use super::*;

/// A path is resolved by download ID in the authenticated backend, never supplied by WebView content.
fn completed_path(id:u64) -> ApiResult<PathBuf> {
    let data=request_snapshot()?;
    let file=data.downloads.iter().find(|f|f.id==id && f.status=="Complete").ok_or("Select a completed download")?;
    let path=PathBuf::from(&file.path);
    if !path.is_absolute() || !path.exists() { return Err("Downloaded file not found".into()); }
    Ok(path)
}

#[tauri::command]
pub async fn drag_download(window:tauri::Window, id:u64) -> ApiResult<()> {
    #[cfg(windows)]
    {
        let hwnd=window.hwnd().map_err(|e|e.to_string())?.0 as isize;
        let pid=std::process::id();
        tauri::async_runtime::spawn_blocking(move||{
            completed_path(id)?;
            let request=mdm_ipc::Command{action:Some("glass-drag-file".into()),ids:vec![id],queue:Some(serde_json::json!({"hwnd":hwnd,"pid":pid}).to_string()),..Default::default()};
            let reply=send_ipc(&request)?;
            let result:serde_json::Value=serde_json::from_str(&reply).map_err(|e|e.to_string())?;
            if let Some(error)=result.get("error"){return Err(error.to_string());}
            Ok(())
        }).await.map_err(|e|e.to_string())?
    }
    #[cfg(not(windows))]
    { let _=(window,id); Err("Native file dragging is Windows-only".into()) }
}

/// The original engine owns the current path and whether an unknown target took it.
#[tauri::command]
pub async fn drag_state(id:u64) -> ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(move||{
        let reply=send_ipc(&mdm_ipc::Command{query:Some("glass-move-status".into()),ids:vec![id],..Default::default()})?;
        let result:serde_json::Value=serde_json::from_str(&reply).map_err(|e|e.to_string())?;
        if let Some(error)=result.get("error"){return Err(error.to_string());}
        Ok(result)
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn choose_move(id:u64) -> ApiResult<Option<serde_json::Value>> {
    tauri::async_runtime::spawn_blocking(move || {
        let data=request_snapshot()?;
        let item=data.downloads.iter().find(|i|i.id==id).ok_or("Download not found")?;
        if item.status=="Downloading" {return Err("Stop the download before moving it".into());}
        let path=PathBuf::from(&item.path);
        let mut picker=rfd::FileDialog::new().set_title("Move/Rename").set_file_name(&item.file);
        if let Some(parent)=path.parent() {picker=picker.set_directory(parent);}
        let Some(target)=picker.save_file() else {return Ok(None);};
        if target==path {return Ok(Some(serde_json::json!({"ok":true})));}
        let s=send_ipc(&mdm_ipc::Command{action:Some("glass-item".into()),category:Some("move".into()),ids:vec![id],queue:Some(target.to_string_lossy().into_owned()),..Default::default()})?;
        let v:serde_json::Value=serde_json::from_str(&s).map_err(|e|e.to_string())?;
        if v.get("error").is_some() {return Err(v.to_string());}
        // Moving is asynchronous in MDM. Do not report success until the backend
        // has finished and updated its stored destination; a failed move leaves
        // the old path in place and must remain visible to the user.
        for _ in 0..14400 {
            let reply=send_ipc(&mdm_ipc::Command{query:Some("glass-move-status".into()),ids:vec![id],..Default::default()})?;
            let status:serde_json::Value=serde_json::from_str(&reply).map_err(|e|e.to_string())?;
            if let Some(error)=status.get("error"){return Err(error.to_string());}
            if status["moving"]==false {
                let actual=status["path"].as_str().ok_or("Could not read the moved file location")?;
                if PathBuf::from(actual)==target {return Ok(Some(serde_json::json!({"ok":true,"path":actual})));}
                return Err("The file could not be moved. Check the destination and Windows permissions.".into());
            }
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
        Err("The move is still running; check the download list for its eventual location.".into())
    }).await.map_err(|e|e.to_string())?
}

/// Read only when the user opens Add URL and has chosen clipboard prefill.
#[tauri::command]
pub async fn clipboard_text() -> ApiResult<String> {
    tauri::async_runtime::spawn_blocking(|| {
        #[cfg(windows)]
        { arboard::Clipboard::new().and_then(|mut c| c.get_text()).map_err(|e| e.to_string()) }
        #[cfg(not(windows))]
        { Err("Clipboard prefill is available on Windows".into()) }
    }).await.map_err(|e|e.to_string())?
}

/// Original MDM video quality lookup; the engine owns the token and choices.
/// Sign in inside a separate unprivileged webview. Remote pages do not receive app IPC permissions.
#[tauri::command]
pub async fn open_youtube_sign_in(app: AppHandle) -> ApiResult<()> {
    // WebView2 window construction blocks waiting for the Windows UI thread.
    // A synchronous command runs on that thread and deadlocks the whole app.
    tauri::async_runtime::spawn_blocking(move || {
        if let Some(window)=app.get_webview_window("youtube-login") {
            window.show().map_err(|e|e.to_string())?;
            let _=window.unminimize();let _=window.set_focus();return Ok(());
        }
        let url=tauri::Url::parse("https://www.youtube.com/").map_err(|e|e.to_string())?;
        tauri::WebviewWindowBuilder::new(&app,"youtube-login",tauri::WebviewUrl::External(url))
            .title("YouTube sign-in — Auralis").inner_size(1000.0,720.0).center().build()
            .map_err(|e|format!("Could not open YouTube sign-in: {e}"))?;
        Ok(())
    }).await.map_err(|e|format!("Could not start the YouTube sign-in window: {e}"))?
}
fn youtube_session_cookies(app:&AppHandle) -> ApiResult<Vec<mdm_ipc::BrowserCookie>> {
    let window=app.get_webview_window("youtube-login").ok_or("Open YouTube sign-in and sign in first. Keep that window open while looking up the video.")?;
    let mut result=Vec::new();let mut seen=std::collections::HashSet::new();
    for address in ["https://www.youtube.com/","https://www.google.com/","https://accounts.google.com/"] {
        let url=tauri::Url::parse(address).map_err(|e|e.to_string())?;
        let host=url.host_str().unwrap_or("").to_owned();
        for cookie in window.cookies_for_url(url).map_err(|e|format!("Could not read the in-app sign-in session: {e}"))? {
            let domain=cookie.domain().unwrap_or(&host).to_owned();let path=cookie.path().unwrap_or("/").to_owned();
            if !seen.insert((domain.clone(),path.clone(),cookie.name().to_owned())) {continue;}
            result.push(mdm_ipc::BrowserCookie{name:cookie.name().to_owned(),value:cookie.value().to_owned(),host_only:cookie.domain().is_none(),domain,path,secure:cookie.secure().unwrap_or(false),expires:None});
        }
    }
    if !result.iter().any(|c|matches!(c.name.as_str(),"SID"|"SAPISID"|"__Secure-3PSID"|"LOGIN_INFO")) {
        return Err("No YouTube sign-in cookies were found. Sign in in the Auralis YouTube window, then try again. If Google blocks embedded sign-in, use the extension in your regular browser or manually supplied cookies.".into());
    }
    Ok(result)
}

#[tauri::command]
pub async fn video_tool(app:AppHandle,action:String,value:String,choice:Option<usize>,subs:Option<serde_json::Value>,cookies:Option<String>,cookie_browser:Option<String>,app_session:Option<bool>) -> ApiResult<serde_json::Value> {
    if value.len()>8192 {return Err("Video request is too long".into());}
    let mut command=mdm_ipc::Command::default();
    if app_session.unwrap_or(false) {
        let page=tauri::Url::parse(&value).map_err(|_|"Enter a YouTube video URL")?;
        let host=page.host_str().unwrap_or("").to_ascii_lowercase();
        if action!="lookup"||page.scheme()!="https"||!(host=="youtube.com"||host.ends_with(".youtube.com")||host=="youtu.be") {return Err("The in-app YouTube session can only be used for a YouTube video lookup".into());}
        let session_app=app.clone();
        command.cookie_jar=tauri::async_runtime::spawn_blocking(move || youtube_session_cookies(&session_app))
            .await.map_err(|e|format!("Could not read the YouTube session: {e}"))??;
        command.video_explicit_cookies=true;
    }
    if let Some(browser) = cookie_browser.filter(|b| !b.is_empty()) {
        if action != "lookup" || !matches!(browser.as_str(), "edge"|"chrome"|"firefox"|"brave"|"chromium"|"opera"|"vivaldi") { return Err("Choose a supported browser".into()); }
        command.video_cookie_browser=Some(browser);
        command.video_explicit_cookies=true;
    }
    if let Some(cookies) = cookies.filter(|c| !c.trim().is_empty()) {
        if action != "lookup" || cookies.len() > 8192 || !cookies.contains('=') || cookies.contains(['\r','\n','\0']) { return Err("Enter cookies as name=value pairs separated by semicolons".into()); }
        command.cookies=Some(cookies);
        command.video_explicit_cookies=true;
    }
    match action.as_str() {
        "lookup" if value.starts_with("https://")||value.starts_with("http://") => command.video_lookup=Some(mdm_ipc::VideoLookup{address:value,..Default::default()}),
        "tracks" if !value.is_empty()&&value.len()<=256 => {command.query=Some("glass-video-tracks".into());command.queue=Some(value)},
        "poll" if !value.is_empty()&&value.len()<=256 => command.video_poll=Some(value),
        "pick" if !value.is_empty()&&value.len()<=256&&choice.is_some_and(|n|n<1000) => {command.video_pick=Some(mdm_ipc::VideoPick{token:value,choice:choice.unwrap_or_default(),..Default::default()});if let Some(subs)=subs {command.category=Some("glass-subtitles".into());command.queue=Some(subs.to_string());}},
        _=>return Err("Enter a valid video page address".into()),
    }
    tauri::async_runtime::spawn_blocking(move||{
        let response=send_ipc(&command)?;
        serde_json::from_str(&response).map_err(|_|"Could not read the video lookup result".into())
    }).await.map_err(|e|e.to_string())?
}

#[tauri::command]
pub async fn browser_video(id:u64, choice:Option<usize>,subs:Option<serde_json::Value>) -> ApiResult<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(move||{
        let command=if let Some(choice)=choice {mdm_ipc::Command{action:Some("glass-video".into()),ids:vec![id],queue:Some(serde_json::json!({"choice":choice,"subs":subs}).to_string()),..Default::default()}} else {mdm_ipc::Command{query:Some("glass-video".into()),ids:vec![id],..Default::default()}};
        let response=send_ipc(&command)?;
        serde_json::from_str(&response).map_err(|_|"Could not read the video request".into())
    }).await.map_err(|e|e.to_string())?
}
