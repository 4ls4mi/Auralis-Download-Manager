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
pub async fn drag_download(app:AppHandle, window:tauri::Window, id:u64) -> ApiResult<()> {
    let path=tauri::async_runtime::spawn_blocking(move || completed_path(id)).await.map_err(|e|e.to_string())??;
    #[cfg(windows)]
    {
        let (tx,rx)=std::sync::mpsc::channel();
        app.run_on_main_thread(move || {
            let result=drag::start_drag(&window,drag::DragItem::Files(vec![path]),
                drag::Image::Raw(include_bytes!("../icons/drag.png").to_vec()),
                |_,_|{},drag::Options::default()).map_err(|e|e.to_string());
            let _=tx.send(result);
        }).map_err(|e|e.to_string())?;
        tauri::async_runtime::spawn_blocking(move || rx.recv().map_err(|e|e.to_string())?).await.map_err(|e|e.to_string())?
    }
    #[cfg(not(windows))]
    { let _=(app,window,path); Err("Native file dragging is Windows-only".into()) }
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
        Ok(Some(v))
    }).await.map_err(|e|e.to_string())?
}
