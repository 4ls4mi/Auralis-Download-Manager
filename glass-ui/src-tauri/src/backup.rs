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
        if !ui.is_object() || ui.to_string().len()>262144 {return Err("Invalid appearance settings".into())}
        let Some(path)=rfd::FileDialog::new().set_title("Save Auralis preferences backup").set_file_name("auralis-preferences.json").add_filter("Auralis backup", &["json"]).save_file() else{return Ok(None)};
        let settings=parse_reply(&send_ipc(&mdm_ipc::Command{query:Some("glass-backup-settings".into()),..Default::default()})?)?;
        let startup=crate::startup::startup_settings(app)?;
        let body=serde_json::to_vec_pretty(&json!({"format":"auralis-preferences","version":1,"appearance":ui,"settings":settings["settings"],"startup":startup})).map_err(|e|e.to_string())?;
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
