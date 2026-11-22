//! Window lifecycle belongs to the native shell, so hiding the main WebView
//! cannot stop browser prompts or leave a completed progress window behind.
use super::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{Emitter, WebviewUrl, WebviewWindow, WebviewWindowBuilder, utils::config::WindowConfig};
static AUTO_PROGRESS: AtomicBool = AtomicBool::new(true);

pub fn fit_size(app:&AppHandle,width:f64,height:f64)->(f64,f64) {
    app.get_webview_window("main").and_then(|w|w.current_monitor().ok().flatten())
        .or_else(||app.primary_monitor().ok().flatten())
        .map(|m|(width.min((m.size().width as f64/m.scale_factor()-32.0).max(360.0)),
            height.min((m.size().height as f64/m.scale_factor()-76.0).max(300.0))))
        .unwrap_or((width,height))
}

// Use the same explicit transparent WebView creation for the main window and popups.
fn build_glass_window(app: &AppHandle, config: &WindowConfig) -> ApiResult<WebviewWindow> {
    WebviewWindowBuilder::from_config(app, config).map_err(|error| error.to_string())?
        .transparent(true).background_color(tauri::window::Color(0, 0, 0, 0))
        .shadow(false).build().map_err(|error| error.to_string())
}

pub fn create_main(app: &AppHandle) -> ApiResult<()> {
    let mut config = app.config().app.windows.first().cloned().ok_or("Main window configuration is missing")?;
    let (width,height) = fit_size(app, 814.0, 468.0);
    config.width = width;
    config.height = height;
    config.min_width = Some(width.min(600.0));
    config.min_height = Some(height.min(420.0));
    build_glass_window(app, &config)?;
    Ok(())
}

pub fn open(app: &AppHandle, label: &str, route: &str, width: f64, height: f64) -> ApiResult<()> {
    let priority = label.starts_with("info-") || label.starts_with("download-") || label.starts_with("tool-video-") || label == "tool-update-notice" || label == "tool-progress-tray";
    if let Some(w) = app.get_webview_window(label) {
        // A corner notice must never take focus when another update check runs.
        if label == "tool-update-toast" { return show_update_toast(w); }
        if priority { let _ = w.set_always_on_top(true); }
        let _ = w.emit("glass-navigate", route);
        w.show().map_err(|e| e.to_string())?;
        if let Some(id) = label.strip_prefix("download-").and_then(|v| v.parse::<u64>().ok()) {
            if let Ok(mut hidden) = app.state::<HiddenDownloadWindows>().0.lock() { hidden.remove(&id); }
            super::refresh_tray_menu(app);
        }
        let _ = w.unminimize();
        let _ = w.set_focus();
        if priority { let raised=w.clone(); thread::spawn(move||{thread::sleep(Duration::from_millis(1200));let _=raised.set_always_on_top(false);}); }
        return Ok(());
    }
    let (width,height)=fit_size(app,width,height);
    // Use the same transparent-window configuration as the main window. In
    // particular this includes Windows noRedirectionBitmap, which avoids an
    // opaque/white backing around secondary glass windows on some systems.
    let mut config=app.config().app.windows.first().cloned().ok_or("Main window configuration is missing")?;
    config.label=label.to_owned();
    config.visible=true;
    if label == "tool-update-toast" {
        // The WebView positions itself before showing, avoiding a centered flash.
        config.visible=false;
        config.focus=false;
        config.skip_taskbar=true;
    }
    config.url=WebviewUrl::App(format!("index.html?{route}").into());
    config.width = width;
    config.height = height;
    config.min_width = Some(width.min(440.0));
    config.min_height = Some(height.min(320.0));
    config.always_on_top = priority;
    let w = build_glass_window(app, &config)?;
    if priority { let _ = w.show(); let _ = w.set_focus(); let raised=w.clone(); thread::spawn(move||{thread::sleep(Duration::from_millis(1200));let _=raised.set_always_on_top(false);}); }
    Ok(())
}

pub fn start(app: AppHandle) {
    thread::spawn(move || {
        let mut previous: Option<HashMap<u64, String>> = None;
        let mut tray_items: Vec<(u64, MenuItem<tauri::Wry>)> = Vec::new();
        let mut helpers_checked = super::is_isolated_test();
        let mut last_queue_running: Option<bool> = None;
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
            let queue_running=snapshot.queues.first().is_some_and(|q|q.running);
            if last_queue_running!=Some(queue_running){last_queue_running=Some(queue_running);super::refresh_tray_menu(&app);}
            let hidden=app.state::<HiddenDownloadWindows>().0.lock().map(|v|v.clone()).unwrap_or_default();
            let visuals = if hidden.is_empty() { None } else { send_ipc(&mdm_ipc::Command{query:Some("glass-visuals".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok()) };
            let entries: Vec<_> = snapshot.downloads.iter().filter(|d| hidden.contains(&d.id)).map(|d| {
                let detail=visuals.as_ref().and_then(|v|v["downloads"].as_array()).and_then(|items|items.iter().find(|item|item["id"].as_u64()==Some(d.id)));
                let percent=d.size.filter(|size|*size>0).map(|size|format!("{:.1}%",100.0*d.downloaded as f64/size as f64)).unwrap_or_else(||"size unknown".into());
                let eta=if d.speed>0 { d.size.map(|size| format!("{}s left",size.saturating_sub(d.downloaded)/d.speed)).unwrap_or_else(||"time unknown".into()) } else { "time unknown".into() };
                let active=detail.and_then(|v|v["active_connections"].as_u64()).map(|n|format!("{n} connections")).unwrap_or_else(||"connections unknown".into());
                let resume=match detail.and_then(|v|v["resumable"].as_bool()) {Some(true)=>"resumable",Some(false)=>"not resumable",None=>"resume unknown"};
                (d.id,format!("{} — {} · {} · {:.1} MB/s · {} · {} · {}",d.file,d.status,percent,d.speed as f64/1048576.0,eta,active,resume))
            }).collect();
            if let Some(tray) = app.tray_by_id("progress-tray") {
                let _=tray.set_show_menu_on_left_click(false);
                let tip=if entries.len()==1 {entries[0].1.chars().take(120).collect::<String>()} else {format!("Auralis — {} download windows",entries.len())};
                let _=tray.set_tooltip(Some(tip));
            }
            let membership_changed = entries.len()!=tray_items.len() || entries.iter().any(|(id,_)|!tray_items.iter().any(|(old,_)|old==id));
            if membership_changed {
                if let Some(tray) = app.tray_by_id("progress-tray") {
                    if let Ok(menu) = Menu::new(&app) {
                        let mut items=Vec::new();
                        for (id,title) in &entries {
                            if let Ok(item)=MenuItem::with_id(&app,format!("progress-{id}"),title,true,None::<&str>) {
                                if menu.append(&item).is_ok(){items.push((*id,item));}
                            }
                        }
                        if entries.is_empty() {
                            if let Ok(item)=MenuItem::with_id(&app,"progress-empty","No hidden windows",false,None::<&str>){let _=menu.append(&item);}
                        }
                        if tray.set_menu(Some(menu)).is_ok(){tray_items=items;}
                    }
                }
            } else {
                for (id,title) in &entries {
                    if let Some((_,item))=tray_items.iter().find(|(old,_)|old==id){let _=item.set_text(title);}
                }
            }
            if let Some(path)=mdm_ipc::data_dir().map(|d|d.join("glass-browser-window-request")) {
                if let Ok(target)=std::fs::read_to_string(&path) {
                    let _=std::fs::remove_file(&path);
                    if target=="main" { super::show_main(&app); }
                    else if target.starts_with("options:") { let _=open(&app,"settings","settings=1&tab=Browser%20Integration",968.0,765.0); }
                }
            }
            if !helpers_checked {
                let helpers=send_ipc(&mdm_ipc::Command{query:Some("glass-helpers".into()),..Default::default()}).ok().and_then(|s|serde_json::from_str::<serde_json::Value>(&s).ok());
                if let Some(tools)=helpers.as_ref().and_then(|v|v["tools"].as_array()) {
                    helpers_checked=true;
                    if tools.iter().any(|tool|tool["version"].is_null()) {let _=open(&app,"tool-helpers","tool=helpers",680.0,520.0);}
                }
            }

            let config = send_ipc(&mdm_ipc::Command {query:Some("glass-settings".into()),..Default::default()})
                .ok().and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
            let complete = !super::is_isolated_test() && config.as_ref().and_then(|c| c["show_complete"].as_bool()).unwrap_or(false);
            let progress = !super::is_isolated_test() && AUTO_PROGRESS.load(Ordering::Relaxed)
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
                        if let Ok(mut hidden) = owner.state::<HiddenDownloadWindows>().0.lock() { hidden.remove(&id); }
                        if let Some(w) = owner.get_webview_window(&format!("download-{id}")) { let _ = w.close(); }
                        super::refresh_tray_menu(&owner);
                        if complete { let _ = open(&owner,&format!("complete-{id}"),&format!("complete={id}"),720.0,420.0); }
                    } else if !hidden.contains(&id) {
                        let _ = open(&owner,&format!("download-{id}"),&format!("detail={id}"),760.0,560.0);
                    }
                }
                for id in new_videos {let _=open(&owner,&format!("tool-video-{id}"),&format!("tool=video&browser={id}"),720.0,560.0);}
                if exit {let _=mdm_ipc::send(&mdm_ipc::Command{exit:true,..Default::default()});owner.exit(0);return;}
                if let Some(id)=duplicate{let _=open(&owner,&format!("tool-duplicate-{id}"),&format!("tool=duplicate&lease={id}"),620.0,400.0);}
                if let Some(id)=queue{let _=open(&owner,&format!("tool-queue-{id}"),&format!("tool=queue&lease={id}"),600.0,340.0);}
                if import.is_some(){let _=open(&owner,"tool-grabber","tool=grabber",900.0,680.0);}
                if let Some(id)=power_id {let _=open(&owner,&format!("power-{id}"),&format!("power={id}"),590.0,330.0);}
                if let Some(id) = request.filter(|_| !super::is_isolated_test()) { let _ = open(&owner,&format!("info-{id}"),&format!("request={id}"),780.0,560.0); }
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
    if !matches!(action.as_str(),"category"|"queues"|"schedule"|"power"|"power-state"|"original-settings"|"original-setting"|"batch"|"grabber"|"grabber-state"|"categories"|"accounts"|"account"|"prompts"|"prompt"|"helpers"|"helpers-install"|"fork-status"|"fork-check"|"gallery") {return Err("Unsupported tool".into());}
    tauri::async_runtime::spawn_blocking(move||{
        let mut cmd=mdm_ipc::Command::default();
        if action=="queues" {cmd.query=Some("glass-queues".into());}
        else if action=="grabber-state"||action=="categories"||action=="accounts"||action=="prompts"||action=="helpers"{cmd.query=Some(format!("glass-{action}"));}
        else if action=="helpers-install" {cmd.action=Some("glass-helpers".into());cmd.queue=payload.map(|p|p.to_string());}
        else if action=="fork-status" {cmd.query=Some("glass-fork-check".into());}
        else if action=="fork-check" {cmd.action=Some("glass-fork-check".into());cmd.queue=Some(env!("CARGO_PKG_VERSION").to_owned());}
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
pub async fn list_network_adapters()->ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(|| {
        let reply=send_ipc(&mdm_ipc::Command{query:Some("glass-network-adapters".into()),..Default::default()})?;
        let value:serde_json::Value=serde_json::from_str(&reply).map_err(|e|e.to_string())?;
        if let Some(error)=value.get("error") {return Err(error.to_string())} Ok(value)
    }).await.map_err(|e|e.to_string())?
}
#[tauri::command]
pub async fn choose_setting_file(kind:String)->ApiResult<Option<String>> {
    tauri::async_runtime::spawn_blocking(move|| {
        let picker=rfd::FileDialog::new();
        let selected=match kind.as_str() {
            "cookies"=>picker.set_title("Choose a Netscape cookies file").add_filter("Text files", &["txt"]).pick_file(),
            "sound"=>picker.set_title("Choose a notification sound").add_filter("Audio files", &["wav","mp3","ogg"]).pick_file(),
            _=>return Err("Unsupported file type".into()),
        };Ok(selected.map(|p|p.to_string_lossy().into_owned()))
    }).await.map_err(|e|e.to_string())?
}
#[tauri::command]
pub async fn choose_folder()->ApiResult<Option<String>> {
    tauri::async_runtime::spawn_blocking(||Ok(rfd::FileDialog::new().set_title("Choose folder").pick_folder().map(|p|p.to_string_lossy().into_owned()))).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn open_glass_window(app:AppHandle,label:String,url:String,width:f64,height:f64)->ApiResult<()> {
    if label.is_empty()||label.len()>100||!label.chars().all(|c|c.is_ascii_alphanumeric()||c=='-'||c=='_')||!url.starts_with("/?")||url.len()>1024||url.contains(['\\',':'])||!width.is_finite()||!height.is_finite(){return Err("Invalid download window".into());}
    let (width,height)=if label=="tool-update-toast" {(width.clamp(320.0,500.0),height.clamp(120.0,240.0))} else {(width.clamp(360.0,1800.0),height.clamp(280.0,1200.0))};
    tauri::async_runtime::spawn_blocking(move||open(&app,&label,&url[2..],width,height)).await.map_err(|e|e.to_string())?
}

/// Show only the update popup without stealing the active window's focus.
#[tauri::command]
pub fn show_update_toast(window:tauri::WebviewWindow)->ApiResult<()> {
    if window.label()!="tool-update-toast" { return Err("Only the update popup can use this action".into()); }
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::WindowsAndMessaging::{SetWindowPos, HWND_TOPMOST, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_SHOWWINDOW};
        // Respect Windows' presentation/full-screen/quiet states. The persistent
        // in-app update notice remains available after the user returns.
        #[link(name="shell32")]
        unsafe extern "system" { fn SHQueryUserNotificationState(state:*mut i32)->i32; }
        let mut notification_state=0;
        // SAFETY: the pointer is valid for the duration of the synchronous call.
        let status=unsafe { SHQueryUserNotificationState(&mut notification_state) };
        if status>=0 && matches!(notification_state,1|2|3|4|6) {
            return window.close().map_err(|e|e.to_string());
        }
        let hwnd=window.hwnd().map_err(|e|e.to_string())?.0 as windows_sys::Win32::Foundation::HWND;
        // SAFETY: hwnd belongs to this live Tauri window; no size or position is changed.
        if unsafe { SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW) } == 0 {
            return Err("Could not show update popup".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    { window.show().map_err(|e|e.to_string()) }
}

#[tauri::command]
pub fn close_progress_windows(app:AppHandle,ids:Vec<u64>){
    if let Ok(mut hidden) = app.state::<HiddenDownloadWindows>().0.lock() {
        for id in &ids { hidden.remove(id); }
    }
    for id in ids { if let Some(w)=app.get_webview_window(&format!("download-{id}")) { let _=w.close(); } }
    super::refresh_tray_menu(&app);
}

#[tauri::command]
pub fn hide_download_to_tray(app:AppHandle,id:u64)->ApiResult<()> {
    let window=app.get_webview_window(&format!("download-{id}")).ok_or("Download window is no longer open")?;
    window.hide().map_err(|e|e.to_string())?;
    app.state::<HiddenDownloadWindows>().0.lock().map_err(|e|e.to_string())?.insert(id);
    super::refresh_tray_menu(&app);
    Ok(())
}
