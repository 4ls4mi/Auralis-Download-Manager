#![allow(unsafe_code)] // C ABI boundary; pointer ownership is documented below.
//! Narrow native boundary for the future WinUI shell. It is not connected to
//! the development preview yet. Do not expose arbitrary IPC commands to a webview.
use std::{ffi::{c_char, CString}, sync::{Mutex, OnceLock}, thread::{self, JoinHandle}, time::{Duration, Instant}};

static ENGINE: OnceLock<Mutex<Option<JoinHandle<Result<(), String>>>>> = OnceLock::new();
// The development host must explicitly choose its private test data
// directory before starting. It cannot attach to an installed app's data.
static ISOLATED_DATA: OnceLock<std::path::PathBuf> = OnceLock::new();
static ISOLATED_DATA_CANONICAL: OnceLock<std::path::PathBuf> = OnceLock::new();
fn same_path(left: &std::path::Path, right: &std::path::Path) -> bool {
    if cfg!(windows) { left.to_string_lossy().eq_ignore_ascii_case(&right.to_string_lossy()) } else { left==right }
}
fn remember_isolated_data(path: &std::path::Path) -> Result<(), String> {
    let canonical=path.canonicalize().map_err(|e|e.to_string())?;
    ISOLATED_DATA_CANONICAL.set(canonical).map_err(|_|"Downloader data was already initialized.")?;
    ISOLATED_DATA.set(path.to_path_buf()).map_err(|_|"Downloader data was already initialized.")
}
fn prepare_test_output(data: &std::path::Path, expected: &std::path::Path) -> Result<std::path::PathBuf, String> {
    let current=data.canonicalize().map_err(|_|"The development profile is unavailable.")?;
    if !same_path(&current,expected) { return Err("The development profile was redirected.".into()); }
    let output=data.join("downloads");
    match std::fs::create_dir(&output) {
        Ok(()) => (),
        Err(error) if error.kind()==std::io::ErrorKind::AlreadyExists => (),
        Err(error) => return Err(format!("Cannot create the test downloads folder: {error}")),
    }
    let meta=std::fs::symlink_metadata(&output).map_err(|e|e.to_string())?;
    let resolved=output.canonicalize().map_err(|e|e.to_string())?;
    if meta.file_type().is_symlink() || !meta.is_dir() || !same_path(&resolved,&expected.join("downloads")) {
        return Err("The test downloads folder cannot be redirected.".into());
    }
    Ok(output)
}
fn test_output_dir() -> Result<std::path::PathBuf, String> {
    let data=ISOLATED_DATA.get().ok_or("The isolated test folder is unavailable.")?;
    let canonical=ISOLATED_DATA_CANONICAL.get().ok_or("The isolated test folder is unavailable.")?;
    prepare_test_output(data,canonical)
}
fn initialize_sandbox() -> Result<serde_json::Value, String> {
    let worker = engine().lock().map_err(|_| "Downloader state unavailable")?;
    if worker.is_some() { return Err("Stop the downloader before initializing its test data.".into()); }
    if let Some(path) = ISOLATED_DATA.get() { return Ok(serde_json::json!({"isolated":true,"directory":path})); }
    let stamp=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e|e.to_string())?.as_nanos();
    let root=std::env::temp_dir();
    for suffix in 0..128 {
        let path=root.join(format!("auralis-winui-dev-{}-{stamp}-{suffix}",std::process::id()));
        match std::fs::create_dir(&path) {
            Ok(()) => {
                mdm_ipc::set_data_dir(path.clone());
                if mdm_ipc::data_dir().as_ref()!=Some(&path) { return Err("Cannot isolate the downloader data directory.".into()); }
                remember_isolated_data(&path)?;
                return Ok(serde_json::json!({"isolated":true,"directory":path}));
            }
            Err(error) if error.kind()==std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("Cannot create the isolated test directory: {error}")),
        }
    }
    Err("Cannot choose an isolated test directory.".into())
}
/// The fixed development-only folder is separate from the installed app and
/// survives restarts so interrupted test downloads can be resumed.
fn development_profile_path(base: &std::path::Path) -> Result<std::path::PathBuf, String> {
    if !base.is_absolute() { return Err("The local application data folder must be absolute.".into()); }
    Ok(base.join("Auralis WinUI Development").join("Downloader"))
}
fn initialize_development_profile() -> Result<serde_json::Value, String> {
    let worker=engine().lock().map_err(|_|"Downloader state unavailable")?;
    if worker.is_some() { return Err("Stop the downloader before initializing its test data.".into()); }
    if let Some(path)=ISOLATED_DATA.get() { return Ok(serde_json::json!({"isolated":true,"directory":path})); }
    let base=std::env::var_os("LOCALAPPDATA").ok_or("The local application data folder is unavailable.")?;
    let path=development_profile_path(std::path::Path::new(&base))?;
    // Create and check each level before touching its children. Canonical
    // comparison also rejects Windows junctions and other reparse redirects.
    let parent=path.parent().ok_or("Invalid development profile")?;
    let canonical_base=std::path::Path::new(&base).canonicalize().map_err(|e|e.to_string())?;
    for (directory,expected) in [(parent,canonical_base.join("Auralis WinUI Development")),(path.as_path(),canonical_base.join("Auralis WinUI Development").join("Downloader"))] {
        match std::fs::create_dir(directory) {
            Ok(()) => (),
            Err(e) if e.kind()==std::io::ErrorKind::AlreadyExists => (),
            Err(e) => return Err(format!("Cannot create the isolated development profile: {e}")),
        }
        let meta=std::fs::symlink_metadata(directory).map_err(|e|e.to_string())?;
        let actual=directory.canonicalize().map_err(|e|e.to_string())?;
        let same=same_path(&actual,&expected);
        if meta.file_type().is_symlink() || !meta.is_dir() || !same { return Err("The development profile cannot be a redirected folder.".into()); }
    }
    mdm_ipc::set_data_dir(path.clone());
    if mdm_ipc::data_dir().as_ref()!=Some(&path) { return Err("Cannot isolate the downloader data directory.".into()); }
    remember_isolated_data(&path)?;
    Ok(serde_json::json!({"isolated":true,"directory":path}))
}
fn engine() -> &'static Mutex<Option<JoinHandle<Result<(), String>>>> { ENGINE.get_or_init(|| Mutex::new(None)) }
fn request(query: &str) -> Result<serde_json::Value, String> {
    let command = mdm_ipc::Command { query: Some(query.into()), ..Default::default() };
    let raw = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|_| "Invalid downloader response".to_owned())
}
fn owned_backend() -> bool {
    mdm_ipc::app_pid() == Some(std::process::id())
        && request("glass-backend").is_ok_and(|v| v["headless"] == true && v["glass"] == true)
}

fn start() -> Result<serde_json::Value, String> {
    if ISOLATED_DATA.get().is_none() { return Err("Initialize isolated test data before starting the development downloader.".into()); }
    let mut worker = engine().lock().map_err(|_| "Downloader state unavailable")?;
    if worker.as_ref().is_some_and(|w| !w.is_finished()) {
        return if owned_backend() { Ok(serde_json::json!({"running":true})) } else { Err("Downloader is still starting".into()) };
    }
    if let Some(done) = worker.take() { let _ = done.join(); }
    if request("glass-backend").is_ok() { return Err("Another downloader is using this data; close it before starting the WinUI shell.".into()); }
    *worker = Some(thread::Builder::new().name("auralis-downloader".into()).spawn(mdm_app::run_embedded_downloader).map_err(|e| e.to_string())?);
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        if worker.as_ref().is_some_and(|w| w.is_finished()) {
            let done = worker.take().expect("checked above");
            return Err(match done.join() { Ok(Err(error)) => error, _ => "Downloader stopped during startup".into() });
        }
        if owned_backend() { return Ok(serde_json::json!({"running":true})); }
        if Instant::now() >= deadline { return Err("Downloader is still starting; check its log".into()); }
        thread::sleep(Duration::from_millis(250));
    }
}
fn stop() -> Result<serde_json::Value, String> {
    let mut worker = engine().lock().map_err(|_| "Downloader state unavailable")?;
    if worker.as_ref().is_some_and(|w| !w.is_finished()) {
        if !owned_backend() { return Err("Cannot confirm ownership of the downloader; it was left running.".into()); }
        mdm_ipc::send(&mdm_ipc::Command { exit:true, ..Default::default() }).map_err(|e| e.to_string())?;
        let deadline = Instant::now() + Duration::from_secs(30);
        while worker.as_ref().is_some_and(|w| !w.is_finished()) {
            if Instant::now() >= deadline { return Err("Downloader is still saving; try again shortly.".into()); }
            thread::sleep(Duration::from_millis(100));
        }
    }
    if let Some(done) = worker.take() { done.join().map_err(|_| "Downloader stopped unexpectedly")??; }
    Ok(serde_json::json!({"running":false}))
}
fn dispatch(operation: u32) -> Result<serde_json::Value, String> {
    match operation {
        1 => start(),
        2 => stop(),
        3..=5 if owned_backend() => request(match operation { 3 => "list", 4 => "glass-visuals", _ => "glass-settings" }),
        3..=5 => Err("The embedded downloader is not running in this process.".into()),
        6 => initialize_sandbox(),
        7 => initialize_development_profile(),
        _ => Err("Unsupported bridge operation".into()),
    }
}
fn download_action(action: u32, id: u64) -> Result<serde_json::Value, String> {
    let action = match action { 1 => "start", 2 => "pause", 3 => "remove", _ => return Err("Unsupported download action".into()) };
    if id == 0 { return Err("Invalid download ID".into()); }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let command = mdm_ipc::Command { action: Some(action.into()), ids: vec![id], ..Default::default() };
    let raw = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
    let result: mdm_ipc::api::ActAnswer = serde_json::from_str(&raw).map_err(|_| "Invalid downloader action response")?;
    serde_json::to_value(result).map_err(|e| e.to_string())
}
fn queue_action(name: &str, action: u8) -> Result<serde_json::Value, String> {
    if name.is_empty() || name.len()>256 { return Err("Invalid queue name.".into()); }
    let action=match action { 1=>"start_queue", 2=>"stop_queue", _=>return Err("Unsupported queue action.".into()) };
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let command=mdm_ipc::Command { action:Some(action.into()), queue:Some(name.into()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let result:mdm_ipc::api::ActAnswer=serde_json::from_str(&raw).map_err(|_|"Queue action failed.")?;
    serde_json::to_value(result).map_err(|e|e.to_string())
}
/// # Safety
/// `name` must point to `len` readable UTF-8 bytes for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_queue_action(name: *const u8, len: usize, action: u8) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if name.is_null() || len==0 || len>256 { return Err("Invalid queue name.".into()); }
        let bytes=unsafe { std::slice::from_raw_parts(name,len) };
        let name=std::str::from_utf8(bytes).map_err(|_|"Invalid queue name.")?;
        queue_action(name,action)
    }))
}
fn file_details(id: u64) -> Result<serde_json::Value, String> {
    if id == 0 { return Err("Invalid download ID".into()); }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some("details".into()), ids:vec![id], ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid download details response")?;
    if data.get("error").is_some() { return Err("Download details are unavailable.".into()); }
    Ok(data)
}
/// Returns details for one download; no file paths or operations are accepted from the caller.
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_file_details(id: u64) -> *mut c_char {
    encode(std::panic::catch_unwind(|| file_details(id)))
}
fn safe_test_path(id: u64, folder: bool) -> Result<serde_json::Value, String> {
    if id==0 || !owned_backend() { return Err("The test download is unavailable.".into()); }
    let requested_root=test_output_dir()?;
    let root=requested_root.canonicalize().map_err(|_|"The test folder is unavailable.")?;
    let command=mdm_ipc::Command { query:Some("list".into()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let list:mdm_ipc::api::ListAnswer=serde_json::from_str(&raw).map_err(|_|"Invalid download list.")?;
    let item=list.downloads.iter().find(|item|item.id==id).ok_or("The test download no longer exists.")?;
    let path=std::path::PathBuf::from(&item.path);
    if !path.starts_with(&requested_root) { return Err("The download is outside the test folder.".into()); }
    let target=if folder { requested_root } else {
        if item.status!="Complete" { return Err("The test download is not complete.".into()); }
        let resolved=path.canonicalize().map_err(|_|"The downloaded file is unavailable.")?;
        if !resolved.starts_with(&root) || !resolved.is_file() { return Err("The downloaded file is outside the test folder.".into()); }
        path
    };
    Ok(serde_json::json!({"path":target}))
}
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_safe_test_path(id: u64, folder: u8) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if folder>1 { return Err("Invalid test file request.".into()); }
        safe_test_path(id,folder==1)
    }))
}
fn set_speed_limit(id: u64, kb: u64) -> Result<serde_json::Value, String> {
    if id == 0 || kb > 10_000_000 { return Err("Invalid download speed limit.".into()); }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let value=if kb==0 { "off".to_owned() } else { kb.to_string() };
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some("speed-limit".into()), ids:vec![id], queue:Some(value), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid speed limit response")?;
    if data.get("error").is_some() || data["ok"]!=true { return Err("The speed limit could not be applied.".into()); }
    Ok(data)
}
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_speed_limit(id: u64, kb: u64) -> *mut c_char {
    encode(std::panic::catch_unwind(|| set_speed_limit(id,kb)))
}
fn update_setting(key: &str, value: &str) -> Result<serde_json::Value, String> {
    const ALLOWED: &[&str] = &[
        "max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb",
        "start_immediately", "only_add_to_queue", "confirm_delete", "torrent_keep_sharing", "torrent_dht",
        "torrent_lsd", "proxy_from_browser", "capture_opened", "net_adapter", "show_complete",
        "show_progress", "advanced_integration", "double_click_open",
    ];
    if !ALLOWED.contains(&key) || value.len() > 256 { return Err("Unsupported settings change.".into()); }
    // Keep development settings changes limited to the isolated downloader.
    // In particular, never enable integration, networking or startup behavior.
    if ISOLATED_DATA.get().is_some() && !["show_complete", "show_progress", "confirm_delete", "double_click_open", "max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "start_immediately", "only_add_to_queue"].contains(&key) {
        return Err("This setting is disabled in the development sandbox.".into());
    }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let command = mdm_ipc::Command { action: Some("glass-setting".into()), category: Some(key.into()), queue: Some(value.into()), ..Default::default() };
    let raw = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
    let result: serde_json::Value = serde_json::from_str(&raw).map_err(|_| "Invalid settings response")?;
    if result["saved"] != true { return Err("The downloader rejected the settings change.".into()); }
    Ok(result)
}
/// # Safety
/// `input` must point to `len` readable UTF-8 bytes for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_update_setting(input: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if input.is_null() || len == 0 || len > 2048 { return Err("Invalid settings request.".into()); }
        let bytes = unsafe { std::slice::from_raw_parts(input, len) };
        let data: serde_json::Value = serde_json::from_slice(bytes).map_err(|_| "Invalid settings request.")?;
        let key = data["key"].as_str().ok_or("Invalid setting name.")?;
        let value = data["value"].as_str().ok_or("Invalid setting value.")?;
        update_setting(key, value)
    }))
}
fn add_download(url: &str, later: bool) -> Result<serde_json::Value, String> {
    let url = url.trim();
    if url.is_empty() || url.len() > 8192 { return Err("Enter a supported HTTP, HTTPS, FTP or magnet link.".into()); }
    let parsed = url::Url::parse(url).map_err(|_| "Enter a valid download link.")?;
    let supported = match parsed.scheme() {
        "http" | "https" | "ftp" => parsed.host_str().is_some(),
        "magnet" => parsed.query().is_some_and(|q| !q.is_empty()),
        _ => false,
    };
    if !supported { return Err("Enter a supported HTTP, HTTPS, FTP or magnet link.".into()); }
    if !matches!(parsed.scheme(), "http" | "https") { return Err("The development sandbox accepts only HTTP and HTTPS links.".into()); }
    let output = test_output_dir()?;
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    mdm_ipc::send(&mdm_ipc::Command { url: Some(url.to_owned()), dir: Some(output.to_string_lossy().into_owned()), later, silent: true, ..Default::default() }).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({"pending":true}))
}
/// # Safety
/// `url` must point to `len` readable bytes for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_add_download(url: *const u8, len: usize, later: u8) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if url.is_null() || len == 0 || len > 8192 || later > 1 { return Err("Invalid download request.".into()); }
        let bytes = unsafe { std::slice::from_raw_parts(url, len) };
        let url = std::str::from_utf8(bytes).map_err(|_| "The download link is not UTF-8.")?;
        add_download(url, later == 1)
    }))
}
fn encode(result: Result<Result<serde_json::Value, String>, Box<dyn std::any::Any + Send>>) -> *mut c_char {
    let value = match result { Ok(Ok(value)) => serde_json::json!({"ok":true,"value":value}), Ok(Err(error)) => serde_json::json!({"ok":false,"error":error}), Err(_) => serde_json::json!({"ok":false,"error":"Native bridge failed"}) };
    CString::new(value.to_string()).expect("JSON escapes zero bytes").into_raw()
}
/// Starts, pauses or removes a single isolated download from the list.
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_download_action(action: u32, id: u64) -> *mut c_char {
    encode(std::panic::catch_unwind(|| download_action(action, id)))
}
/// Returns an owned UTF-8 JSON string; release it exactly once with `auralis_bridge_free`.
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_call(operation: u32) -> *mut c_char {
    encode(std::panic::catch_unwind(|| dispatch(operation)))
}
/// # Safety
/// `value` must be null or a pointer returned by `auralis_bridge_call` that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_free(value: *mut c_char) {
    if !value.is_null() { unsafe { drop(CString::from_raw(value)); } }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    #[test]
    fn development_output_rejects_redirected_downloads_folder() {
        use std::os::unix::fs::symlink;
        let unique=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let base=std::env::temp_dir().join(format!("auralis-winui-link-test-{}-{unique}",std::process::id()));
        let data=base.join("profile"); let outside=base.join("outside");
        std::fs::create_dir_all(&data).unwrap(); std::fs::create_dir_all(&outside).unwrap();
        let canonical=data.canonicalize().unwrap();
        symlink(&outside,data.join("downloads")).unwrap();
        assert!(prepare_test_output(&data,&canonical).is_err());
        assert!(std::fs::read_dir(&outside).unwrap().next().is_none());
        std::fs::remove_dir_all(base).unwrap();
    }
    #[test]
    fn development_profile_is_fixed_and_separate() {
        let base=std::env::temp_dir();
        let profile=development_profile_path(&base).expect("absolute local data folder");
        assert_eq!(profile,base.join("Auralis WinUI Development").join("Downloader"));
        assert!(development_profile_path(std::path::Path::new("relative")).is_err());
    }
    #[test]
    fn isolated_embedded_downloader_starts_reads_and_stops() {
        assert!(start().unwrap_err().contains("isolated test data"));
        let initialized=initialize_sandbox().expect("create isolated data directory");
        assert_eq!(initialized["isolated"],true);
        let data=std::path::PathBuf::from(initialized["directory"].as_str().expect("test directory"));
        assert!(data.starts_with(std::env::temp_dir()));
        assert_eq!(initialize_sandbox().unwrap()["directory"],initialized["directory"]);
        let started = start().expect("start isolated embedded downloader");
        assert_eq!(started["running"], true);
        let list = dispatch(3).expect("read download list");
        assert!(list["downloads"].is_array());
        let main_queue=list["queues"][0]["name"].as_str().expect("main queue");
        assert!(queue_action(main_queue,2).expect("stop isolated queue").is_object());
        assert!(queue_action(main_queue,3).is_err());
        let visual = dispatch(4).expect("read download visuals");
        assert!(visual["downloads"].is_array());
        let settings = dispatch(5).expect("read downloader settings");
        assert!(settings["max_connections"].is_number());
        assert!(update_setting("advanced_integration", "true").unwrap_err().contains("disabled"));
        update_setting("max_connections", "8").expect("update isolated connection limit");
        assert_eq!(dispatch(5).unwrap()["max_connections"],8);
        update_setting("show_complete", "false").expect("update isolated setting");
        assert_eq!(dispatch(5).unwrap()["show_complete"], false);
        assert!(add_download("magnet:?xt=urn:btih:1234", true).unwrap_err().contains("HTTP"));
        use std::io::{Read, Write};
        use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
        let listener=std::net::TcpListener::bind("127.0.0.1:0").expect("local test server");
        listener.set_nonblocking(true).expect("nonblocking test server");
        let address=listener.local_addr().unwrap();
        let stopped_server=Arc::new(AtomicBool::new(false));
        let stop_signal=stopped_server.clone();
        let server=thread::spawn(move || {
            let deadline=Instant::now()+Duration::from_secs(60);
            while !stop_signal.load(Ordering::Relaxed) && Instant::now()<deadline {
                match listener.accept() {
                    Ok((mut stream,_)) => {
                        let _=stream.set_read_timeout(Some(Duration::from_secs(2)));
                        let mut bytes=[0u8;4096];
                        if let Ok(n)=stream.read(&mut bytes) {
                            let head=bytes[..n].starts_with(b"HEAD ");
                            let body=b"isolated WinUI test download";
                            let header=format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",body.len());
                            let _=stream.write_all(header.as_bytes());
                            if !head { let _=stream.write_all(body); }
                        }
                    }
                    Err(e) if e.kind()==std::io::ErrorKind::WouldBlock => thread::sleep(Duration::from_millis(20)),
                    Err(_) => break,
                }
            }
        });
        add_download(&format!("http://{address}/winui-test.bin"), true).expect("queue isolated test download");
        let deadline=Instant::now()+Duration::from_secs(10);
        let queued=loop {
            let list=dispatch(3).expect("read queued download");
            if let Some(item)=list["downloads"].as_array().and_then(|items| items.first()) { break item.clone(); }
            assert!(Instant::now()<deadline, "queued download was not added");
            thread::sleep(Duration::from_millis(100));
        };
        let destination=std::path::PathBuf::from(queued["path"].as_str().expect("download path"));
        assert!(destination.starts_with(data.join("downloads")), "test download escaped sandbox");
        assert!(safe_test_path(0,false).is_err());
        let id=queued["id"].as_u64().expect("download id");
        assert!(file_details(id).expect("read isolated download details").is_object());
        set_speed_limit(id,512).expect("set isolated speed limit");
        assert_eq!(file_details(id).unwrap()["own_limit_kb"],512);
        set_speed_limit(id,0).expect("clear isolated speed limit");
        assert!(file_details(id).unwrap()["own_limit_kb"].is_null());
        assert!(set_speed_limit(id,10_000_001).is_err());
        assert!(file_details(0).is_err());
        assert!(download_action(2, u64::MAX).unwrap()["skipped"].is_array());
        assert!(download_action(1, id).expect("start queued test download")["done"].as_array().is_some_and(|done|done.contains(&serde_json::json!(id))));
        let finish_deadline=Instant::now()+Duration::from_secs(30);
        loop {
            let list=dispatch(3).expect("read test progress");
            let item=list["downloads"].as_array().unwrap().iter().find(|item|item["id"]==id).expect("test download present");
            if item["status"]=="Complete" { break; }
            assert!(item["status"]!="Error", "test download failed: {item}");
            assert!(Instant::now()<finish_deadline, "test download did not complete: {item}");
            thread::sleep(Duration::from_millis(100));
        }
        assert_eq!(std::fs::read(&destination).expect("read test download"),b"isolated WinUI test download");
        assert!(std::path::PathBuf::from(safe_test_path(id,false).unwrap()["path"].as_str().unwrap()).starts_with(data.join("downloads")));
        assert_eq!(std::path::PathBuf::from(safe_test_path(id,true).unwrap()["path"].as_str().unwrap()),data.join("downloads"));
        let removed=download_action(3,id).expect("remove test download from list");
        assert!(removed["done"].as_array().is_some_and(|done|done.contains(&serde_json::json!(id))));
        assert!(destination.is_file(),"removing a list entry must preserve the downloaded file");
        assert!(download_action(4,id).is_err(),"the sandbox must not expose file deletion");
        stopped_server.store(true,Ordering::Relaxed);
        server.join().expect("stop test server");
        let stopped = stop().expect("stop isolated embedded downloader");
        assert_eq!(stopped["running"], false);
        assert!(dispatch(3).is_err());
        assert_eq!(start().expect("restart isolated embedded downloader")["running"],true);
        let restored=dispatch(5).expect("read restored settings");
        assert_eq!(restored["max_connections"],8);
        assert_eq!(restored["show_complete"],false);
        assert!(destination.is_file(),"a restart must preserve previously downloaded files");
        assert_eq!(stop().expect("stop restarted downloader")["running"],false);
        std::fs::remove_dir_all(data).expect("remove isolated test data");
    }

    #[test]
    fn unsupported_operations_are_rejected_and_ffi_returns_json() {
        assert!(update_setting("automation_api", "true").is_err());
        assert!(add_download("file:///local/private", false).is_err());
        assert!(add_download("http://", false).is_err());
        assert!(add_download("magnet:", false).is_err());
        assert!(add_download(&"x".repeat(8193), false).is_err());
        assert_eq!(download_action(999, 1).unwrap_err(), "Unsupported download action");
        assert_eq!(download_action(1, 0).unwrap_err(), "Invalid download ID");
        let pointer = auralis_bridge_call(999);
        assert!(!pointer.is_null());
        let response = unsafe { std::ffi::CStr::from_ptr(pointer) }.to_str().unwrap();
        let value: serde_json::Value = serde_json::from_str(response).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"], "Unsupported bridge operation");
        unsafe { auralis_bridge_free(pointer) };
    }
}
