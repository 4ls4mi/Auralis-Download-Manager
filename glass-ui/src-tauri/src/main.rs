#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// Windows-only Tauri shell. Keeps MDM's production download engine as a
// bundled, hidden legacy process until app-only logic has been extracted.
// Frontend never accesses MDM's token or loopback socket directly.
mod lifecycle;
#[cfg(windows)] mod fork_update;
mod material_window;
mod native_actions;
use lifecycle::{pending_file_info, file_info_action, choose_download_path, window_preferences, glass_tool, choose_folder, open_glass_window, close_progress_windows};
use native_actions::{drag_download, drag_state, choose_move, clipboard_text, video_tool, browser_video};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command as ProcessCommand, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, Submenu},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
use serde::Deserialize;
use std::collections::HashSet;
use std::sync::Mutex;

type ApiResult<T> = Result<T, String>;

#[derive(Default)]
struct HiddenDownloadWindows(Mutex<HashSet<u64>>);

fn send_ipc(command: &mdm_ipc::Command) -> ApiResult<String> {
    mdm_ipc::request_checked(command).map_err(|e| e.to_string())
}

fn request_snapshot() -> ApiResult<mdm_ipc::api::ListAnswer> {
    let response = send_ipc(&mdm_ipc::Command {
        query: Some("list".into()),
        ..Default::default()
    })?;
    serde_json::from_str(&response)
        .map_err(|_| format!("Cannot read download list from existing MDM: {response}"))
}

fn possible_legacy_paths(app: &AppHandle) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(root) = app.path().resource_dir() {
        paths.push(root.join("mdm-legacy.exe"));
        paths.push(root.join("resources").join("mdm-legacy.exe"));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            paths.push(parent.join("mdm-legacy.exe"));
            paths.push(parent.join("resources").join("mdm-legacy.exe"));
        }
    }
    paths
}

#[derive(Deserialize)]
struct BackendIdentity {
    headless: bool,
    glass: bool,
}

fn current_backend() -> ApiResult<BackendIdentity> {
    let response = send_ipc(&mdm_ipc::Command {
        query: Some("glass-backend".into()),
        ..Default::default()
    })?;
    serde_json::from_str(&response)
        .map_err(|_| "Another original Mister Download Manager instance is running. It still owns the original tray icon. Finish active downloads, then exit original MDM before starting Auralis. Your download data and settings will be preserved.".into())
}

fn boot_existing_engine(app: &AppHandle) -> ApiResult<String> {
    // NEVER attach the Glass UI to a legacy GUI instance: that previously
    // resulted in two tray icons and opening the old window by accident.
    // Nor silently exit an existing user's active downloads.
    match current_backend() {
        Ok(identity) if identity.headless && identity.glass => {
            request_snapshot()?;
            return Ok("Connected to headless Rust downloader • Glass owns the Windows tray".into())
        }
        Ok(_) => return Err("An incompatible downloader is running. Exit it safely before switching to Glass.".into()),
        Err(e) if e.contains("Another original Mister") => return Err(e),
        Err(_) => {}
    }
    let backend = possible_legacy_paths(app).into_iter()
        .find(|candidate| candidate.is_file())
        .ok_or_else(|| "The bundled headless Rust downloader is missing. Reinstall Mister Hybrid Glass.".to_string())?;
    // The ORIGINAL project already implements --headless. No egui window
    // opens, no original tray icon is created, and its download logic and
    // saved data are preserved. Disable its separate remote HTTP server.
    ProcessCommand::new(backend)
        .arg("--headless")
        .env("MDM_GLASS_HEADLESS", "1")
        .env("MDM_REMOTE", "off")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Could not launch headless Rust engine: {e}"))?;
    for _ in 0..48 {
        thread::sleep(Duration::from_millis(250));
        match current_backend() {
            Ok(identity) if identity.headless && identity.glass => {
                request_snapshot()?;
                return Ok("Headless Rust downloader started • One Glass tray icon".into());
            }
            Ok(_) => return Err("A different MDM process acquired the download data lock.                 Please close that instance without losing active downloads.".into()),
            Err(e) if e.contains("Another original Mister") => return Err(e),
            Err(_) => {}
        }
    }
    Err("Headless downloader did not initialize. See its crash logs in the original MDM data directory.".into())
}

fn build_tray_menu(app: &AppHandle) -> ApiResult<Menu> {
    let menu = Menu::new(app).map_err(|e| e.to_string())?;
    let show = MenuItem::with_id(app, "show", "Open Auralis Download Manager", true, None::<&str>).map_err(|e| e.to_string())?;
    let add = MenuItem::with_id(app, "add", "Add new download…", true, None::<&str>).map_err(|e| e.to_string())?;
    let batch = MenuItem::with_id(app, "batch", "Add batch download…", true, None::<&str>).map_err(|e| e.to_string())?;
    let batch_clipboard = MenuItem::with_id(app, "batch-clipboard", "Add batch download from clipboard", true, None::<&str>).map_err(|e| e.to_string())?;
    let downloads = Submenu::with_id(app, "downloads", "Downloads in progress", true).map_err(|e| e.to_string())?;
    let hidden = app.state::<HiddenDownloadWindows>().0.lock().map(|v| v.clone()).unwrap_or_default();
    let snapshot = request_snapshot().ok();
    for id in hidden {
        if let Some(window) = app.get_webview_window(&format!("download-{id}")) {
            let _ = window.title();
            let label = snapshot.as_ref().and_then(|s| s.downloads.iter().find(|d| d.id == id))
                .map(|d| d.file.clone()).unwrap_or_else(|| format!("Download #{id}"));
            let item = MenuItem::with_id(app, format!("restore-download-{id}"), label, true, None::<&str>)
                .map_err(|e| e.to_string())?;
            downloads.append(&item).map_err(|e| e.to_string())?;
        }
    }
    if downloads.items().is_empty() {
        let empty = MenuItem::with_id(app, "no-hidden-downloads", "No hidden download windows", false, None::<&str>)
            .map_err(|e| e.to_string())?;
        downloads.append(&empty).map_err(|e| e.to_string())?;
    }
    let speed = MenuItem::with_id(app, "speed-limit", "Speed Limiter…", true, None::<&str>).map_err(|e| e.to_string())?;
    let scheduler = MenuItem::with_id(app, "scheduler", "Scheduler", true, None::<&str>).map_err(|e| e.to_string())?;
    let start = MenuItem::with_id(app, "start-queue", "Start main download queue", true, None::<&str>).map_err(|e| e.to_string())?;
    let stop = MenuItem::with_id(app, "stop-queue", "Stop main download queue", true, None::<&str>).map_err(|e| e.to_string())?;
    let options = MenuItem::with_id(app, "options", "Options", true, None::<&str>).map_err(|e| e.to_string())?;
    let exit = MenuItem::with_id(app, "quit", "Exit Auralis", true, None::<&str>).map_err(|e| e.to_string())?;
    for item in [&show, &add, &batch, &batch_clipboard] {
        menu.append(item).map_err(|e| e.to_string())?;
    }
    menu.append(&PredefinedMenuItem::separator(app).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    menu.append(&downloads).map_err(|e| e.to_string())?;
    menu.append(&PredefinedMenuItem::separator(app).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    for item in [&speed, &scheduler, &start, &stop, &options] {
        menu.append(item).map_err(|e| e.to_string())?;
    }
    menu.append(&PredefinedMenuItem::separator(app).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    menu.append(&exit).map_err(|e| e.to_string())?;
    Ok(menu)
}

fn refresh_tray_menu(app: &AppHandle) {
    if let (Some(tray), Ok(menu)) = (app.tray_by_id("auralis-tray"), build_tray_menu(app)) {
        let _ = tray.set_menu(Some(menu));
    }
}

fn restore_download_window(app: &AppHandle, id: u64) {
    if let Ok(mut hidden) = app.state::<HiddenDownloadWindows>().0.lock() {
        hidden.remove(&id);
    }
    if let Some(window) = app.get_webview_window(&format!("download-{id}")) {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
    refresh_tray_menu(app);
}

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

#[tauri::command]
async fn boot_engine(app: AppHandle) -> ApiResult<String> {
    tauri::async_runtime::spawn_blocking(move || {
        let boot = boot_existing_engine(&app)?;
        let browser = register_browser_host(&app);
        match browser {
            Ok(_) => Ok(format!("{boot} • browser extension host registered")),
            Err(err) => Ok(format!("{boot} • browser helper needs attention: {err}")),
        }
    }).await.map_err(|e| e.to_string())?
}

/// Private, authenticated engine telemetry for the native download views.
#[tauri::command]
async fn open_upstream_releases() -> ApiResult<()> {
    // A user-requested read-only check. Never launch an updater that could
    // overwrite the separate Glass Windows installation.
    tauri::async_runtime::spawn_blocking(|| {
        open::that("https://github.com/anefzaoui/misterdownloadmanager/releases")
            .map_err(|e| format!("Could not open upstream release history: {e}"))
    }).await.map_err(|e| e.to_string())?
}

/// Resolve only official extension pages. Edge uses its protocol so it opens
/// even when another browser is configured as the Windows default.
fn extension_store_target(browser: &str) -> ApiResult<String> {
    let chromium = || mdm_ipc::extension::store_page()
        .ok_or_else(|| "The original Chrome Web Store listing is unavailable".to_string());
    match browser {
        "edge" => Ok(format!("microsoft-edge:{}", chromium()?)),
        "chromium" => chromium(),
        "firefox" => Ok(mdm_ipc::extension::FIREFOX_PAGE.to_owned()),
        _ => Err("Unsupported browser".into()),
    }
}
#[tauri::command]
fn extension_store_link(browser: String) -> ApiResult<String> { extension_store_target(&browser) }
#[tauri::command]
async fn open_extension_store(browser: String) -> ApiResult<()> {
    let url = extension_store_target(&browser)?;
    tauri::async_runtime::spawn_blocking(move || {
        open::that(&url).map_err(|e| format!("Could not open the extension page: {e}"))
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn dashboard_visuals() -> ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(|| {
        let reply = send_ipc(&mdm_ipc::Command {
            query: Some("glass-visuals".into()),
            ..Default::default()
        })?;
        let result: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| format!("Invalid engine telemetry: {reply}"))?;
        if !result.get("downloads").is_some_and(serde_json::Value::is_array) {
            return Err(format!("Visual telemetry unavailable: {result}"));
        }
        Ok(result)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn dashboard_snapshot() -> ApiResult<mdm_ipc::api::ListAnswer> {
    tauri::async_runtime::spawn_blocking(request_snapshot)
        .await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn download_action(action: String, ids: Vec<u64>) -> ApiResult<mdm_ipc::api::ActAnswer> {
    if !matches!(action.as_str(), "start" | "pause" | "remove" | "delete") {
        return Err("Unsupported download action.".into());
    }
    if ids.is_empty() || ids.len() > 100 {
        return Err("Select between 1 and 100 downloads.".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let response = send_ipc(&mdm_ipc::Command {
            action: Some(action),
            ids,
            ..Default::default()
        })?;
        serde_json::from_str(&response)
            .map_err(|_| format!("Invalid action response: {response}"))
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn add_download(url: String, later: bool) -> ApiResult<String> {
    let url = url.trim().to_owned();
    if url.is_empty() || url.len() > 8192 {
        return Err("Enter a valid URL.".into());
    }
    if !url.starts_with("http://") && !url.starts_with("https://")
        && !url.starts_with("ftp://") && !url.starts_with("magnet:") {
        return Err("Supported links start with http://, https://, ftp:// or magnet:".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        mdm_ipc::send(&mdm_ipc::Command {url:Some(url),later,silent:false,..Default::default()})
            .map_err(|e|e.to_string())?;
        Ok(serde_json::json!({"pending":true}).to_string())
    }).await.map_err(|e|e.to_string())?
}

fn suffix(path: &Path) -> Option<String> {
    path.extension()?.to_str().map(|s| s.to_ascii_lowercase())
}

/// Read validated live options from the same headless process that handles
/// downloads. Never edit downloads.json from the WebView or a second process.

fn native_host_candidates(app: &AppHandle) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(dir) = app.path().resource_dir() {
        paths.push(dir.join("misterdownloadmanager-nmhost.exe"));
        paths.push(dir.join("resources/misterdownloadmanager-nmhost.exe"));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            paths.push(dir.join("misterdownloadmanager-nmhost.exe"));
            paths.push(dir.join("resources/misterdownloadmanager-nmhost.exe"));
        }
    }
    paths
}

fn register_browser_host(app: &AppHandle) -> ApiResult<String> {
    let host = native_host_candidates(app).into_iter().find(|p| p.is_file())
        .ok_or_else(|| "MDM browser native-messaging helper was not included in this installation".to_string())?;
    // Reuse the original signed extension's host identifier, allowed origins,
    // Chromium/Firefox manifests and Windows registry logic. Register for the
    // current user only; do not overwrite other applications' registry keys.
    let output = ProcessCommand::new(&host).arg("--register")
        .stdin(Stdio::null()).output()
        .map_err(|e| format!("Could not launch the original MDM browser helper: {e}"))?;
    if !output.status.success() {
        return Err(format!("Browser host registration failed: {}",
            String::from_utf8_lossy(&output.stderr)));
    }
    Ok(format!("MDM browser integration registered: {}",
        host.to_string_lossy()))
}

#[tauri::command]
async fn quit_glass(app: AppHandle) -> ApiResult<()> {
    tauri::async_runtime::spawn_blocking(|| {
        if current_backend().is_ok_and(|state| state.glass && state.headless) {
            let _ = mdm_ipc::send(&mdm_ipc::Command {
                exit: true,
                ..Default::default()
            });
        }
    }).await.map_err(|e| e.to_string())?;
    app.exit(0);
    Ok(())
}

#[tauri::command]
async fn add_torrent_file() -> ApiResult<Option<serde_json::Value>> {
    tauri::async_runtime::spawn_blocking(|| {
        let picked = rfd::FileDialog::new().set_title("Add torrent — Mister Hybrid Glass")
            .add_filter("BitTorrent", &["torrent"]).pick_file();
        let Some(path) = picked else { return Ok(None) };
        let reply = send_ipc(&mdm_ipc::Command {
            action: Some("glass-torrent-file".into()),
            dir: Some(path.to_string_lossy().into_owned()),
            ..Default::default()
        })?;
        let result: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| format!("Invalid torrent response: {reply}"))?;
        if result.get("error").is_some() { return Err(result.to_string()); }
        Ok(Some(result))
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn browser_integration(app: AppHandle, repair: bool) -> ApiResult<String> {
    tauri::async_runtime::spawn_blocking(move || {
        if repair { register_browser_host(&app) }
        else {
            let host = native_host_candidates(&app).into_iter().find(|p| p.is_file())
                .ok_or_else(|| "Browser helper is missing from the Glass package".to_string())?;
            Ok(format!("Original MDM browser helper installed at {}. Choose repair if your extension is disconnected.",host.display()))
        }
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn bulk_action(action: String) -> ApiResult<mdm_ipc::api::ActAnswer> {
    if !matches!(action.as_str(), "stop-all" | "delete-completed") {
        return Err("Unsupported download bulk action".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let reply = send_ipc(&mdm_ipc::Command {
            action: Some("glass-bulk".into()),
            category: Some(action),
            ..Default::default()
        })?;
        let result: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| format!("Invalid bulk response: {reply}"))?;
        if result.get("error").is_some() { return Err(result.to_string()); }
        serde_json::from_value(result).map_err(|e| e.to_string())
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn file_operation(id: u64, operation: String, value: Option<String>) -> ApiResult<serde_json::Value> {
    if !matches!(operation.as_str(), "details" | "redownload" | "speed-limit" |
        "open" | "folder" | "open-with" | "queue-add" | "queue-remove" | "refresh-address" | "checksum" | "checksum-result" | "completion-options" | "extract" | "extract-status" | "extract-password" | "extract-cancel") {
        return Err("Unsupported file operation".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        // Read the current path and URL from backend by ID, never trust file
        // paths supplied by web content or browser/clipboard input.
        if operation == "open" || operation == "folder" {
            let state=send_ipc(&mdm_ipc::Command{query:Some("glass-move-status".into()),ids:vec![id],..Default::default()})?;
            let state:serde_json::Value=serde_json::from_str(&state).map_err(|e|e.to_string())?;
            if state["moved_away"]==true {return Err("The file was moved, but Windows could not report its new location".into());}
            let downloads = request_snapshot()?;
            let file = downloads.downloads.iter().find(|d| d.id == id)
                .ok_or_else(|| "Download no longer exists".to_string())?;
            let path = PathBuf::from(&file.path);
            let target = if operation == "folder" {
                if path.is_dir() { path.clone() }
                else { path.parent().ok_or("Download has no folder")?.to_path_buf() }
            } else {
                if file.status != "Complete" {
                    return Err("The download is not complete yet".into());
                }
                if !path.exists() {
                    return Err("The downloaded file cannot be found".into());
                }
                path
            };
            open::that(&target).map_err(|e| format!("Windows could not open {}: {e}",target.display()))?;
            return Ok(serde_json::json!({"ok":true}));
        }
        let reply = send_ipc(&mdm_ipc::Command {
            action: Some("glass-item".into()),
            category: Some(operation),
            ids: vec![id],
            queue: value,
            ..Default::default()
        })?;
        let data: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| format!("Invalid native download response: {reply}"))?;
        if data.get("error").is_some() { return Err(data.to_string()) };
        Ok(data)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn queue_action(name: String, action: String) -> ApiResult<mdm_ipc::api::ActAnswer> {
    if name.is_empty() || name.len() > 256
        || !matches!(action.as_str(), "start_queue" | "stop_queue") {
        return Err("Unknown queue operation".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let reply = send_ipc(&mdm_ipc::Command {
            action: Some(action),
            queue: Some(name),
            ..Default::default()
        })?;
        serde_json::from_str(&reply)
            .map_err(|_| format!("Queue action failed: {reply}"))
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn glass_settings() -> ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(|| {
        let reply = send_ipc(&mdm_ipc::Command {
            query: Some("glass-settings".into()),
            ..Default::default()
        })?;
        let settings: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| "Failed to decode Rust downloader settings".to_string())?;
        if !settings.is_object() || settings.get("error").is_some() {
            return Err(format!("Settings not available: {reply}"));
        }
        Ok(settings)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn update_glass_setting(key: String, value: String) -> ApiResult<serde_json::Value> {
    const VALID: &[&str] = &[
        "max_connections", "speed_limit_on", "speed_limit_kb",
        "global_limit_on", "global_limit_kb", "start_immediately",
        "only_add_to_queue", "confirm_delete", "torrent_keep_sharing",
        "torrent_dht", "torrent_lsd", "proxy_from_browser",
        "capture_opened", "net_adapter", "show_complete", "show_progress",
        "advanced_integration", "double_click_open"
    ];
    if !VALID.contains(&key.as_str()) || value.len() > 256 {
        return Err("Unsupported settings change".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let reply = send_ipc(&mdm_ipc::Command {
            action: Some("glass-setting".into()),
            category: Some(key),
            queue: Some(value),
            ..Default::default()
        })?;
        let result: serde_json::Value = serde_json::from_str(&reply)
            .map_err(|_| "Invalid response from Rust settings service".to_string())?;
        if result.get("saved").and_then(|v| v.as_bool()) != Some(true) {
            return Err(format!("Settings change rejected: {reply}"));
        }
        Ok(result)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
async fn select_wallpaper(app: AppHandle, target: String) -> ApiResult<Option<String>> {
    if target != "main" && target != "details" {
        return Err("Unknown wallpaper target.".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let file = rfd::FileDialog::new()
            .set_title("Choose Mister Hybrid wallpaper")
            .add_filter("Images and videos", &["png", "jpg", "jpeg", "webp", "mp4", "webm", "mov", "m4v"])
            .pick_file();
        let Some(file) = file else { return Ok(None) };
        let extension = suffix(&file).ok_or("Selected file has no supported extension")?;
        if !matches!(extension.as_str(), "png" | "jpg" | "jpeg" | "webp" | "mp4" | "webm" | "mov" | "m4v") {
            return Err("Use PNG, JPG, WebP, MP4, WebM or MOV.".into());
        }
        let bytes = fs::metadata(&file).map_err(|e| e.to_string())?.len();
        if bytes > 2_000_000_000 {
            return Err("Wallpaper must be smaller than 2 GB.".into());
        }
        let dir = app.path().app_data_dir().map_err(|e| e.to_string())?
            .join("wallpapers");
        fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?.as_millis();
        let destination = dir.join(format!("{target}-{stamp}.{extension}"));
        fs::copy(&file, &destination).map_err(|e| format!("Could not save wallpaper: {e}"))?;
        Ok(Some(destination.to_string_lossy().into_owned()))
    }).await.map_err(|e| e.to_string())?
}

fn test_browser_args()->Option<String>{
    let port=std::env::var("GLASS_TEST_CDP_PORT").ok()?.parse::<u16>().ok().filter(|p|*p>1023)?;
    Some(format!("--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --remote-debugging-port={port} --remote-debugging-address=127.0.0.1 --remote-allow-origins=*"))
}

fn main() {
    let mut context=tauri::generate_context!();
    if let Some(args)=test_browser_args(){if let Some(window)=context.config_mut().app.windows.first_mut(){window.additional_browser_args=Some(args);}}
    tauri::Builder::default()
        // Glass is the one and only UI process: a second launch restores it.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            show_main(app);
        }))
        .setup(|app| {
            if let Some(main)=app.get_webview_window("main") {
                let (width,height)=lifecycle::fit_size(app.handle(),1480.0,850.0);
                let _=main.set_min_size(Some(tauri::LogicalSize::new(width.min(600.0),height.min(420.0))));
                let _=main.set_size(tauri::LogicalSize::new(width,height));
                let _=main.center();
            }
            app.manage(HiddenDownloadWindows::default());
            let menu = build_tray_menu(app.handle()).map_err(std::io::Error::other)?;
            TrayIconBuilder::with_id("auralis-tray")
                .icon(app.default_window_icon().cloned().ok_or("No packaged Auralis icon")?)
                .tooltip("Auralis Download Manager")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_main(app),
                    "add" => { let _ = lifecycle::open(app, "tray-add-url", "add=url", 590.0, 390.0); },
                    "batch" | "batch-clipboard" => { let _ = lifecycle::open(app, "tray-batch", "tool=batch", 760.0, 680.0); },
                    "speed-limit" => { let _ = lifecycle::open(app, "tray-settings", "settings=1&tab=Connection", 920.0, 700.0); },
                    "scheduler" => { let _ = lifecycle::open(app, "tray-scheduler", "schedule=1", 860.0, 660.0); },
                    "options" => { let _ = lifecycle::open(app, "tray-options", "settings=1", 920.0, 700.0); },
                    "start-queue" | "stop-queue" => {
                        if let Ok(snapshot) = request_snapshot() {
                            if let Some(queue) = snapshot.queues.first() {
                                let action = if event.id.as_ref() == "start-queue" { "start_queue" } else { "stop_queue" };
                                let _ = send_ipc(&mdm_ipc::Command { action: Some(action.into()), queue: Some(queue.name.clone()), ..Default::default() });
                            }
                        }
                    },
                    id if id.starts_with("restore-download-") => {
                        if let Ok(download_id) = id.trim_start_matches("restore-download-").parse::<u64>() { restore_download_window(app, download_id); }
                    }
                    "quit" => {
                        // This is an explicit EXIT, not closing/minimizing.
                        // The headless service persists its state on exit.
                        if current_backend().is_ok_and(|b| b.headless && b.glass) {
                            let _ = mdm_ipc::send(&mdm_ipc::Command {
                                exit: true,
                                ..Default::default()
                            });
                        }
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {
                        show_main(tray.app_handle());
                    }
                })
                .build(app)?;
            lifecycle::start(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { .. } = event {
                if let Some(id)=window.label().strip_prefix("tool-video-").and_then(|s|s.parse::<u64>().ok()) {
                    thread::spawn(move||{let _=send_ipc(&mdm_ipc::Command{action:Some("glass-video".into()),category:Some("close".into()),ids:vec![id],..Default::default()});});
                }
                for kind in ["queue","duplicate"]{
                    if let Some(lease)=window.label().strip_prefix(&format!("tool-{kind}-")).and_then(|s|s.parse::<u64>().ok()){
                        thread::spawn(move||{let _=send_ipc(&mdm_ipc::Command{action:Some("glass-prompt".into()),queue:Some(serde_json::json!({"kind":kind,"lease":lease,"cancel":true}).to_string()),..Default::default()});});
                    }
                }
                if let Some(id)=window.label().strip_prefix("power-").and_then(|s|s.parse::<u64>().ok()) {
                    thread::spawn(move || {let _=send_ipc(&mdm_ipc::Command {action:Some("glass-power".into()),queue:Some(serde_json::json!({"id":id,"action":"cancel"}).to_string()),..Default::default()});});
                }
                if let Some(id)=window.label().strip_prefix("info-").and_then(|s|s.parse::<u64>().ok()) {
                    thread::spawn(move || {let _=send_ipc(&mdm_ipc::Command {action:Some("glass-file-info".into()),category:Some("cancel".into()),ids:vec![id],..Default::default()});});
                }
            }
            if window.label() == "main" {
                if let WindowEvent::CloseRequested { api, .. } = event {
                    // Closing the X hides the glass window, never exits the
                    // downloader. Restore it through the single Glass tray.
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            material_window::set_material_window_shape, pending_file_info, file_info_action, choose_download_path, window_preferences, glass_tool, choose_folder, open_glass_window, close_progress_windows, hide_download_to_tray, drag_download, drag_state, choose_move, clipboard_text, video_tool, browser_video,
            boot_engine, dashboard_snapshot, dashboard_visuals, download_action,
            add_download, select_wallpaper, queue_action, glass_settings, update_glass_setting,
            browser_integration, extension_store_link, open_extension_store, bulk_action, file_operation, add_torrent_file, quit_glass, open_upstream_releases, fork_update::glass_update_check, fork_update::glass_update_download, fork_update::glass_update_install
        ])
        .run(context)
        .expect("error starting Auralis Download Manager desktop");
}
