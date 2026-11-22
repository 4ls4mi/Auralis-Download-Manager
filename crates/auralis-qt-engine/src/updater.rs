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
fn client(timeout: Duration) -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .user_agent("AuralisDownloadManager/update-check")
        .connect_timeout(Duration::from_secs(8))
        .timeout(timeout)
        .build()
        .map_err(|e| e.to_string())
}
fn candidate_from_release(
    value: &serde_json::Value,
    current: &str,
) -> Result<Option<Candidate>, String> {
    let Some(tag) = value["tag_name"].as_str() else {
        return Ok(None);
    };
    let Ok(version) = semver::Version::parse(tag.trim_start_matches(['v', 'V'])) else {
        return Ok(None);
    };
    let current =
        semver::Version::parse(current).map_err(|_| "The installed version is invalid")?;
    if version <= current {
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
        .filter(|asset| {
            asset["name"]
                .as_str()
                .is_some_and(|name| expected_names.iter().any(|expected| expected == name))
        })
        .collect();
    if matches.is_empty() {
        return Ok(None);
    }
    if matches.len() != 1 {
        return Err("This Auralis release must contain exactly one Windows x64 installer".into());
    }
    let asset = matches[0];
    let url = asset["browser_download_url"]
        .as_str()
        .ok_or("The installer address is missing")?;
    if !url.starts_with(ASSET_PREFIX) || url.contains('?') || url.contains('#') {
        return Err("The installer is not from the Auralis GitHub releases".into());
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
        url: url.to_owned(),
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
        let value: serde_json::Value = response
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .map_err(|e| e.to_string())?;
        if !value.is_array() {
            return Err("The release feed is invalid".into());
        }
        Ok(value)
    };
    match fetch(primary) {
        Ok(value)=>Ok(value),
        Err(error)=>fetch(fallback).map_err(|_|format!("Update check unavailable (GitHub: {error}); try again later or download the latest release from GitHub.")),
    }
}
fn check(current: &str) -> Result<UpdateStatus, String> {
    semver::Version::parse(current).map_err(|_| "The installed version is invalid")?;
    let value = release_feed(&client(Duration::from_secs(12))?, FEED, FALLBACK_FEED)?;
    let releases = value
        .as_array()
        .ok_or("The GitHub release feed is invalid")?;
    let mut next: Option<Candidate> = None;
    for release in releases {
        if release["draft"] == true || release["prerelease"] == true {
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
    if let (Some(new), Some(old)) = (&mut next, state.as_ref()) {
        if new.url == old.url && new.sha256 == old.sha256 {
            new.staged = old.staged.clone();
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
    let folder = mdm_ipc::data_dir()
        .ok_or("The application profile is unavailable")?
        .join("updates");
    mdm_ipc::private_dir(&folder).map_err(|e| e.to_string())?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let tmp = folder.join(format!("glass-{nonce}.part"));
    let final_path = folder.join(format!("glass-{nonce}.exe"));
    let result = (|| -> Result<(), String> {
        let source = client(Duration::from_secs(180))?
            .get(&c.url)
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?;
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
            .filter(|next| next.url == c.url && next.sha256 == c.sha256)
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
    // Paths travel as environment variables, never as PowerShell source.
    let script = r#"$ErrorActionPreference='Stop'; $p=[int]$env:MHG_UPDATE_PID; Wait-Process -Id $p -Timeout 90 -ErrorAction SilentlyContinue; if (Get-Process -Id $p -ErrorAction SilentlyContinue) { exit 1 }; $backend=Join-Path (Split-Path $env:MHG_UPDATE_OLD) 'mdm-legacy.exe'; for ($n=0; $n -lt 30; $n++) { $busy=Get-Process -Name 'mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $backend }; if (!$busy) { break }; Start-Sleep -Seconds 1 }; if ($busy) { Start-Process -FilePath $env:MHG_UPDATE_OLD; exit 1 }; try { $x=Start-Process -FilePath $env:MHG_UPDATE_INSTALLER -ArgumentList '/P','/UPDATE','/R' -PassThru; $x.WaitForExit(); if ($x.ExitCode -ne 0) { Start-Process -FilePath $env:MHG_UPDATE_OLD } } catch { Start-Process -FilePath $env:MHG_UPDATE_OLD }"#;
    std::process::Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-WindowStyle",
            "Hidden",
            "-Command",
            script,
        ])
        .env("MHG_UPDATE_PID", std::process::id().to_string())
        .env("MHG_UPDATE_INSTALLER", &installer)
        .env("MHG_UPDATE_OLD", &exe)
        .creation_flags(0x08000000)
        .spawn()
        .map_err(|e| format!("Could not start the installer: {e}"))?;
    Ok(())
}
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
    fn release(url: &str, digest: &str) -> serde_json::Value {
        serde_json::json!({"tag_name":"v0.3.2","body":"Changes", "assets":[{"name":"Auralis Download Manager_0.3.2_x64-setup.exe","browser_download_url":url,"digest":digest,"size":123}]})
    }
    #[test]
    fn accepts_only_newer_fork_installer_with_digest() {
        let good = release(
            "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.2/setup.exe",
            &format!("sha256:{}", "a".repeat(64)),
        );
        assert!(candidate_from_release(&good, "0.3.1").unwrap().is_some());
        assert!(candidate_from_release(&good, "0.3.2").unwrap().is_none());
        let mut published = good.clone();
        published["assets"][0]["name"] =
            serde_json::json!("Auralis.Download.Manager_0.3.2_x64-setup.exe");
        assert!(
            candidate_from_release(&published, "0.3.1")
                .unwrap()
                .is_some()
        );
        let mut wrong = good.clone();
        wrong["assets"][0]["name"] = serde_json::json!("MisterDownloadManager-0.9.0-setup.exe");
        assert!(candidate_from_release(&wrong, "0.3.1").unwrap().is_none());
        let bad = release(
            "https://evil.example/setup.exe",
            &format!("sha256:{}", "a".repeat(64)),
        );
        assert!(candidate_from_release(&bad, "0.3.1").is_err());
        let bad = release(
            "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.2/setup.exe",
            "sha256:bad",
        );
        assert!(candidate_from_release(&bad, "0.3.1").is_err());
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
