#![allow(unsafe_code)] // C ABI boundary; pointer ownership is documented below.
//! Narrow native boundary for the future WinUI shell. It is not connected to
//! the development preview yet. Do not expose arbitrary IPC commands to a webview.
use std::{ffi::{c_char, CString}, sync::{Mutex, OnceLock}, thread::{self, JoinHandle}, time::{Duration, Instant}};

static ENGINE: OnceLock<Mutex<Option<JoinHandle<Result<(), String>>>>> = OnceLock::new();
// The development host must explicitly choose an empty, private test data
// directory before starting. It cannot attach to an installed app's data.
static ISOLATED_DATA: OnceLock<std::path::PathBuf> = OnceLock::new();
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
                ISOLATED_DATA.set(path.clone()).map_err(|_|"Downloader data was already initialized.")?;
                return Ok(serde_json::json!({"isolated":true,"directory":path}));
            }
            Err(error) if error.kind()==std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("Cannot create the isolated test directory: {error}")),
        }
    }
    Err("Cannot choose an isolated test directory.".into())
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
        _ => Err("Unsupported bridge operation".into()),
    }
}
fn download_action(action: u32, id: u64) -> Result<serde_json::Value, String> {
    let action = match action { 1 => "start", 2 => "pause", _ => return Err("Unsupported download action".into()) };
    if id == 0 { return Err("Invalid download ID".into()); }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    let command = mdm_ipc::Command { action: Some(action.into()), ids: vec![id], ..Default::default() };
    let raw = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
    let result: mdm_ipc::api::ActAnswer = serde_json::from_str(&raw).map_err(|_| "Invalid downloader action response")?;
    serde_json::to_value(result).map_err(|e| e.to_string())
}
fn update_setting(key: &str, value: &str) -> Result<serde_json::Value, String> {
    const ALLOWED: &[&str] = &[
        "max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb",
        "start_immediately", "only_add_to_queue", "confirm_delete", "torrent_keep_sharing", "torrent_dht",
        "torrent_lsd", "proxy_from_browser", "capture_opened", "net_adapter", "show_complete",
        "show_progress", "advanced_integration", "double_click_open",
    ];
    if !ALLOWED.contains(&key) || value.len() > 256 { return Err("Unsupported settings change.".into()); }
    // Keep development settings changes limited to harmless UI preferences.
    // In particular, never enable integration, networking or startup behavior.
    if ISOLATED_DATA.get().is_some() && !["show_complete", "show_progress", "confirm_delete", "double_click_open"].contains(&key) {
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
    let data = ISOLATED_DATA.get().ok_or("Initialize isolated test data first.")?;
    if !matches!(parsed.scheme(), "http" | "https") { return Err("The development sandbox accepts only HTTP and HTTPS links.".into()); }
    let output = data.join("downloads");
    std::fs::create_dir_all(&output).map_err(|e| format!("Cannot create the test downloads folder: {e}"))?;
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
/// Starts or pauses a single download. Arbitrary and destructive commands are not exposed.
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
        let visual = dispatch(4).expect("read download visuals");
        assert!(visual["downloads"].is_array());
        let settings = dispatch(5).expect("read downloader settings");
        assert!(settings["max_connections"].is_number());
        assert!(update_setting("advanced_integration", "true").unwrap_err().contains("disabled"));
        update_setting("show_complete", "false").expect("update isolated setting");
        assert_eq!(dispatch(5).unwrap()["show_complete"], false);
        assert!(add_download("magnet:?xt=urn:btih:1234", true).unwrap_err().contains("HTTP"));
        add_download("https://example.com/winui-test.bin", true).expect("queue isolated test download");
        let deadline=Instant::now()+Duration::from_secs(10);
        let queued=loop {
            let list=dispatch(3).expect("read queued download");
            if let Some(item)=list["downloads"].as_array().and_then(|items| items.first()) { break item.clone(); }
            assert!(Instant::now()<deadline, "queued download was not added");
            thread::sleep(Duration::from_millis(100));
        };
        let destination=std::path::PathBuf::from(queued["path"].as_str().expect("download path"));
        assert!(destination.starts_with(data.join("downloads")), "test download escaped sandbox");
        assert!(download_action(2, u64::MAX).unwrap()["skipped"].is_array());
        let stopped = stop().expect("stop isolated embedded downloader");
        assert_eq!(stopped["running"], false);
        assert!(dispatch(3).is_err());
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
