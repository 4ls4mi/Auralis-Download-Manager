#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// Windows-only Tauri shell. Keeps MDM's production download engine as a
// bundled, hidden legacy process until app-only logic has been extracted.
// Frontend never accesses MDM's token or loopback socket directly.
mod lifecycle;
mod native_actions;
use lifecycle::{pending_file_info, file_info_action, choose_download_path, window_preferences, glass_tool, choose_folder, open_glass_window};
use native_actions::{drag_download, choose_move};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command as ProcessCommand, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
use serde::Deserialize;

type ApiResult<T> = Result<T, String>;

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
        .map_err(|_| "Another original Mister Download Manager instance is running.             It still owns the old tray icon. Please finish active downloads,             then exit the original MDM from its tray icon before starting             Mister Hybrid Glass. The current downloads and settings will be preserved.".into())
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

fn main() {
    tauri::Builder::default()
        // Glass is the one and only UI process: a second launch restores it.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            show_main(app);
        }))
        .setup(|app| {
            if let Some(main)=app.get_webview_window("main") {
                let (width,height)=lifecycle::fit_size(app.handle(),1480.0,850.0);
                let _=main.set_min_size(Some(tauri::LogicalSize::new(width.min(720.0),height.min(520.0))));
                let _=main.set_size(tauri::LogicalSize::new(width,height));
                let _=main.center();
            }
            let show = MenuItem::with_id(app, "show", "Open Mister Hybrid Glass", true, None::<&str>)?;
            let exit = MenuItem::with_id(app, "quit", "Exit Glass and stop downloads", true, None::<&str>)?;
            let downloads = MenuItem::with_id(app, "downloads", "Restore download windows", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &downloads, &exit])?;
            TrayIconBuilder::with_id("glass-tray")
                .icon(app.default_window_icon().cloned().ok_or("No packaged tray icon")?)
                .tooltip("Mister Hybrid Glass — Rust download engine")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_main(app),
                    "downloads" => {
                        for (label,w) in app.webview_windows() {
                            if label != "main" { let _=w.show(); let _=w.unminimize(); }
                        }
                    },
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
            pending_file_info, file_info_action, choose_download_path, window_preferences, glass_tool, choose_folder, open_glass_window, drag_download, choose_move,
            boot_engine, dashboard_snapshot, dashboard_visuals, download_action,
            add_download, select_wallpaper, queue_action, glass_settings, update_glass_setting,
            browser_integration, bulk_action, file_operation, add_torrent_file, quit_glass, open_upstream_releases
        ])
        .run(tauri::generate_context!())
        .expect("error starting Mister Hybrid glass desktop");
}
