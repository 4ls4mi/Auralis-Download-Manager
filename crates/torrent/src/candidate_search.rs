//! Search hints for recovery. A search result is never evidence of file identity;
//! torrent piece hashes must be checked against the saved bytes separately.
//!
//! Calling this service discloses the search terms to Internet Archive. Callers
//! must obtain the user's consent before searching.

use mdm_engine::download::{Options, hop_client};
use url::Url;

const SEARCH_URL: &str = "https://archive.org/advancedsearch.php";
const MAX_RESPONSE: usize = 512 * 1024;
const MAX_RESULTS: usize = 20;
const MAX_REDIRECTS: usize = 5;
const MAX_SAME_SIZE_FILES: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub identifier: String,
    pub title: String,
    pub torrent_url: Url,
}

/// A candidate file whose available, complete pieces match the saved bytes.
/// The unmatched bytes are still unknown and must not be considered verified.
#[derive(Debug)]
pub struct MatchingFile {
    pub file_index: usize,
    pub path: std::path::PathBuf,
    pub evidence: mdm_engine::recovery::PieceComparison,
}

/// Metadata for a candidate with at least one matching local piece. Holding the
/// metadata lets a caller recheck it before staging without trusting a later
/// response for the same URL.
#[derive(Debug)]
pub struct MatchedCandidate {
    pub candidate: Candidate,
    pub info_hash: String,
    pub torrent: Vec<u8>,
    pub files: Vec<MatchingFile>,
}

#[derive(Debug, Default)]
pub struct SearchReport {
    pub searched: usize,
    pub failed: usize,
    pub matches: Vec<MatchedCandidate>,
}

fn archive_download_url(url: &Url) -> bool {
    url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.port_or_known_default() == Some(443)
        && url
            .host_str()
            .is_some_and(|host| host == "archive.org" || host.ends_with(".archive.org"))
}

/// Fetch torrent metadata only from Internet Archive and its HTTPS download
/// hosts. Search candidates may redirect, so every hop is checked and no
/// download cookies or authorization headers are supplied.
pub async fn fetch_archive_torrent(
    candidate: &Candidate,
    opts: &Options,
) -> Result<Vec<u8>, String> {
    let mut url = candidate.torrent_url.clone();
    for hop in 0..=MAX_REDIRECTS {
        if !archive_download_url(&url) {
            return Err("Torrent metadata redirected outside Internet Archive".into());
        }
        let client = hop_client(opts, &url).map_err(|e| e.to_string())?;
        let mut response = client
            .get(url.clone())
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if response.status().is_redirection() {
            if hop == MAX_REDIRECTS {
                return Err("Too many torrent metadata redirects".into());
            }
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .ok_or("Torrent metadata redirect has no valid location")?;
            url = url
                .join(location)
                .map_err(|_| "Invalid torrent metadata redirect")?;
            continue;
        }
        response = response.error_for_status().map_err(|e| e.to_string())?;
        if response
            .content_length()
            .is_some_and(|size| size > crate::MAX_TORRENT_FILE)
        {
            return Err("Torrent metadata is too large".into());
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|e| e.to_string())? {
            if bytes.len().saturating_add(chunk.len()) > crate::MAX_TORRENT_FILE as usize {
                return Err("Torrent metadata is too large".into());
            }
            bytes.extend_from_slice(&chunk);
        }
        // Parse and validate names before returning data to the recovery flow.
        crate::files_from_bytes(&bytes).map_err(|e| e.to_string())?;
        return Ok(bytes);
    }
    Err("Too many torrent metadata redirects".into())
}

/// Compare all plausible same-size files in a candidate. The operation reads
/// local data and should run off the UI thread. A single matching piece is
/// evidence only about that piece; a caller must explain the residual risk.
pub fn matching_files(
    torrent: &[u8],
    saved: &mdm_engine::state::ResumeState,
) -> Result<Vec<MatchingFile>, String> {
    if torrent.len() as u64 > crate::MAX_TORRENT_FILE {
        return Err("Torrent metadata is too large".into());
    }
    let _reservation =
        mdm_engine::naming::reserve(&saved.dest).ok_or("The saved download is in use")?;
    let files = crate::files_from_bytes(torrent).map_err(|e| e.to_string())?;
    let choices: Vec<_> = files
        .into_iter()
        .enumerate()
        .filter(|(_, f)| !f.padding && f.size == saved.size)
        .collect();
    if choices.len() > MAX_SAME_SIZE_FILES {
        return Err("Torrent contains too many same-size files to check safely".into());
    }
    let mut matches = Vec::new();
    for (file_index, file) in choices {
        let evidence = crate::compare_saved_torrent_file(torrent, saved, file_index)
            .map_err(|e| e.to_string())?;
        if !evidence.matching.is_empty() && evidence.mismatching.is_empty() {
            matches.push(MatchingFile {
                file_index,
                path: file.path,
                evidence,
            });
        }
    }
    Ok(matches)
}

fn candidate_usable(torrent: &[u8], size: u64) -> bool {
    crate::metadata_from_bytes(torrent).is_ok()
        && crate::files_from_bytes(torrent).is_ok_and(|files| {
            files.iter().filter(|file| !file.padding && file.size == size).count()
                <= MAX_SAME_SIZE_FILES
        })
}

/// Query one public index and compare its candidates with the saved ranges.
/// The caller must first inform the user that search terms leave the computer.
/// A caller must recheck before staging, since the local file can change later.
pub async fn find_archive_matches(
    name: &str,
    saved: &mdm_engine::state::ResumeState,
    opts: &Options,
) -> Result<SearchReport, String> {
    let candidates = search_archive(name, opts).await?;
    let mut report = SearchReport::default();
    for candidate in candidates {
        report.searched += 1;
        let metadata = tokio::time::timeout(
            std::time::Duration::from_secs(15),
            fetch_archive_torrent(&candidate, opts),
        )
        .await;
        let torrent = match metadata {
            Ok(Ok(torrent)) => torrent,
            _ => {
                report.failed += 1;
                continue;
            }
        };
        // An unusable candidate must not prevent later candidates from being
        // checked. Keep local I/O failures from the comparison itself fatal,
        // so an inaccessible saved download is not mistaken for no matches.
        if !candidate_usable(&torrent, saved.size) {
            report.failed += 1;
            continue;
        }
        let saved_copy = saved.clone();
        let result = tokio::task::spawn_blocking(move || {
            let files = matching_files(&torrent, &saved_copy)?;
            let hash = crate::metadata_from_bytes(&torrent).map_err(|e|e.to_string())?.info_hash;
            Ok::<_, String>((torrent, files, hash))
        })
        .await
        .map_err(|_| "Torrent comparison task failed")?;
        let (torrent, files, info_hash) = result?;
        if !files.is_empty() {
            report.matches.push(MatchedCandidate {
                candidate,
                info_hash,
                torrent,
                files,
            });
            if report.matches.len() == 3 {
                break;
            }
        }
    }
    Ok(report)
}

/// Build a restricted query from a file name, excluding query syntax and paths.
/// A filename is sent to a third party; the caller controls consent and policy.
fn search_terms(name: &str) -> Result<String, String> {
    let name = name.rsplit(['/', '\\']).next().unwrap_or("");
    // Archive indexes item titles, which rarely contain a download's extension.
    // Preserve unknown suffixes (including version numbers) as search terms.
    let name = match name.rsplit_once('.') {
        Some((stem, extension))
            if [
                "zip", "7z", "rar", "tar", "gz", "xz", "iso", "exe", "msi", "pdf", "epub", "mp4",
                "mkv", "webm", "mov", "avi", "mp3", "flac", "wav", "apk", "torrent",
            ]
            .iter()
            .any(|known| extension.eq_ignore_ascii_case(known)) =>
        {
            stem
        }
        _ => name,
    };
    let tokens: Vec<_> = name
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| s.chars().count() >= 2)
        .take(12)
        .map(|s| s.chars().take(48).collect::<String>())
        .collect();
    if tokens.is_empty() {
        return Err("The file name has no searchable words".into());
    }
    Ok(tokens.join(" "))
}

fn parse_candidates(bytes: &[u8]) -> Result<Vec<Candidate>, String> {
    let json: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| "Invalid search response")?;
    let docs = json
        .pointer("/response/docs")
        .and_then(|v| v.as_array())
        .ok_or("Invalid search response")?;
    let mut candidates = Vec::new();
    for doc in docs.iter().take(MAX_RESULTS) {
        let Some(id) = doc.get("identifier").and_then(|v| v.as_str()) else {
            continue;
        };
        if id.is_empty()
            || id.len() > 100
            || id.contains("..")
            || !id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
        {
            continue;
        }
        let title = doc
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or(id)
            .chars()
            .take(300)
            .collect();
        let mut torrent_url = Url::parse("https://archive.org/download/").expect("fixed URL");
        torrent_url
            .path_segments_mut()
            .expect("base URL")
            .pop_if_empty()
            .push(id)
            .push(&format!("{id}_archive.torrent"));
        candidates.push(Candidate {
            identifier: id.to_owned(),
            title,
            torrent_url,
        });
    }
    Ok(candidates)
}

/// Search Internet Archive's item index for possible candidates. Results are hints,
/// not authenticated matches; the provider may not index the requested file.
pub async fn search_archive(name: &str, opts: &Options) -> Result<Vec<Candidate>, String> {
    let terms = search_terms(name)?;
    let mut url = Url::parse(SEARCH_URL).expect("fixed URL");
    url.query_pairs_mut()
        .append_pair(
            "q",
            &format!("title:({terms}) AND format:\"Archive BitTorrent\""),
        )
        .append_pair("fl[]", "identifier")
        .append_pair("fl[]", "title")
        .append_pair("rows", "20")
        .append_pair("output", "json");
    let client = hop_client(opts, &url).map_err(|e| e.to_string())?;
    let mut response = client
        .get(url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .error_for_status()
        .map_err(|e| e.to_string())?;
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|e| e.to_string())? {
        if body.len().saturating_add(chunk.len()) > MAX_RESPONSE {
            return Err("Search response is too large".into());
        }
        body.extend_from_slice(&chunk);
    }
    parse_candidates(&body)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn candidate_screen_rejects_bad_metadata_without_rejecting_valid_candidates() {
        let mut valid = b"d4:infod6:lengthi4e4:name1:x12:piece lengthi4e6:pieces20:".to_vec();
        valid.extend_from_slice(&[0; 20]);
        valid.extend_from_slice(b"ee");
        assert!(!candidate_usable(b"not a torrent", 4));
        assert!(candidate_usable(&valid, 4));
    }
    #[test]
    fn query_cannot_inject_search_syntax_or_include_directories() {
        assert_eq!(
            search_terms(r"C:\private\example-video (2024).mp4").unwrap(),
            "example video 2024"
        );
        assert_eq!(search_terms("Example.v12").unwrap(), "Example v12");
        assert!(search_terms("a.x").is_err());
    }
    #[test]
    fn candidates_reject_unsafe_ids_and_are_only_hints() {
        let body = br#"{"response":{"docs":[{"identifier":"valid-id","title":"Example"},{"identifier":"../unsafe"},{"identifier":"x/y"}]}}"#;
        let results = parse_candidates(body).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(
            results[0].torrent_url.as_str(),
            "https://archive.org/download/valid-id/valid-id_archive.torrent"
        );
        assert!(parse_candidates(b"{}").is_err());
    }
    #[test]
    fn metadata_redirects_are_confined_to_archive_https_hosts() {
        for valid in [
            "https://archive.org/download/item/file",
            "https://ia800000.us.archive.org/file",
        ] {
            assert!(archive_download_url(&Url::parse(valid).unwrap()));
        }
        for invalid in [
            "http://archive.org/file",
            "https://archive.org.evil.example/file",
            "https://evilarchive.org/file",
            "https://user@archive.org/file",
            "https://archive.org:444/file",
        ] {
            assert!(!archive_download_url(&Url::parse(invalid).unwrap()));
        }
    }
}
