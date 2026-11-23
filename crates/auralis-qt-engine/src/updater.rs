//! Fork-only Windows updater. Releases and checksums come from the fixed GitHub repository.
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::PathBuf,
    sync::{Mutex, OnceLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const FEED: &str =
    "https://api.github.com/repos/4ls4mi/Auralis-Download-Manager/releases?per_page=30";
// The notification service caches metadata from authenticated GitHub release
// webhooks. The installer still comes from GitHub and must match its digest.
const FALLBACK_FEED: &str = "https://auralis-release-push.auralis-updates.workers.dev/latest";
const ASSET_PREFIX: &str = "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/";
const MAX_FEED_BYTES: u64 = 8 * 1024 * 1024;
const MAX_BYTES: u64 = 256 * 1024 * 1024;
#[derive(Clone)]
struct Candidate {
    version: String,
    notes: String,
    url: String,
    sha256: String,
    size: u64,
    staged: Option<PathBuf>,
}
static CANDIDATE: OnceLock<Mutex<Option<Candidate>>> = OnceLock::new();
static TRANSFER: Mutex<Option<TransferProgress>> = Mutex::new(None);

#[derive(Serialize)]
struct TransferProgress {
    state: &'static str,
    version: String,
    downloaded: u64,
    total: u64,
}

fn report_transfer(candidate: &Candidate, state: &'static str, downloaded: u64) {
    if let Ok(mut progress) = TRANSFER.lock() {
        if let Some(progress) = progress
            .as_mut()
            .filter(|value| value.version == candidate.version)
        {
            progress.state = state;
            progress.downloaded = downloaded;
            progress.total = candidate.size;
        } else {
            *progress = Some(TransferProgress {
                state,
                version: candidate.version.clone(),
                downloaded,
                total: candidate.size,
            });
        }
    }
}

fn candidate() -> &'static Mutex<Option<Candidate>> {
    CANDIDATE.get_or_init(|| Mutex::new(None))
}
fn lock() -> Result<std::sync::MutexGuard<'static, Option<Candidate>>, String> {
    candidate()
        .lock()
        .map_err(|_| "Update state is unavailable".into())
}
#[derive(Serialize)]
pub struct UpdateStatus {
    state: &'static str,
    version: Option<String>,
    notes: Option<String>,
    size: Option<u64>,
}
fn client(
    timeout: Duration,
    redirect: reqwest::redirect::Policy,
) -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .user_agent("AuralisDownloadManager/update-check")
        .https_only(true)
        .redirect(redirect)
        .connect_timeout(Duration::from_secs(8))
        .timeout(timeout)
        .build()
        .map_err(|e| e.to_string())
}
fn installer_redirect(url: &reqwest::Url, previous: &[reqwest::Url]) -> bool {
    previous.len() == 1
        && previous[0].host_str() == Some("github.com")
        && url.scheme() == "https"
        && url.host_str() == Some("release-assets.githubusercontent.com")
        && url.port().is_none()
        && url.username().is_empty()
        && url.password().is_none()
}

fn candidate_from_release(
    value: &serde_json::Value,
    current: &str,
) -> Result<Option<Candidate>, String> {
    let Some(tag) = value["tag_name"].as_str() else {
        return Ok(None);
    };
    let number = tag
        .strip_prefix('v')
        .or_else(|| tag.strip_prefix('V'))
        .unwrap_or(tag);
    let Ok(version) = semver::Version::parse(number) else {
        return Ok(None);
    };
    let current =
        semver::Version::parse(current).map_err(|_| "The installed version is invalid")?;
    if version <= current || !version.pre.is_empty() || !version.build.is_empty() {
        return Ok(None);
    }
    // This repository also carries upstream MDM releases. Only releases with the Auralis
    // installer are update candidates; an unrelated newer MDM tag must never block this fork.
    let Some(assets) = value["assets"].as_array() else {
        return Ok(None);
    };
    let expected_names = [
        format!("Auralis.Download.Manager_{}_x64-setup.exe", version),
        format!("Auralis Download Manager_{}_x64-setup.exe", version),
    ];
    let matches: Vec<_> = assets
        .iter()
        .filter_map(|asset| {
            let name = asset["name"].as_str()?;
            expected_names
                .iter()
                .any(|expected| expected == name)
                .then_some((asset, name))
        })
        .collect();
    if matches.is_empty() {
        return Ok(None);
    }
    if matches.len() != 1 {
        return Err("This Auralis release must contain exactly one Windows x64 installer".into());
    }
    let (asset, name) = matches[0];
    let url = asset["browser_download_url"]
        .as_str()
        .ok_or("The installer address is missing")?;
    let canonical_url = format!("{ASSET_PREFIX}{tag}/{}", name.replace(' ', "%20"));
    if url != canonical_url && url != format!("{ASSET_PREFIX}{tag}/{name}") {
        return Err(
            "The installer address does not match the Auralis release version and asset".into(),
        );
    }
    let digest = asset["digest"]
        .as_str()
        .and_then(|v| v.strip_prefix("sha256:"))
        .ok_or("The release does not provide a SHA-256 digest")?;
    if digest.len() != 64 || !digest.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err("The installer digest is invalid".into());
    }
    let size = asset["size"]
        .as_u64()
        .filter(|n| *n > 0 && *n <= MAX_BYTES)
        .ok_or("The installer size is invalid")?;
    Ok(Some(Candidate {
        version: version.to_string(),
        notes: value["body"].as_str().unwrap_or("").to_owned(),
        url: canonical_url,
        sha256: digest.to_ascii_lowercase(),
        size,
        staged: None,
    }))
}
fn release_feed(
    client: &reqwest::blocking::Client,
    primary: &str,
    fallback: &str,
) -> Result<serde_json::Value, String> {
    let fetch = |url: &str| -> Result<serde_json::Value, String> {
        let response = client
            .get(url)
            .header("Accept", "application/json")
            .send()
            .map_err(|e| e.to_string())?;
        let response = response.error_for_status().map_err(|e| e.to_string())?;
        let mut bytes = Vec::new();
        response
            .take(MAX_FEED_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        if bytes.len() as u64 > MAX_FEED_BYTES {
            return Err("The release feed exceeds its size limit".into());
        }
        let value: serde_json::Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        if !value.is_array() {
            return Err("The release feed is invalid".into());
        }
        Ok(value)
    };
    match fetch(primary) {
        Ok(value) => Ok(value),
        Err(error) => fetch(fallback).map_err(|_| {
            format!("Update check unavailable (GitHub: {error}). Try again later or download the latest release from GitHub.")
        }),
    }
}
fn check(current: &str) -> Result<UpdateStatus, String> {
    semver::Version::parse(current).map_err(|_| "The installed version is invalid")?;
    let value = release_feed(
        &client(Duration::from_secs(12), reqwest::redirect::Policy::none())?,
        FEED,
        FALLBACK_FEED,
    )?;
    let releases = value
        .as_array()
        .ok_or("The GitHub release feed is invalid")?;
    let mut next: Option<Candidate> = None;
    for release in releases {
        if release["draft"].as_bool() != Some(false)
            || release["prerelease"].as_bool() != Some(false)
        {
            continue;
        }
        if let Some(candidate) = candidate_from_release(release, current)? {
            let replace = match next.as_ref() {
                None => true,
                Some(old) => {
                    semver::Version::parse(&candidate.version).map_err(|e| e.to_string())?
                        > semver::Version::parse(&old.version).map_err(|e| e.to_string())?
                }
            };
            if replace {
                next = Some(candidate);
            }
        }
    }
    let status = match &next {
        Some(c) => UpdateStatus {
            state: "available",
            version: Some(c.version.clone()),
            notes: Some(c.notes.clone()),
            size: Some(c.size),
        },
        None => UpdateStatus {
            state: "latest",
            version: None,
            notes: None,
            size: None,
        },
    };
    let mut state = lock()?;
    if let Some(old) = state.as_mut() {
        if let Some(new) = next
            .as_mut()
            .filter(|new| new.url == old.url && new.sha256 == old.sha256 && new.size == old.size)
        {
            new.staged = old.staged.take();
        } else if let Some(staged) = old.staged.take() {
            let _ = fs::remove_file(staged);
        }
    }
    *state = next;
    Ok(status)
}
fn hash_file(path: &std::path::Path) -> Result<(String, u64), String> {
    let mut f = File::open(path).map_err(|e| e.to_string())?;
    let mut hash = Sha256::new();
    let mut buf = [0u8; 65536];
    let mut n = 0u64;
    loop {
        let got = f.read(&mut buf).map_err(|e| e.to_string())?;
        if got == 0 {
            break;
        }
        n += got as u64;
        if n > MAX_BYTES {
            return Err("Installer is too large".into());
        }
        hash.update(&buf[..got]);
    }
    Ok((hex::encode(hash.finalize()), n))
}
fn selected_candidate(version: &str) -> Result<Candidate, String> {
    let current = lock()?;
    let candidate = current.as_ref().ok_or("Check for an update first")?;
    if candidate.version != version {
        return Err("The selected release changed; check again".into());
    }
    Ok(candidate.clone())
}

fn copy_installer(
    mut source: impl Read,
    mut destination: impl Write,
    expected_size: u64,
    mut bytes_written: impl FnMut(u64),
) -> Result<(), String> {
    let mut buffer = [0u8; 65536];
    let mut count = 0u64;
    loop {
        let amount = source
            .read(&mut buffer)
            .map_err(|error| error.to_string())?;
        if amount == 0 {
            break;
        }
        count += amount as u64;
        if count > expected_size || count > MAX_BYTES {
            return Err("Installer size does not match the release".into());
        }
        destination
            .write_all(&buffer[..amount])
            .map_err(|error| error.to_string())?;
        bytes_written(count);
    }
    if count != expected_size {
        return Err("Installer size does not match the release".into());
    }
    Ok(())
}

fn stage_installer(c: &Candidate) -> Result<PathBuf, String> {
    // Custom download profiles can be shared or portable. The installer belongs
    // in the Windows user's own profile, independent of the download state.
    let folder = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .ok_or("The Windows user profile is unavailable")?
        .join("Auralis Download Manager Updates");
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let tmp = folder.join(format!("auralis-update-{nonce}.part"));
    let final_path = folder.join(format!("auralis-update-{nonce}.exe"));
    let result = (|| -> Result<(), String> {
        let redirect = reqwest::redirect::Policy::custom(|attempt| {
            if installer_redirect(attempt.url(), attempt.previous()) {
                attempt.follow()
            } else {
                attempt.error("Unexpected installer download redirect")
            }
        });
        let source = client(Duration::from_secs(180), redirect)?
            .get(&c.url)
            .send()
            .map_err(|e| e.without_url().to_string())?
            .error_for_status()
            .map_err(|e| e.without_url().to_string())?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp)
            .map_err(|e| e.to_string())?;
        copy_installer(source, &mut file, c.size, |bytes| {
            report_transfer(c, "downloading", bytes)
        })?;
        report_transfer(c, "verifying", c.size);
        file.sync_all().map_err(|e| e.to_string())?;
        drop(file);
        let (hash, size) = hash_file(&tmp)?;
        if hash != c.sha256 || size != c.size {
            return Err("Installer verification failed".into());
        }
        fs::rename(&tmp, &final_path).map_err(|e| e.to_string())?;
        Ok(())
    })();
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(final_path)
}

fn download(version: &str) -> Result<u64, String> {
    let c = selected_candidate(version)?;
    report_transfer(&c, "connecting", 0);
    let result = (|| {
        let staged = stage_installer(&c)?;
        let mut state = lock()?;
        let Some(next) = state
            .as_mut()
            .filter(|next| next.url == c.url && next.sha256 == c.sha256 && next.size == c.size)
        else {
            let _ = fs::remove_file(staged);
            return Err("The selected release changed; check again".into());
        };
        if let Some(previous) = next.staged.replace(staged) {
            let _ = fs::remove_file(previous);
        }
        Ok(c.size)
    })();
    report_transfer(
        &c,
        if result.is_ok() { "ready" } else { "failed" },
        if result.is_ok() { c.size } else { 0 },
    );
    result
}

#[cfg(windows)]
fn system_directory() -> Result<PathBuf, String> {
    use std::{ffi::OsString, os::windows::ffi::OsStringExt};

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetSystemDirectoryW(buffer: *mut u16, size: u32) -> u32;
    }

    let mut buffer = [0_u16; 260];
    // Windows writes at most the supplied number of UTF-16 code units.
    let length = unsafe { GetSystemDirectoryW(buffer.as_mut_ptr(), buffer.len() as u32) } as usize;
    if length == 0 || length >= buffer.len() {
        return Err("The Windows system folder is unavailable".into());
    }
    Ok(PathBuf::from(OsString::from_wide(&buffer[..length])))
}

#[cfg(windows)]
fn install(version: &str) -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    let c = selected_candidate(version)?;
    let installer = c.staged.ok_or("Download the update first")?;
    let (hash, size) = hash_file(&installer)?;
    if hash != c.sha256 || size != c.size {
        return Err("The downloaded installer has changed; download again".into());
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dir = exe.parent().ok_or("Application folder is unavailable")?;
    if !dir.join("uninstall.exe").is_file() {
        return Err(
            "Automatic updates require the installed version of Auralis Download Manager".into(),
        );
    }
    let system = system_directory()?;
    // Paths and integrity data travel as environment variables, never as PowerShell source.
    std::process::Command::new(system.join("WindowsPowerShell/v1.0/powershell.exe"))
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-WindowStyle",
            "Hidden",
            "-Command",
            include_str!("install-update.ps1"),
        ])
        .current_dir(system)
        .env("AURALIS_UPDATE_PID", std::process::id().to_string())
        .env("AURALIS_UPDATE_INSTALLER", &installer)
        .env("AURALIS_UPDATE_OLD", &exe)
        .env("AURALIS_UPDATE_SHA256", &c.sha256)
        .env("AURALIS_UPDATE_SIZE", c.size.to_string())
        .creation_flags(0x08000000)
        .spawn()
        .map_err(|e| format!("Could not start the installer: {e}"))?;
    Ok(())
}
#[cfg(windows)]
pub(super) fn dispatch(
    action: &str,
    request: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    let version = || {
        request
            .get("expectedVersion")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| String::from("Select an update version first"))
    };
    match action {
        "update-check" => {
            let current = request
                .get("currentVersion")
                .and_then(serde_json::Value::as_str)
                .ok_or("The installed version is unavailable")?;
            serde_json::to_value(check(current)?).map_err(|error| error.to_string())
        }
        "update-progress" => TRANSFER
            .lock()
            .map_err(|_| String::from("Update progress is unavailable"))
            .and_then(|progress| {
                serde_json::to_value(progress.as_ref()).map_err(|error| error.to_string())
            }),
        "update-download" => {
            download(version()?).map(|size| serde_json::json!({ "ok": true, "size": size }))
        }
        "update-install" => install(version()?).map(|()| serde_json::json!({ "ok": true })),
        _ => Err("Unsupported release update operation".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const LEGACY_URL: &str = "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.2/Auralis%20Download%20Manager_0.3.2_x64-setup.exe";
    const RELEASE_URL: &str = "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.2/Auralis.Download.Manager_0.3.2_x64-setup.exe";

    fn release(url: &str, digest: &str) -> serde_json::Value {
        serde_json::json!({"tag_name":"v0.3.2","body":"Changes", "assets":[{"name":"Auralis Download Manager_0.3.2_x64-setup.exe","browser_download_url":url,"digest":digest,"size":123}]})
    }
    #[test]
    fn accepts_only_newer_fork_installer_with_digest() {
        let digest = format!("sha256:{}", "a".repeat(64));
        let good = release(LEGACY_URL, &digest);
        assert_eq!(
            candidate_from_release(&good, "0.3.1").unwrap().unwrap().url,
            LEGACY_URL
        );
        assert!(candidate_from_release(&good, "0.3.2").unwrap().is_none());
        let mut published = good.clone();
        published["assets"][0]["name"] =
            serde_json::json!("Auralis.Download.Manager_0.3.2_x64-setup.exe");
        published["assets"][0]["browser_download_url"] = serde_json::json!(RELEASE_URL);
        assert!(
            candidate_from_release(&published, "0.3.1")
                .unwrap()
                .is_some()
        );
        let mut wrong = good.clone();
        wrong["assets"][0]["name"] = serde_json::json!("MisterDownloadManager-0.9.0-setup.exe");
        assert!(candidate_from_release(&wrong, "0.3.1").unwrap().is_none());
        let other_artifact = release(RELEASE_URL, &digest);
        assert!(candidate_from_release(&other_artifact, "0.3.1").is_err());
        let other_tag = release(&LEGACY_URL.replace("/v0.3.2/", "/v0.3.1/"), &digest);
        assert!(candidate_from_release(&other_tag, "0.3.1").is_err());
        let invalid_digest = release(LEGACY_URL, "sha256:bad");
        assert!(candidate_from_release(&invalid_digest, "0.3.1").is_err());
    }

    #[test]
    fn only_follows_the_github_asset_cdn_handoff() {
        let parse = |url| reqwest::Url::parse(url).unwrap();
        let asset = parse(RELEASE_URL);
        let cdn =
            parse("https://release-assets.githubusercontent.com/github-production-release-asset");
        assert!(installer_redirect(&cdn, std::slice::from_ref(&asset)));
        assert!(!installer_redirect(&asset, std::slice::from_ref(&cdn)));
        assert!(!installer_redirect(&cdn, &[asset.clone(), cdn.clone()]));
        assert!(!installer_redirect(
            &parse("http://release-assets.githubusercontent.com/"),
            &[asset]
        ));
    }

    #[test]
    fn reports_only_bytes_written_and_requires_the_release_size() {
        let data = vec![42_u8; 96 * 1024];
        let mut file = Vec::new();
        let mut seen = Vec::new();
        copy_installer(data.as_slice(), &mut file, data.len() as u64, |bytes| {
            seen.push(bytes)
        })
        .unwrap();
        assert_eq!(file, data);
        assert_eq!(seen, [64 * 1024, 96 * 1024]);

        for incorrect_size in [data.len() - 1, data.len() + 1] {
            let size_error = copy_installer(
                data.as_slice(),
                std::io::sink(),
                incorrect_size as u64,
                |_| {},
            );
            assert!(size_error.is_err());
        }
    }

    #[test]
    fn uses_fallback_when_primary_is_rate_limited() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
            thread,
        };
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            for index in 0..2 {
                let (mut socket, _) = listener.accept().unwrap();
                let mut buffer = [0; 2048];
                let _ = socket.read(&mut buffer);
                let (status, body) = if index == 0 {
                    ("403 Forbidden", "rate limited")
                } else {
                    ("200 OK", "[]")
                };
                write!(
                    socket,
                    "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                )
                .unwrap();
            }
        });
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap();
        let url = format!("http://{address}/");
        assert_eq!(
            release_feed(&client, &url, &url).unwrap(),
            serde_json::json!([])
        );
        server.join().unwrap();
    }
}
