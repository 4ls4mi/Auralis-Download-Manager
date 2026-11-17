//! Window lifecycle belongs to the native shell, so hiding the main WebView
//! cannot stop browser prompts or leave a completed progress window behind.
use super::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{Emitter, WebviewUrl, WebviewWindowBuilder};
static AUTO_PROGRESS: AtomicBool = AtomicBool::new(true);

pub fn fit_size(app:&AppHandle,width:f64,height:f64)->(f64,f64) {
    app.get_webview_window("main").and_then(|w|w.current_monitor().ok().flatten())
        .map(|m|(width.min((m.size().width as f64/m.scale_factor()-32.0).max(360.0)),
            height.min((m.size().height as f64/m.scale_factor()-76.0).max(300.0))))
        .unwrap_or((width,height))
}

pub fn open(app: &AppHandle, label: &str, route: &str, width: f64, height: f64) -> ApiResult<()> {
    let priority = label.starts_with("info-") || label.starts_with("tool-video-") || label.starts_with("complete-");
    if let Some(w) = app.get_webview_window(label) {
        if priority { let _ = w.set_always_on_top(true); }
        let _ = w.emit("glass-navigate", route);
        w.show().map_err(|e| e.to_string())?;
        let _ = w.unminimize();
        let _ = w.set_focus();
        if priority { let _ = w.set_always_on_top(false); }
        return Ok(());
    }
    let (width,height)=fit_size(app,width,height);
    let mut builder=WebviewWindowBuilder::new(app, label, WebviewUrl::App(format!("index.html?{route}").into()));
    if let Some(args)=test_browser_args(){builder=builder.additional_browser_args(&args);}
    let w = builder
        .title("Mister Hybrid Glass").always_on_top(priority).inner_size(width, height)
        .min_inner_size(width.min(440.0), height.min(320.0)).center().decorations(false)
        .transparent(true).shadow(false).resizable(true).build()
        .map_err(|e| e.to_string())?;
    if priority { let _ = w.show(); let _ = w.set_focus(); let _ = w.set_always_on_top(false); }
    Ok(())
}

pub fn start(app: AppHandle) {
    thread::spawn(move || {
        let mut previous: Option<HashMap<u64, String>> = None;
        let mut helpers_checked = false;
        let mut last_info = 0;
        let mut last_power = 0;
        let mut last_import = 0;
        let mut last_duplicate = 0;
        let mut last_queue = 0;
        let mut seen_videos = std::collections::HashSet::new();
        loop {
            thread::sleep(Duration::from_millis(650));
            if !current_backend().is_ok_and(|b|b.headless&&b.glass) {continue;}
            let Ok(snapshot) = request_snapshot() else { continue; };
            if !helpers_checked {
                let helpers=send_ipc(&mdm_ipc::Command{query:Some("glass-helpers".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
                if let Some(tools)=helpers.as_ref().and_then(|v|v["tools"].as_array()) {
                    helpers_checked=true;
                    if tools.iter().any(|tool|tool["version"].is_null()) {let _=open(&app,"tool-helpers","tool=helpers",680.0,520.0);}
                }
            }

            let config = send_ipc(&mdm_ipc::Command {query:Some("glass-settings".into()),..Default::default()})
                .ok().and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
            let complete = config.as_ref().and_then(|c| c["show_complete"].as_bool()).unwrap_or(false);
            let progress = AUTO_PROGRESS.load(Ordering::Relaxed)
                && config.as_ref().and_then(|c| c["show_progress"].as_bool()).unwrap_or(true);
            let mut transitions = Vec::new();
            if let Some(old) = &previous {
                for file in &snapshot.downloads {
                    if old.get(&file.id).map(String::as_str) != Some(file.status.as_str()) {
                        if file.status == "Complete" || file.status == "Downloading" && progress {
                            transitions.push((file.id, file.status.clone()));
                        }
                    }
                }
            }
            previous = Some(snapshot.downloads.iter().map(|d| (d.id,d.status.clone())).collect());
            let info = send_ipc(&mdm_ipc::Command {query:Some("glass-file-info".into()),..Default::default()})
                .ok().and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
            let pending = info.as_ref().filter(|v| v["info"].is_object()).and_then(|v| v["id"].as_u64());
            let request = pending.filter(|id| *id != last_info);
            if let Some(id) = request { last_info = id; }
            let power=send_ipc(&mdm_ipc::Command{query:Some("glass-power".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
            let exit=power.as_ref().is_some_and(|p|p["exit"]==true);
            let power_id=power.as_ref().filter(|p|p["pending"].is_object()).and_then(|p|p["id"].as_u64()).filter(|id|*id!=last_power);
            if let Some(id)=power_id {last_power=id;}
            let imported=send_ipc(&mdm_ipc::Command{query:Some("glass-grabber-status".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
            let import=imported.as_ref().filter(|g|g["pending"]==true).and_then(|g|g["version"].as_u64()).filter(|v|*v!=last_import);
            if let Some(v)=import{last_import=v;}
            let prompts=send_ipc(&mdm_ipc::Command{query:Some("glass-prompts".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
            let duplicate=prompts.as_ref().and_then(|p|p["duplicate"]["lease"].as_u64()).filter(|id|*id!=last_duplicate);if let Some(id)=duplicate{last_duplicate=id;}
            let queue=prompts.as_ref().and_then(|p|p["queue"]["lease"].as_u64()).filter(|id|*id!=last_queue);if let Some(id)=queue{last_queue=id;}
            let videos=send_ipc(&mdm_ipc::Command{query:Some("glass-videos".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
            let new_videos:Vec<u64>=videos.as_ref().and_then(|v|v["ids"].as_array()).into_iter().flatten().filter_map(|id|id.as_u64()).filter(|id|seen_videos.insert(*id)).collect();
            let owner = app.clone();
            {
                for (id, status) in transitions {
                    if status == "Complete" {
                        if let Some(w) = owner.get_webview_window(&format!("download-{id}")) { let _ = w.close(); }
                        if complete { let _ = open(&owner,&format!("complete-{id}"),&format!("complete={id}"),720.0,420.0); }
                    } else {
                        let _ = open(&owner,&format!("download-{id}"),&format!("detail={id}"),880.0,500.0);
                    }
                }
                for id in new_videos {let _=open(&owner,&format!("tool-video-{id}"),&format!("tool=video&browser={id}"),720.0,560.0);}
                if exit {let _=mdm_ipc::send(&mdm_ipc::Command{exit:true,..Default::default()});owner.exit(0);return;}
                if let Some(id)=duplicate{let _=open(&owner,&format!("tool-duplicate-{id}"),&format!("tool=duplicate&lease={id}"),620.0,400.0);}
                if let Some(id)=queue{let _=open(&owner,&format!("tool-queue-{id}"),&format!("tool=queue&lease={id}"),600.0,340.0);}
                if import.is_some(){let _=open(&owner,"tool-grabber","tool=grabber",900.0,680.0);}
                if let Some(id)=power_id {let _=open(&owner,&format!("power-{id}"),&format!("power={id}"),590.0,330.0);}
                if let Some(id) = request { let _ = open(&owner,&format!("info-{id}"),&format!("request={id}"),780.0,560.0); }
            }
        }
    });
}

#[tauri::command]
pub fn window_preferences(auto_progress: bool) { AUTO_PROGRESS.store(auto_progress,Ordering::Relaxed); }

#[tauri::command]
pub async fn pending_file_info() -> ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(|| {
        let s=send_ipc(&mdm_ipc::Command{query:Some("glass-file-info".into()),..Default::default()})?;
        serde_json::from_str(&s).map_err(|e| e.to_string())
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn file_info_action(id:u64, action:String, payload:Option<serde_json::Value>) -> ApiResult<serde_json::Value> {
    if !matches!(action.as_str(),"commit"|"cancel"|"category") { return Err("Invalid file-info action".into()); }
    tauri::async_runtime::spawn_blocking(move || {
        let s=send_ipc(&mdm_ipc::Command{action:Some("glass-file-info".into()),ids:vec![id],category:Some(action),queue:payload.map(|p|p.to_string()),..Default::default()})?;
        let result:serde_json::Value=serde_json::from_str(&s).map_err(|e|e.to_string())?;
        if let Some(error)=result.get("error") {return Err(error.to_string());}
        Ok(result)
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn choose_download_path(current:String) -> ApiResult<Option<String>> {
    tauri::async_runtime::spawn_blocking(move || {
        let path=PathBuf::from(&current);
        let mut picker=rfd::FileDialog::new().set_title("Save download as");
        if let Some(name)=path.file_name() { picker=picker.set_file_name(name.to_string_lossy()); }
        if let Some(parent)=path.parent().filter(|p|p.is_absolute()) { picker=picker.set_directory(parent); }
        Ok(picker.save_file().map(|p|p.to_string_lossy().into_owned()))
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn glass_tool(action:String,payload:Option<serde_json::Value>) -> ApiResult<serde_json::Value> {
    if !matches!(action.as_str(),"category"|"queues"|"schedule"|"power"|"power-state"|"original-settings"|"original-setting"|"batch"|"grabber"|"grabber-state"|"categories"|"accounts"|"account"|"prompts"|"prompt"|"helpers"|"helpers-install"|"upstream-status"|"upstream-check"|"gallery") {return Err("Unsupported tool".into());}
    tauri::async_runtime::spawn_blocking(move||{
        let mut cmd=mdm_ipc::Command::default();
        if action=="queues" {cmd.query=Some("glass-queues".into());}
        else if action=="grabber-state"||action=="categories"||action=="accounts"||action=="prompts"||action=="helpers"{cmd.query=Some(format!("glass-{action}"));}
        else if action=="helpers-install" {cmd.action=Some("glass-helpers".into());cmd.queue=payload.map(|p|p.to_string());}
        else if action=="upstream-status" {cmd.query=Some("glass-upstream-check".into());}
        else if action=="upstream-check" {cmd.action=Some("glass-upstream-check".into());}
        else if action=="power-state" {cmd.query=Some("glass-power".into());}
        else if action=="original-settings" {cmd.query=Some("glass-original-settings".into());}
        else {cmd.action=Some(format!("glass-{action}"));cmd.queue=payload.map(|p|p.to_string());}
        let s=send_ipc(&cmd)?;
        let value:serde_json::Value=serde_json::from_str(&s).map_err(|e|e.to_string())?;
        if let Some(e)=value.get("error") {return Err(e.to_string());}
        Ok(value)
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn choose_folder()->ApiResult<Option<String>> {
    tauri::async_runtime::spawn_blocking(||Ok(rfd::FileDialog::new().set_title("Choose folder").pick_folder().map(|p|p.to_string_lossy().into_owned()))).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn open_glass_window(app:AppHandle,label:String,url:String,width:f64,height:f64)->ApiResult<()> {
    if label.is_empty()||label.len()>100||!label.chars().all(|c|c.is_ascii_alphanumeric()||c=='-'||c=='_')||!url.starts_with("/?")||url.len()>1024||url.contains(['\\',':'])||!width.is_finite()||!height.is_finite(){return Err("Invalid download window".into());}
    tauri::async_runtime::spawn_blocking(move||open(&app,&label,&url[2..],width.clamp(360.0,1800.0),height.clamp(280.0,1200.0))).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub fn close_progress_windows(app:AppHandle,ids:Vec<u64>){for id in ids{if let Some(w)=app.get_webview_window(&format!("download-{id}")){let _=w.close();}}}
