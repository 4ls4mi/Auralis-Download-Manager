//! Narrow native boundary for the future WinUI shell. It is not connected to
//! the development preview yet. Do not expose arbitrary IPC commands to a webview.
use std::{ffi::{c_char, CString}, sync::{Mutex, OnceLock}, thread::{self, JoinHandle}, time::{Duration, Instant}};

static ENGINE: OnceLock<Mutex<Option<JoinHandle<Result<(), String>>>>> = OnceLock::new();
fn engine() -> &'static Mutex<Option<JoinHandle<Result<(), String>>>> { ENGINE.get_or_init(|| Mutex::new(None)) }
fn request(query: &str) -> Result<serde_json::Value, String> {
    let command = mdm_ipc::Command { query: Some(query.into()), ..Default::default() };
    let raw = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|_| "Invalid downloader response".to_owned())
}
fn owned_backend() -> bool {
    let Some(path) = mdm_ipc::data_dir().map(|p| p.join("ipc.json")) else { return false };
    let Some(pid) = std::fs::read(path).ok().and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok()).and_then(|v| v.get("pid").and_then(|v| v.as_u64())) else { return false };
    pid == u64::from(std::process::id()) && request("glass-backend").is_ok_and(|v| v["headless"] == true && v["glass"] == true)
}
fn start() -> Result<serde_json::Value, String> {
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
        3 | 4 if owned_backend() => request(if operation == 3 { "list" } else { "glass-visuals" }),
        3 | 4 => Err("The embedded downloader is not running in this process.".into()),
        _ => Err("Unsupported bridge operation".into()),
    }
}
/// Returns an owned UTF-8 JSON string; release it exactly once with `auralis_bridge_free`.
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_call(operation: u32) -> *mut c_char {
    let result = std::panic::catch_unwind(|| dispatch(operation));
    let value = match result { Ok(Ok(value)) => serde_json::json!({"ok":true,"value":value}), Ok(Err(error)) => serde_json::json!({"ok":false,"error":error}), Err(_) => serde_json::json!({"ok":false,"error":"Native bridge failed"}) };
    CString::new(value.to_string()).expect("JSON escapes zero bytes").into_raw()
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
        let data = std::env::temp_dir().join(format!("auralis-winui-bridge-test-{}", std::process::id()));
        std::fs::create_dir(&data).expect("create isolated data directory");
        mdm_ipc::set_data_dir(data.clone());
        let started = start().expect("start isolated embedded downloader");
        assert_eq!(started["running"], true);
        let list = dispatch(3).expect("read download list");
        assert!(list["downloads"].is_array());
        let visual = dispatch(4).expect("read download visuals");
        assert!(visual["downloads"].is_array());
        let stopped = stop().expect("stop isolated embedded downloader");
        assert_eq!(stopped["running"], false);
        assert!(dispatch(3).is_err());
        std::fs::remove_dir_all(data).expect("remove isolated test data");
    }

    #[test]
    fn unsupported_operations_are_rejected_and_ffi_returns_json() {
        let pointer = auralis_bridge_call(999);
        assert!(!pointer.is_null());
        let response = unsafe { std::ffi::CStr::from_ptr(pointer) }.to_str().unwrap();
        let value: serde_json::Value = serde_json::from_str(response).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"], "Unsupported bridge operation");
        unsafe { auralis_bridge_free(pointer) };
    }
}
