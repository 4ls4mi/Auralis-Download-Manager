#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// Windows-only Tauri shell. Keeps MDM's production download engine as a
// bundled, hidden legacy process until app-only logic has been extracted.
// Frontend never accesses MDM's token or loopback socket directly.
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command as ProcessCommand, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};

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

fn boot_existing_engine(app: &AppHandle) -> ApiResult<String> {
    // An existing instance always wins: don't start duplicate downloads,
    // overwrite settings, or touch another process's files.
    let status = send_ipc(&mdm_ipc::Command {
        api: Some(true),
        ..Default::default()
    });
    if status.is_err() {
        let backend = possible_legacy_paths(app).into_iter()
            .find(|candidate| candidate.is_file())
            .ok_or_else(|| "MDM backend is not running and its bundled executable is missing. Use the Windows installer for this build.".to_string())?;
        // /startup is supported by the original app: starts minimized to tray.
        ProcessCommand::new(backend)
            .arg("/startup")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("Could not launch original MDM backend: {e}"))?;
        let mut ready = false;
        for _ in 0..40 {
            thread::sleep(Duration::from_millis(250));
            if send_ipc(&mdm_ipc::Command {
                api: Some(true),
                ..Default::default()
            }).is_ok() {
                ready = true;
                break;
            }
        }
        if !ready {
            return Err("MDM backend did not become available. Check its tray icon or log.".into());
        }
    }
    // Confirm that the version of MDM really supports the API before claiming connected.
    request_snapshot()?;
    Ok("Connected to original MDM download engine (local authenticated IPC)".into())
}

#[tauri::command]
async fn boot_engine(app: AppHandle) -> ApiResult<String> {
    tauri::async_runtime::spawn_blocking(move || boot_existing_engine(&app))
        .await.map_err(|e| e.to_string())?
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
        send_ipc(&mdm_ipc::Command {
            url: Some(url),
            later,
            silent: true,
            ..Default::default()
        })
    }).await.map_err(|e| e.to_string())?
}

fn suffix(path: &Path) -> Option<String> {
    path.extension()?.to_str().map(|s| s.to_ascii_lowercase())
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
        .invoke_handler(tauri::generate_handler![
            boot_engine, dashboard_snapshot, download_action,
            add_download, select_wallpaper
        ])
        .run(tauri::generate_context!())
        .expect("error starting Mister Hybrid glass desktop");
}
