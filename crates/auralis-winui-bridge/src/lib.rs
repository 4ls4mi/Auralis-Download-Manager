#![allow(unsafe_code)] // C ABI boundary; pointer ownership is documented below.
//! Narrow native boundary for the future WinUI shell. It is not connected to
//! the development preview yet. Do not expose arbitrary IPC commands to a webview.
use std::{ffi::{c_char, CString}, sync::{Mutex, OnceLock}, thread::{self, JoinHandle}, time::{Duration, Instant}};

static ENGINE: OnceLock<Mutex<Option<JoinHandle<Result<(), String>>>>> = OnceLock::new();
// The development host must explicitly choose its private test data
// directory before starting. It cannot attach to an installed app's data.
static ISOLATED_DATA: OnceLock<std::path::PathBuf> = OnceLock::new();
static ISOLATED_DATA_CANONICAL: OnceLock<std::path::PathBuf> = OnceLock::new();
#[cfg(feature = "installed-profile")]
static INSTALLED_DATA: OnceLock<std::path::PathBuf> = OnceLock::new();
fn installed_profile_selected() -> bool {
    #[cfg(feature = "installed-profile")]
    { INSTALLED_DATA.get().is_some() }
    #[cfg(not(feature = "installed-profile"))]
    { false }
}
fn same_path(left: &std::path::Path, right: &std::path::Path) -> bool {
    if cfg!(windows) { left.to_string_lossy().eq_ignore_ascii_case(&right.to_string_lossy()) } else { left==right }
}
fn remember_isolated_data(path: &std::path::Path) -> Result<(), String> {
    let canonical=path.canonicalize().map_err(|e|e.to_string())?;
    ISOLATED_DATA_CANONICAL.set(canonical).map_err(|_|"Downloader data was already initialized.")?;
    ISOLATED_DATA.set(path.to_path_buf()).map_err(|_|"Downloader data was already initialized.".to_owned())
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
    if installed_profile_selected() { return Err("The installed profile is already selected.".into()); }
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
    if installed_profile_selected() { return Err("The installed profile is already selected.".into()); }
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
/// Select the exact data directory resolved by the installed Auralis backend.
/// This is a host-only operation, never a WebView command. The existing
/// downloader still acquires its own instance lock before it opens any data.
#[cfg(feature = "installed-profile")]
fn initialize_installed_profile() -> Result<serde_json::Value, String> {
    let worker=engine().lock().map_err(|_|"Downloader state unavailable")?;
    if worker.is_some() { return Err("Stop the downloader before selecting its data.".into()); }
    if ISOLATED_DATA.get().is_some() { return Err("A development profile is already selected.".into()); }
    if INSTALLED_DATA.get().is_some() { return Ok(serde_json::json!({"installed":true})); }
    let path=mdm_ipc::data_dir().ok_or("The Auralis data directory is unavailable.")?;
    if !path.is_absolute() { return Err("The Auralis data directory is invalid.".into()); }
    INSTALLED_DATA.set(path).map_err(|_|"The Auralis profile was already selected.")?;
    Ok(serde_json::json!({"installed":true}))
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
    if ISOLATED_DATA.get().is_none() && !installed_profile_selected() { return Err("Initialize a downloader profile before starting the downloader.".into()); }
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
        8 if owned_backend() => {
            let mut settings = request("glass-original-settings")?;
            let fields = settings["fields"].as_array_mut().ok_or("Invalid preferences response")?;
            fields.retain(|field| field["key"].as_str().is_some_and(safe_preference_key));
            // Never return a stored secret to the interface, even if the
            // underlying settings response changes in a future version.
            for field in fields.iter_mut().filter(|field|field["key"]=="proxy_pass") { field["value"]=serde_json::json!(""); }
            Ok(settings)
        },
        9 if owned_backend() => request("glass-network-adapters"),
        10 if owned_backend() => request("glass-queues"),
        #[cfg(feature = "installed-profile")]
        11 => initialize_installed_profile(),
        #[cfg(feature = "installed-profile")]
        12 if installed_profile_selected() && owned_backend() => request("glass-file-info"),
        _ => Err("Unsupported bridge operation".into()),
    }
}
fn preview_schedule_is_safe(schedule: &serde_json::Value) -> bool {
    schedule.is_object() && schedule["open_when_done"].is_null() && schedule["turn_off"].is_null() &&
        ["hang_up","exit_when_done","force_close","wake"].iter().all(|key|schedule[*key].as_bool()==Some(false))
}
fn save_schedule(payload: &serde_json::Value) -> Result<serde_json::Value, String> {
    if ISOLATED_DATA.get().is_none() || !owned_backend() { return Err("The isolated downloader is not running.".into()); }
    let name=payload["name"].as_str().filter(|s|!s.is_empty() && s.len()<=256).ok_or("Invalid queue name.")?;
    if !payload["files_at_once"].as_u64().is_some_and(|n|(1..=128).contains(&n)) { return Err("Choose 1–128 simultaneous downloads.".into()); }
    let schedule=&payload["schedule"];
    if !preview_schedule_is_safe(schedule) {
        return Err("Computer and completion actions are unavailable in the development preview.".into());
    }
    let queues=request("glass-queues")?;
    if !queues["queues"].as_array().is_some_and(|items|items.iter().any(|item|item["name"].as_str()==Some(name))) { return Err("The selected queue is unavailable.".into()); }
    let command=mdm_ipc::Command { action:Some("glass-schedule".into()), queue:Some(payload.to_string()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid schedule response.")?;
    if data["ok"]!=true { return Err("The schedule could not be saved.".into()); }
    Ok(data)
}
/// # Safety
/// `input` must point to `len` readable JSON bytes during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_save_schedule(input: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if input.is_null() || len==0 || len>8192 { return Err("Invalid schedule request.".into()); }
        let data:serde_json::Value=serde_json::from_slice(unsafe { std::slice::from_raw_parts(input,len) }).map_err(|_|"Invalid schedule request.")?;
        save_schedule(&data)
    }))
}
fn safe_preference_key(key: &str) -> bool {
    matches!(key, "limiter_on_startup" | "global_only_active" | "set_creation_date" | "mark_downloads" | "ignore_mtime" | "many_connections" | "duplicate_action" |
        "proxy_mode" | "proxy_script" | "proxy_host" | "proxy_port" | "proxy_user" | "proxy_pass" | "proxy_http" | "proxy_https" | "proxy_ftp" |
        "user_agent" | "dns_mode" | "dns_provider" | "dns_servers" | "dns_tls_name" | "dns_doh_url" | "dns_nextdns_id" | "dns_fallback" | "ftp_passive")
}
fn update_preference(key: &str, value: &serde_json::Value, clear: bool) -> Result<serde_json::Value, String> {
    let valid=match key {
        "duplicate_action" | "proxy_mode" | "dns_mode" => value.as_u64().is_some_and(|n| n <= 3),
        "proxy_script" | "proxy_host" | "proxy_port" | "proxy_user" | "proxy_pass" | "user_agent" | "dns_provider" | "dns_servers" | "dns_tls_name" | "dns_doh_url" | "dns_nextdns_id" => value.as_str().is_some_and(|s|s.len()<=512 && !s.contains('\0')),
        _ => value.is_boolean(),
    };
    if !safe_preference_key(key) || !valid || (clear && key!="proxy_pass") {
        return Err("Unsupported preference change.".into());
    }
    if ISOLATED_DATA.get().is_none() || !owned_backend() { return Err("The isolated downloader is not running.".into()); }
    let cleared=serde_json::json!("");
    let effective_value=if clear { &cleared } else { value };
    let payload=serde_json::json!({"key":key,"value":effective_value,"clear":clear}).to_string();
    let command=mdm_ipc::Command { action:Some("glass-original-setting".into()), queue:Some(payload), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let result:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid preferences response")?;
    if result["ok"] != true {
        // Forward only known validation messages. Never echo arbitrary backend
        // errors, which could contain a path or a value entered by the user.
        return Err(match result["error"].as_str() {
            Some("Proxy port must be 1–65535") => "Proxy port must be 1–65535",
            Some("Choose a valid option") => "Choose a valid option",
            _ => "The downloader rejected the preference.",
        }.into());
    }
    Ok(result)
}
/// # Safety
/// `input` must point to `len` readable bytes for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_update_preference(input: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if input.is_null() || len == 0 || len > 1024 { return Err("Invalid preference request.".into()); }
        let data:serde_json::Value=serde_json::from_slice(unsafe { std::slice::from_raw_parts(input,len) }).map_err(|_|"Invalid preference request.")?;
        let clear=match data.get("clear") { None => false, Some(v)=>v.as_bool().ok_or("Invalid clear flag.")? };
        update_preference(data["key"].as_str().ok_or("Invalid preference name.")?, &data["value"],clear)
    }))
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
fn item_queue_action(id: u64, name: Option<&str>) -> Result<serde_json::Value, String> {
    if id==0 || !owned_backend() || ISOLATED_DATA.get().is_none() { return Err("The test download is unavailable.".into()); }
    if name.is_some_and(|name|name.is_empty() || name.len()>256) { return Err("Invalid queue name.".into()); }
    let root=test_output_dir()?;
    let command=mdm_ipc::Command { query:Some("list".into()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let list:mdm_ipc::api::ListAnswer=serde_json::from_str(&raw).map_err(|_|"Invalid download list.")?;
    let item=list.downloads.iter().find(|item|item.id==id).ok_or("The test download no longer exists.")?;
    if std::path::Path::new(&item.path).parent().is_none_or(|parent|!same_path(parent,&root)) { return Err("The download is outside the test folder.".into()); }
    if name.is_some_and(|name|!list.queues.iter().any(|queue|queue.name==name)) { return Err("The selected queue is unavailable.".into()); }
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some(if name.is_some(){"queue-add"}else{"queue-remove"}.into()), ids:vec![id], queue:name.map(str::to_owned), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid queue response.")?;
    if data.get("error").is_some() { return Err("The download queue could not be changed.".into()); }
    Ok(data)
}
/// # Safety
/// When `len` is nonzero, `name` must point to `len` readable UTF-8 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_item_queue_action(id: u64, name: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if len>256 || (len>0 && name.is_null()) { return Err("Invalid queue request.".into()); }
        let name=if len==0 { None } else { Some(std::str::from_utf8(unsafe { std::slice::from_raw_parts(name,len) }).map_err(|_|"Invalid queue name.")?) };
        item_queue_action(id,name)
    }))
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
// Check only a stopped ordinary test download owned by the isolated profile.
// The backend performs the read-only hash verification and returns its report.
fn check_saved(id: u64, result: bool) -> Result<serde_json::Value, String> {
    if id==0 || !owned_backend() { return Err("The test download is unavailable.".into()); }
    let root=test_output_dir()?;
    let canonical_root=root.canonicalize().map_err(|_|"The test folder is unavailable.")?;
    let command=mdm_ipc::Command { query:Some("list".into()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let list:mdm_ipc::api::ListAnswer=serde_json::from_str(&raw).map_err(|_|"Invalid download list.")?;
    let item=list.downloads.iter().find(|item|item.id==id).ok_or("The test download no longer exists.")?;
    let destination=std::path::PathBuf::from(&item.path);
    if destination.parent().is_none_or(|parent|!same_path(parent,&root)) { return Err("The download is outside the test folder.".into()); }
    if !result {
        for suffix in [".mdm.json",".mdm.part"] {
            let mut name=destination.as_os_str().to_owned(); name.push(suffix);
            let file=std::path::PathBuf::from(name);
            let metadata=std::fs::symlink_metadata(&file).map_err(|_|"Saved download data is unavailable.")?;
            let actual=file.canonicalize().map_err(|_|"Saved download data is unavailable.")?;
            if metadata.file_type().is_symlink() || !metadata.is_file() || actual.parent().is_none_or(|p|!same_path(p,&canonical_root)) {
                return Err("Saved download data cannot be redirected.".into());
            }
        }
    }
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some(if result {"check-saved-result"} else {"check-saved"}.into()), ids:vec![id], ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid saved-data response")?;
    if data.get("error").is_some() { return Err("The saved download cannot be checked now.".into()); }
    Ok(data)
}
#[unsafe(no_mangle)]
pub extern "C" fn auralis_bridge_check_saved(id: u64, result: u8) -> *mut c_char {
    encode(std::panic::catch_unwind(|| if result>1 { Err("Invalid saved-data request.".into()) } else { check_saved(id,result==1) }))
}
fn checksum(id: u64, expected: Option<&str>) -> Result<serde_json::Value, String> {
    // The development host verifies only its own completed files.
    safe_test_path(id,false)?;
    if expected.is_some_and(|v|v.is_empty() || v.len()>256 || !v.is_ascii() || v.chars().any(|c|c.is_control())) {
        return Err("Invalid checksum.".into());
    }
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some(if expected.is_some() {"checksum"} else {"checksum-result"}.into()), ids:vec![id], queue:expected.map(str::to_owned), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid checksum response")?;
    if data.get("error").is_some() { return Err("The checksum could not be verified.".into()); }
    Ok(data)
}
/// # Safety
/// When `len` is nonzero, `input` must point to `len` readable UTF-8 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_checksum(id: u64, input: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if len>256 || (len>0 && input.is_null()) { return Err("Invalid checksum request.".into()); }
        let expected=if len==0 { None } else { Some(std::str::from_utf8(unsafe { std::slice::from_raw_parts(input,len) }).map_err(|_|"Invalid checksum.")?) };
        checksum(id,expected)
    }))
}
fn refresh_address(id: u64, address: &str) -> Result<serde_json::Value, String> {
    if id==0 || !owned_backend() { return Err("The test download is unavailable.".into()); }
    let url=url::Url::parse(address).map_err(|_|"Enter a valid HTTP or HTTPS address.")?;
    if address.len()>8192 || !matches!(url.scheme(),"http"|"https") || url.host_str().is_none() { return Err("Enter a valid HTTP or HTTPS address.".into()); }
    let root=test_output_dir()?;
    let command=mdm_ipc::Command { query:Some("list".into()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let list:mdm_ipc::api::ListAnswer=serde_json::from_str(&raw).map_err(|_|"Invalid download list.")?;
    let item=list.downloads.iter().find(|item|item.id==id).ok_or("The test download no longer exists.")?;
    let destination=std::path::PathBuf::from(&item.path);
    if destination.parent().is_none_or(|parent|!same_path(parent,&root)) { return Err("The download is outside the test folder.".into()); }
    let command=mdm_ipc::Command { action:Some("glass-item".into()), category:Some("refresh-address".into()), ids:vec![id], queue:Some(url.to_string()), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid address update response")?;
    if let Some(error)=data.get("error") {
        return Err(if error.as_str()==Some("Stop this download before updating its address") {
            "Stop this test download before updating its address."
        } else { "Could not update the test download address." }.into());
    }
    Ok(data)
}
/// # Safety
/// `input` must point to `len` readable UTF-8 bytes for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_refresh_address(id: u64, input: *const u8, len: usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if input.is_null() || len==0 || len>8192 { return Err("Invalid address update request.".into()); }
        let address=std::str::from_utf8(unsafe { std::slice::from_raw_parts(input,len) }).map_err(|_|"Invalid address.")?;
        refresh_address(id,address)
    }))
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
    // Integration and startup behavior remain disabled in the sandbox.
    if ISOLATED_DATA.get().is_some() && !["show_complete", "show_progress", "confirm_delete", "double_click_open", "max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "start_immediately", "only_add_to_queue", "net_adapter"].contains(&key) {
        return Err("This setting is disabled in the development sandbox.".into());
    }
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    if key=="net_adapter" && !value.is_empty() {
        let adapters=request("glass-network-adapters")?;
        if !adapters["adapters"].as_array().is_some_and(|list|list.iter().any(|item|item["name"].as_str()==Some(value))) {
            return Err("The selected network adapter is unavailable.".into());
        }
    }
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
    #[cfg(feature = "installed-profile")]
    if installed_profile_selected() {
        if parsed.scheme()=="magnet" { return Err("Torrent integration is not yet enabled in the WinUI host.".into()); }
        if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
        // Use the app's ordinary add flow so its existing file-info dialog,
        // categories, selected destination and resume rules remain authoritative.
        mdm_ipc::send(&mdm_ipc::Command { url:Some(url.to_owned()), later, silent:false, ..Default::default() }).map_err(|e|e.to_string())?;
        return Ok(serde_json::json!({"pending":true}));
    }
    if !matches!(parsed.scheme(), "http" | "https") { return Err("The development sandbox accepts only HTTP and HTTPS links.".into()); }
    let output = test_output_dir()?;
    if !owned_backend() { return Err("The embedded downloader is not running in this process.".into()); }
    mdm_ipc::send(&mdm_ipc::Command { url: Some(url.to_owned()), dir: Some(output.to_string_lossy().into_owned()), later, silent: true, ..Default::default() }).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({"pending":true}))
}
#[cfg(feature = "installed-profile")]
fn file_info_action(id: u64, action: u8, payload: Option<&serde_json::Value>) -> Result<serde_json::Value, String> {
    if id==0 || !installed_profile_selected() || !owned_backend() { return Err("The download request is unavailable.".into()); }
    let name=match action { 1=>"commit", 2=>"cancel", 3=>"category", _=>return Err("Invalid download request action.".into()) };
    match action {
        2 if payload.is_some() => return Err("Invalid download request.".into()),
        1 => {
            let data=payload.filter(|p|p.is_object()).ok_or("Invalid download request.")?;
            let path=data["save_as"].as_str().filter(|s|!s.trim().is_empty() && s.len()<=32760).ok_or("Choose a destination filename.")?;
            let destination=std::path::Path::new(path);
            if !destination.is_absolute() || destination.file_name().is_none() { return Err("Choose an absolute destination filename.".into()); }
        },
        3 => {
            let data=payload.filter(|p|p.is_object()).ok_or("Invalid download request.")?;
            if !data["category"].as_str().is_some_and(|s|!s.is_empty() && s.len()<=128) { return Err("Choose a valid category.".into()); }
        },
        _=>(),
    }
    let command=mdm_ipc::Command { action:Some("glass-file-info".into()), category:Some(name.into()), ids:vec![id], queue:payload.map(serde_json::Value::to_string), ..Default::default() };
    let raw=mdm_ipc::request_checked(&command).map_err(|e|e.to_string())?;
    let data:serde_json::Value=serde_json::from_str(&raw).map_err(|_|"Invalid download request response.")?;
    if data.get("error").is_some() { return Err("The download request could not be completed.".into()); }
    Ok(data)
}
/// # Safety
/// When `len` is nonzero, `input` must point to `len` readable JSON bytes.
#[cfg(feature = "installed-profile")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_bridge_file_info_action(id:u64, action:u8, input:*const u8, len:usize) -> *mut c_char {
    encode(std::panic::catch_unwind(|| {
        if len>65536 || (len>0 && input.is_null()) { return Err("Invalid download request.".into()); }
        let payload=if len==0 { None } else { Some(serde_json::from_slice(unsafe { std::slice::from_raw_parts(input,len) }).map_err(|_|"Invalid download request.")?) };
        file_info_action(id,action,payload.as_ref())
    }))
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
    #[test]
    fn preferences_reject_secrets_and_invalid_values_before_backend_access() {
        assert!(!safe_preference_key("site_logins"));
        assert!(update_preference("site_logins", &serde_json::json!("secret"),false).is_err());
        assert!(update_preference("many_connections", &serde_json::json!("true"),false).is_err());
        assert!(update_preference("duplicate_action", &serde_json::json!(4),false).is_err());
        assert!(update_preference("proxy_mode", &serde_json::json!(4),false).is_err());
        assert!(update_preference("proxy_host", &serde_json::json!("x".repeat(513)),false).is_err());
        assert!(update_preference("proxy_host", &serde_json::json!("host"),true).is_err());
    }
    #[test]
    fn preview_schedule_rejects_computer_actions() {
        let mut schedule=serde_json::json!({"open_when_done":null,"turn_off":null,"hang_up":false,"exit_when_done":false,"force_close":false,"wake":false});
        assert!(preview_schedule_is_safe(&schedule));
        for key in ["hang_up","exit_when_done","force_close","wake"] {
            schedule[key]=serde_json::json!(true); assert!(!preview_schedule_is_safe(&schedule)); schedule[key]=serde_json::json!(false);
        }
        schedule["turn_off"]=serde_json::json!("ShutDown");assert!(!preview_schedule_is_safe(&schedule));
        schedule["turn_off"]=serde_json::Value::Null;schedule["open_when_done"]=serde_json::json!("C:\\untrusted.exe");assert!(!preview_schedule_is_safe(&schedule));
    }
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
        assert!(start().unwrap_err().contains("Initialize a downloader profile"));
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
        let schedules=dispatch(10).expect("read queue schedules");
        let schedule=schedules["queues"].as_array().unwrap().iter().find(|queue|queue["name"]==main_queue).unwrap()["schedule"].clone();
        let schedule_change=serde_json::json!({"name":main_queue,"files_at_once":2,"schedule":schedule});
        assert_eq!(save_schedule(&schedule_change).expect("save isolated queue schedule")["ok"],true);
        assert!(dispatch(10).unwrap()["queues"].as_array().unwrap().iter().any(|queue|queue["name"]==main_queue && queue["files_at_once"]==2));
        assert!(queue_action(main_queue,2).expect("stop isolated queue").is_object());
        assert!(queue_action(main_queue,3).is_err());
        let visual = dispatch(4).expect("read download visuals");
        assert!(visual["downloads"].is_array());
        let settings = dispatch(5).expect("read downloader settings");
        assert!(settings["max_connections"].is_number());
        assert!(dispatch(9).expect("list network adapters")["adapters"].is_array());
        assert!(update_setting("net_adapter","__auralis_missing_adapter__").is_err());
        assert_eq!(update_setting("net_adapter","").expect("select automatic network adapter")["saved"],true);
        let preferences=dispatch(8).expect("read isolated preferences");
        assert!(preferences["fields"].as_array().unwrap().iter().all(|field|field["key"].as_str().is_some_and(safe_preference_key)));
        assert!(update_preference("many_connections",&serde_json::json!(true),false).expect("save isolated preference")["ok"]==true);
        assert!(dispatch(8).unwrap()["fields"].as_array().unwrap().iter().any(|field|field["key"]=="many_connections" && field["value"]==true));
        assert!(update_preference("proxy_host",&serde_json::json!("proxy.example.test"),false).expect("save proxy host")["ok"]==true);
        assert_eq!(update_preference("proxy_port",&serde_json::json!("70000"),false).unwrap_err(),"Proxy port must be 1–65535");
        assert!(dispatch(8).unwrap()["fields"].as_array().unwrap().iter().any(|field|field["key"]=="proxy_host" && field["value"]=="proxy.example.test"));
        assert!(update_preference("proxy_host",&serde_json::json!(""),false).expect("clear proxy host")["ok"]==true);
        assert!(update_preference("proxy_pass",&serde_json::json!("example-secret"),false).expect("save isolated proxy password")["ok"]==true);
        let fields=dispatch(8).unwrap();
        let password=fields["fields"].as_array().unwrap().iter().find(|field|field["key"]=="proxy_pass").unwrap();
        assert_eq!(password["value"],"");
        assert_eq!(password["saved"],true);
        assert!(!fields.to_string().contains("example-secret"));
        assert!(update_preference("proxy_pass",&serde_json::json!(""),false).is_ok());
        assert!(dispatch(8).unwrap()["fields"].as_array().unwrap().iter().any(|field|field["key"]=="proxy_pass" && field["saved"]==true));
        assert!(update_preference("proxy_pass",&serde_json::json!("discard-this"),true).is_ok());
        assert!(dispatch(8).unwrap()["fields"].as_array().unwrap().iter().any(|field|field["key"]=="proxy_pass" && field["saved"]==false));
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
        assert!(item_queue_action(id,Some("__missing_queue__")).is_err());
        assert_eq!(item_queue_action(id,Some(main_queue)).expect("add test download to queue")["ok"],true);
        assert!(dispatch(3).unwrap()["queues"].as_array().unwrap().iter().any(|queue|queue["name"]==main_queue && queue["ids"].as_array().is_some_and(|ids|ids.contains(&serde_json::json!(id)))));
        assert_eq!(item_queue_action(id,None).expect("remove test download from queue")["ok"],true);
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
        assert!(refresh_address(id,"https://example.test/replacement").is_err(),"a completed download must not have its address changed");
        assert!(refresh_address(u64::MAX,"file:///outside").is_err(),"non-HTTP replacement links must be rejected");
        assert_eq!(checksum(id,Some("6ac9dd29d34969b8e09a5f989251be3693e2b00cc5b437409e96f613b79a9695")).unwrap()["pending"],true);
        let checksum_deadline=Instant::now()+Duration::from_secs(10);
        loop {
            let result=checksum(id,None).expect("read checksum result");
            if result["complete"]==true { assert_eq!(result["matches"],true); break; }
            assert!(Instant::now()<checksum_deadline,"checksum did not finish");
            thread::sleep(Duration::from_millis(50));
        }
        assert!(check_saved(id,false).is_err(),"a completed download must not be treated as partial data");
        assert!(check_saved(u64::MAX,false).is_err(),"unknown downloads cannot be checked");
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
        assert!(dispatch(8).unwrap()["fields"].as_array().unwrap().iter().any(|field|field["key"]=="many_connections" && field["value"]==true));
        assert!(destination.is_file(),"a restart must preserve previously downloaded files");
        assert_eq!(stop().expect("stop restarted downloader")["running"],false);
        std::fs::remove_dir_all(data).expect("remove isolated test data");
    }

    #[test]
    fn unsupported_operations_are_rejected_and_ffi_returns_json() {
        #[cfg(not(feature = "installed-profile"))]
        assert_eq!(dispatch(11).unwrap_err(),"Unsupported bridge operation");
        assert!(check_saved(0,false).is_err());
        let invalid=auralis_bridge_check_saved(1,2);
        let response=unsafe { std::ffi::CStr::from_ptr(invalid) }.to_str().unwrap();
        assert_eq!(serde_json::from_str::<serde_json::Value>(response).unwrap()["ok"],false);
        unsafe { auralis_bridge_free(invalid) };
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
