//! Explicit user-chosen preferences backups. Credentials stay on the device.
use crate::{ApiResult, send_ipc};
use serde_json::{Value, json};
use tauri::AppHandle;

fn parse_reply(text: &str) -> ApiResult<Value> {
    let value: Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
    if let Some(error) = value.get("error").and_then(Value::as_str) {
        return Err(error.into());
    }
    Ok(value)
}
#[tauri::command]
pub async fn export_preferences(app: AppHandle, ui: Value) -> ApiResult<Option<String>> {
    tauri::async_runtime::spawn_blocking(move||{
        if !ui.is_object() || ui.to_string().len()>3*1024*1024 {return Err("Invalid appearance settings".into())}
        let Some(path)=rfd::FileDialog::new().set_title("Save Auralis preferences backup").set_file_name("auralis-preferences.json").add_filter("Auralis backup", &["json"]).save_file() else{return Ok(None)};
        let settings=parse_reply(&send_ipc(&mdm_ipc::Command{query:Some("glass-backup-settings".into()),..Default::default()})?)?;
        let startup=crate::startup::startup_settings(app)?;
        let body=serde_json::to_vec_pretty(&json!({"format":"auralis-preferences","version":1,"appearance":ui,"settings":settings["settings"],"startup":startup})).map_err(|e|e.to_string())?;
        if body.len()>4*1024*1024 {return Err("Preferences backup is too large".into())}
        mdm_ipc::private_write(&path,&body).map_err(|e|format!("Could not save backup: {e}"))?;
        Ok(Some(path.to_string_lossy().into_owned()))
    }).await.map_err(|e|e.to_string())?
}
#[tauri::command]
pub async fn import_preferences(app: AppHandle) -> ApiResult<Option<Value>> {
    tauri::async_runtime::spawn_blocking(move || {
        let Some(path) = rfd::FileDialog::new()
            .set_title("Restore Auralis preferences")
            .add_filter("Auralis backup", &["json"])
            .pick_file()
        else {
            return Ok(None);
        };
        let metadata = std::fs::metadata(&path).map_err(|e| e.to_string())?;
        if metadata.len() > 4 * 1024 * 1024 {
            return Err("Backup file is too large".into());
        }
        let body = std::fs::read(&path).map_err(|e| e.to_string())?;
        let backup: Value =
            serde_json::from_slice(&body).map_err(|e| format!("Invalid backup file: {e}"))?;
        if backup["format"] != "auralis-preferences"
            || backup["version"] != 1
            || !backup["appearance"].is_object()
            || !backup["settings"].is_object()
        {
            return Err("This is not a supported Auralis preferences backup".into());
        }
        let startup:Option<crate::startup::StartupSettings> = backup.get("startup").map(|v| serde_json::from_value(v.clone()).map_err(|e|format!("Invalid startup preferences: {e}"))).transpose()?;
        if startup.as_ref().is_some_and(|s|s.mode!="minimized"&&s.mode!="window") {return Err("Invalid startup mode".into())}
        let settings = serde_json::to_string(&backup["settings"]).map_err(|e| e.to_string())?;
        parse_reply(&send_ipc(&mdm_ipc::Command {
            action: Some("glass-restore-settings".into()),
            queue: Some(settings),
            ..Default::default()
        })?)?;
        if let Some(startup)=startup {crate::startup::set_startup_settings(app,startup.enabled,startup.mode).map_err(|e|format!("Download settings were restored, but Windows startup could not be restored: {e}"))?;}
        Ok(Some(backup["appearance"].clone()))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn run_full_backup_job(command: mdm_ipc::Command) -> ApiResult<Value> {
    let started = parse_reply(&send_ipc(&command)?)?;
    let id = started["id"]
        .as_u64()
        .ok_or("The downloader did not confirm the backup request.")?;
    let status = mdm_ipc::Command {
        query: Some("glass-full-backup-status".into()),
        ids: vec![id],
        ..Default::default()
    };
    let mut delayed = 0;
    loop {
        std::thread::sleep(std::time::Duration::from_millis(350));
        let text = send_ipc(&status)?;
        if text == "timeout" && delayed < 12 {
            // The engine may be saving the restored history. Poll the existing
            // job without starting an export or restore a second time.
            delayed += 1;
            continue;
        }
        let reply = parse_reply(&text)?;
        if reply["pending"] != true {
            return Ok(reply);
        }
        delayed = 0;
    }
}

#[tauri::command]
pub async fn export_full_backup(app: AppHandle, ui: Value) -> ApiResult<Option<Value>> {
    tauri::async_runtime::spawn_blocking(move || {
        use std::io::Write;
        if !ui.is_object() || ui.to_string().len() > 3 * 1024 * 1024 {
            return Err("Invalid appearance settings.".into());
        }
        let Some(path) = rfd::FileDialog::new()
            .set_title("Back up Auralis downloads")
            .set_file_name("auralis-downloads.auralis-backup")
            .add_filter("Auralis download backup", &["auralis-backup"])
            .save_file()
        else {
            return Ok(None);
        };
        let folder = mdm_ipc::data_dir()
            .ok_or("No application data folder is available.")?
            .join("backup-ui");
        mdm_ipc::private_dir(&folder).map_err(|error| error.to_string())?;
        // Pass settings through the private profile folder. The IPC request
        // protocol has a lower message limit than the appearance manifest.
        let mut preferences =
            tempfile::NamedTempFile::new_in(folder).map_err(|error| error.to_string())?;
        let startup = crate::startup::startup_settings(app)?;
        serde_json::to_writer(
            &mut preferences,
            &json!({"appearance": ui, "startup": startup}),
        )
        .map_err(|error| error.to_string())?;
        preferences.flush().map_err(|error| error.to_string())?;
        let response = run_full_backup_job(mdm_ipc::Command {
            action: Some("glass-export-full-backup".into()),
            dir: Some(path.to_string_lossy().into_owned()),
            queue: Some(preferences.path().to_string_lossy().into_owned()),
            ..Default::default()
        })?;
        Ok(Some(response))
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn import_full_backup(app: AppHandle) -> ApiResult<Option<Value>> {
    tauri::async_runtime::spawn_blocking(move || {
        let Some(archive) = rfd::FileDialog::new()
            .set_title("Choose an Auralis download backup")
            .add_filter("Auralis download backup", &["auralis-backup"])
            .pick_file()
        else {
            return Ok(None);
        };
        let Some(folder) = rfd::FileDialog::new()
            .set_title("Choose a location for the restored downloads")
            .pick_folder()
        else {
            return Ok(None);
        };
        let mut target = folder.join("Auralis Restored Downloads");
        for index in 2..=10_000 {
            match std::fs::symlink_metadata(&target) {
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
                Err(error) => return Err(error.to_string()),
                Ok(_) => target = folder.join(format!("Auralis Restored Downloads ({index})")),
            }
        }
        let mut response = run_full_backup_job(mdm_ipc::Command {
            action: Some("glass-import-full-backup".into()),
            dir: Some(archive.to_string_lossy().into_owned()),
            queue: Some(target.to_string_lossy().into_owned()),
            ..Default::default()
        })?;
        if let Some(saved) = response
            .get_mut("startup")
            .map(Value::take)
            .filter(|value| !value.is_null())
        {
            let restored = serde_json::from_value::<crate::startup::StartupSettings>(saved)
                .map_err(|error| error.to_string())
                .and_then(|startup| {
                    crate::startup::set_startup_settings(app, startup.enabled, startup.mode)
                });
            if let Err(error) = restored {
                response["warning"] = json!(format!(
                    "Downloads were restored. Windows startup could not be restored: {error}"
                ));
            }
        }
        Ok(Some(response))
    })
    .await
    .map_err(|error| error.to_string())?
}
