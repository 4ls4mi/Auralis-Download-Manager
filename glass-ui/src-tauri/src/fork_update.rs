//! Fork-only Windows updater. Releases and checksums come from the fixed GitHub repository.
use std::{fs::{self, File, OpenOptions}, io::{Read, Write}, path::PathBuf, sync::{Mutex, OnceLock}, time::{Duration, SystemTime, UNIX_EPOCH}};
use serde::Serialize;
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager};

const FEED: &str = "https://api.github.com/repos/4ls4mi/misterdownloadmanager/releases/latest";
const ASSET_PREFIX: &str = "https://github.com/4ls4mi/misterdownloadmanager/releases/download/";
const MAX_BYTES: u64 = 256 * 1024 * 1024;
#[derive(Clone)]
struct Candidate { version: String, notes: String, url: String, sha256: String, size: u64, staged: Option<PathBuf> }
static CANDIDATE: OnceLock<Mutex<Option<Candidate>>> = OnceLock::new();
fn candidate() -> &'static Mutex<Option<Candidate>> { CANDIDATE.get_or_init(|| Mutex::new(None)) }
fn lock() -> Result<std::sync::MutexGuard<'static, Option<Candidate>>, String> { candidate().lock().map_err(|_| "Update state is unavailable".into()) }
#[derive(Serialize)]
pub struct UpdateStatus { state: &'static str, version: Option<String>, notes: Option<String> }
fn client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder().user_agent("MisterHybridGlass/update-check")
        .timeout(Duration::from_secs(180)).build().map_err(|e| e.to_string())
}
fn candidate_from_release(value: &serde_json::Value, current: &str) -> Result<Option<Candidate>, String> {
    let tag = value["tag_name"].as_str().ok_or("The release has no version")?;
    let version = semver::Version::parse(tag.trim_start_matches(['v','V'])).map_err(|_| "The release version is invalid")?;
    let current = semver::Version::parse(current).map_err(|_| "The installed version is invalid")?;
    if version <= current { return Ok(None); }
    let assets=value["assets"].as_array().ok_or("The release has no installer")?;
    let matches: Vec<_> = assets.iter().filter(|asset| {
        let name=asset["name"].as_str().unwrap_or("");
        name.starts_with("Mister.Hybrid.Glass_") && name.ends_with("_x64-setup.exe")
    }).collect();
    if matches.len()!=1 { return Err("This release must contain one Windows x64 Glass installer".into()); }
    let asset=matches[0];
    let url=asset["browser_download_url"].as_str().ok_or("The installer address is missing")?;
    if !url.starts_with(ASSET_PREFIX) || url.contains('?') || url.contains('#') { return Err("The installer is not from the Glass GitHub releases".into()); }
    let digest=asset["digest"].as_str().and_then(|v|v.strip_prefix("sha256:")).ok_or("The release does not provide a SHA-256 digest")?;
    if digest.len()!=64 || !digest.bytes().all(|c|c.is_ascii_hexdigit()) { return Err("The installer digest is invalid".into()); }
    let size=asset["size"].as_u64().filter(|n|*n>0 && *n<=MAX_BYTES).ok_or("The installer size is invalid")?;
    Ok(Some(Candidate{version:version.to_string(),notes:value["body"].as_str().unwrap_or("").to_owned(),url:url.to_owned(),sha256:digest.to_ascii_lowercase(),size,staged:None}))
}
#[tauri::command]
pub async fn glass_update_check() -> Result<UpdateStatus,String> {
    tauri::async_runtime::spawn_blocking(|| {
        let response=client()?.get(FEED).header("Accept","application/vnd.github+json").send().map_err(|e|e.to_string())?;
        if response.status()==reqwest::StatusCode::NOT_FOUND { *lock()?=None; return Ok(UpdateStatus{state:"latest",version:None,notes:None}); }
        let value:serde_json::Value=response.error_for_status().map_err(|e|e.to_string())?.json().map_err(|e|e.to_string())?;
        let next=candidate_from_release(&value,env!("CARGO_PKG_VERSION"))?;
        let status=match &next {Some(c)=>UpdateStatus{state:"available",version:Some(c.version.clone()),notes:Some(c.notes.clone())},None=>UpdateStatus{state:"latest",version:None,notes:None}};
        *lock()?=next; Ok(status)
    }).await.map_err(|e|e.to_string())?
}
fn hash_file(path:&std::path::Path) -> Result<(String,u64),String> {
    let mut f=File::open(path).map_err(|e|e.to_string())?; let mut hash=Sha256::new();let mut buf=[0u8;65536];let mut n=0u64;
    loop {let got=f.read(&mut buf).map_err(|e|e.to_string())?;if got==0{break}n+=got as u64;if n>MAX_BYTES{return Err("Installer is too large".into())}hash.update(&buf[..got]);}
    Ok((format!("{:x}",hash.finalize()),n))
}
#[tauri::command]
pub async fn glass_update_download(app:AppHandle) -> Result<(),String> {
    tauri::async_runtime::spawn_blocking(move || {
        let c=lock()?.clone().ok_or("Check for an update first")?;
        let folder=app.path().app_data_dir().map_err(|e|e.to_string())?.join("updates");fs::create_dir_all(&folder).map_err(|e|e.to_string())?;
        let nonce=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e|e.to_string())?.as_nanos();
        let tmp=folder.join(format!("glass-{nonce}.part")); let final_path=folder.join(format!("glass-{nonce}.exe"));
        let result=(|| -> Result<(),String> {
            let mut source=client()?.get(&c.url).send().map_err(|e|e.to_string())?.error_for_status().map_err(|e|e.to_string())?;
            let mut file=OpenOptions::new().write(true).create_new(true).open(&tmp).map_err(|e|e.to_string())?;
            let mut buf=[0u8;65536];let mut count=0u64;loop{let n=source.read(&mut buf).map_err(|e|e.to_string())?;if n==0{break}count+=n as u64;if count>c.size||count>MAX_BYTES{return Err("Installer size does not match the release".into())}file.write_all(&buf[..n]).map_err(|e|e.to_string())?;}
            file.sync_all().map_err(|e|e.to_string())?;drop(file);
            let (hash,size)=hash_file(&tmp)?;if hash!=c.sha256||size!=c.size{return Err("Installer verification failed".into())}
            fs::rename(&tmp,&final_path).map_err(|e|e.to_string())?;Ok(())
        })();
        if let Err(e)=result {let _=fs::remove_file(&tmp);return Err(e)}
        let mut state=lock()?; let same=state.as_ref().is_some_and(|next|next.url==c.url&&next.sha256==c.sha256);
        if !same {let _=fs::remove_file(&final_path);return Err("The selected release changed; check again".into())}
        state.as_mut().unwrap().staged=Some(final_path);Ok(())
    }).await.map_err(|e|e.to_string())?
}
#[tauri::command]
pub async fn glass_update_install(app:AppHandle) -> Result<(),String> {
    tauri::async_runtime::spawn_blocking(move || {
        use std::os::windows::process::CommandExt;
        let c=lock()?.clone().ok_or("Check for an update first")?;let installer=c.staged.ok_or("Download the update first")?;
        let (hash,size)=hash_file(&installer)?;if hash!=c.sha256||size!=c.size{return Err("The downloaded installer has changed; download again".into())}
        let exe=std::env::current_exe().map_err(|e|e.to_string())?;let dir=exe.parent().ok_or("Application folder is unavailable")?;
        if !dir.join("uninstall.exe").is_file(){return Err("Automatic updates require the installed version of Mister Hybrid Glass".into())}
        // Paths travel as environment variables, never as PowerShell source.
        let script=r#"$ErrorActionPreference='Stop'; $p=[int]$env:MHG_UPDATE_PID; Wait-Process -Id $p -Timeout 90 -ErrorAction SilentlyContinue; if (Get-Process -Id $p -ErrorAction SilentlyContinue) { exit 1 }; $backend=Join-Path (Split-Path $env:MHG_UPDATE_OLD) 'mdm-legacy.exe'; for ($n=0; $n -lt 30; $n++) { $busy=Get-Process -Name 'mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $backend }; if (!$busy) { break }; Start-Sleep -Seconds 1 }; if ($busy) { Start-Process -FilePath $env:MHG_UPDATE_OLD; exit 1 }; try { $x=Start-Process -FilePath $env:MHG_UPDATE_INSTALLER -ArgumentList '/P','/UPDATE','/R' -Wait -PassThru; if ($x.ExitCode -ne 0) { Start-Process -FilePath $env:MHG_UPDATE_OLD } } catch { Start-Process -FilePath $env:MHG_UPDATE_OLD }"#;
        std::process::Command::new("powershell.exe").args(["-NoProfile","-NonInteractive","-WindowStyle","Hidden","-Command",script])
            .env("MHG_UPDATE_PID",std::process::id().to_string()).env("MHG_UPDATE_INSTALLER",&installer).env("MHG_UPDATE_OLD",&exe)
            .creation_flags(0x08000000).spawn().map_err(|e|format!("Could not start the installer: {e}"))?;
        if super::current_backend().is_ok_and(|s|s.glass&&s.headless) {let _=mdm_ipc::send(&mdm_ipc::Command{exit:true,..Default::default()});}
        app.exit(0);Ok(())
    }).await.map_err(|e|e.to_string())?
}
#[cfg(test)]
mod tests {
    use super::*;
    fn release(url:&str,digest:&str)->serde_json::Value {serde_json::json!({"tag_name":"v0.3.2","body":"Changes", "assets":[{"name":"Mister.Hybrid.Glass_0.3.2_x64-setup.exe","browser_download_url":url,"digest":digest,"size":123}]})}
    #[test] fn accepts_only_newer_fork_installer_with_digest(){
        let good=release("https://github.com/4ls4mi/misterdownloadmanager/releases/download/v0.3.2/setup.exe",&format!("sha256:{}","a".repeat(64)));
        assert!(candidate_from_release(&good,"0.3.1").unwrap().is_some());assert!(candidate_from_release(&good,"0.3.2").unwrap().is_none());
        let bad=release("https://evil.example/setup.exe",&format!("sha256:{}","a".repeat(64)));assert!(candidate_from_release(&bad,"0.3.1").is_err());
        let bad=release("https://github.com/4ls4mi/misterdownloadmanager/releases/download/v0.3.2/setup.exe","sha256:bad");assert!(candidate_from_release(&bad,"0.3.1").is_err());
    }
}
