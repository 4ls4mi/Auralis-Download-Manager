//! Authenticated, local-only adapter to the original MDM actions and file-info queue.
//! Browser cookies/credentials remain in FileInfo.context and are never sent to a WebView.
mod settings;
mod tools;
mod accounts;
mod prompts;
mod full_backup;
pub(super) use full_backup::FullBackup;
use super::*;
use serde_json::{Value, json};

pub(super) type CheckSlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<Option<Result<bool,String>>>>>;
pub(super) type RecoverySlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<Option<Result<Value,String>>>>>;
#[derive(serde::Serialize)]
pub(super) struct BrowserDownloadNotice {
    id: u64,
    browser: String,
    name: String,
}

#[derive(Default)]
pub(super) struct RepairSlot { pub result: Option<Result<Value,String>>, pub applied: bool }
pub(super) type RepairSlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<RepairSlot>>>;
pub(super) type TorrentRecoverySlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<Option<Result<mdm_torrent::candidate_search::SearchReport,String>>>>>;
#[derive(Default)]
pub(super) struct HandoffSlot {
    pub prepared: Option<Result<mdm_torrent::PreparedRecovery,String>>,
    pub result: Option<Result<Value,String>>,
    pub cancelled: bool,
    pub automatic: bool,
}
pub(super) type HandoffSlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<HandoffSlot>>>;

impl App {
    pub(super) fn glass_owned(&self) -> bool {
        self.headless && crate::headless::glass_owned()
    }

    fn glass_next_info(&mut self) {
        if self.file_info.is_some() { return; }
        let ctx = self.ui_ctx.clone();
        if let Some((new, context)) = self.file_info_waiting.pop_front() {
            self.open_file_info(new, context, &ctx);
        } else if let Some(add) = self.glass_video_waiting.pop_front() {
            let new=dialogs::NewUrl { url:add.page.clone(), login:None };
            self.open_file_info(new, add.context.clone(), &ctx);
            if let Some(fi)=self.file_info.as_mut() {
                fi.set_category(add.category);
                fi.glass_destination(add.dest.to_string_lossy().into_owned());
            }
            self.glass_active_video=Some(add);
        }
    }

    pub(super) fn glass_answer(&mut self, cmd: &ipc::Command) -> Option<String> {
        if cmd.action.as_deref() == Some("glass-browser-download") {
            if cmd.private {
                return Some(json!({"ok":true}).to_string());
            }
            let payload = cmd.queue.as_deref().filter(|body| body.len() <= 8192)
                .and_then(|body| serde_json::from_str::<serde_json::Map<String, Value>>(body).ok());
            let Some(payload) = payload else {
                return Some(json!({"error":"Invalid browser download notice"}).to_string());
            };
            let text = |field: &str, limit: usize| {
                payload.get(field).and_then(Value::as_str).unwrap_or_default().trim().chars()
                    .filter(|ch| !ch.is_control()).take(limit).collect::<String>()
            };
            let id = self.glass_browser_download.as_ref().map_or(1, |notice| notice.id + 1);
            self.glass_browser_download = Some(BrowserDownloadNotice {
                id,
                browser: text("browser", 64),
                name: text("name", 200),
            });
            return Some(json!({"ok":true}).to_string());
        }
        if let Some(answer)=self.glass_prompts(cmd){return Some(answer);}
        if let Some(answer)=self.glass_accounts(cmd){return Some(answer);}
        if let Some(answer)=self.glass_tools(cmd){return Some(answer);}
        if cmd.action.as_deref()==Some("glass-recovery-torrent-file") {
            let Some(id)=cmd.ids.first().copied() else {return Some(json!({"error":"Missing download"}).to_string());};
            if !cmd.silent { self.auto_recovery_pending.remove(&id); self.auto_recovery_searches.remove(&id); }
            let Some(item)=self.items.iter().find(|i|i.id==id) else {return Some(json!({"error":"Download not found"}).to_string());};
            if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.video.is_some() || item.gallery.is_some() || item.remote.is_some() {
                return Some(json!({"error":"Stop an incomplete ordinary download before checking a torrent"}).to_string());
            }
            if self.recovery_check_running(id) || self.repair_check_running(id) || self.glass_torrent_recovery.values().any(|slot|slot.lock().map_or(true,|result|result.is_none())) {
                return Some(json!({"error":"Wait for the other saved-data operation to finish"}).to_string());
            }
            let Some(path)=cmd.dir.as_deref().map(PathBuf::from) else {return Some(json!({"error":"Choose a torrent file"}).to_string());};
            let dest=item.dest.clone();
            let state_path=mdm_engine::state::state_path(&dest);
            if !state_path.exists() {return Some(json!({"error":"No saved download state is available for this file"}).to_string());}
            let slot=std::sync::Arc::new(std::sync::Mutex::new(None));
            self.glass_torrent_recovery.remove(&id);
            self.glass_torrent_handoffs.remove(&id);
            self.glass_torrent_recovery.insert(id,slot.clone());
            let wake=self.ui_ctx.clone();
            std::thread::spawn(move || {
                let answer=(|| -> Result<mdm_torrent::candidate_search::SearchReport,String> {
                    let saved=mdm_engine::state::ResumeState::load(&state_path)?;
                    if saved.dest!=dest {return Err("Saved state does not belong to this file".into());}
                    let torrent=mdm_torrent::read_file(&path).map_err(|e|e.to_string())?;
                    let files=mdm_torrent::candidate_search::matching_files(&torrent,&saved)?;
                    let mut report=mdm_torrent::candidate_search::SearchReport{searched:1,..Default::default()};
                    if !files.is_empty() {
                        let info_hash=mdm_torrent::metadata_from_bytes(&torrent).map_err(|e|e.to_string())?.info_hash;
                        report.matches.push(mdm_torrent::candidate_search::MatchedCandidate {
                            candidate:mdm_torrent::candidate_search::Candidate{identifier:String::new(),title:"Chosen torrent file".into(),torrent_url:url::Url::parse("about:blank").expect("fixed URL")},info_hash,torrent,files
                        });
                    }
                    Ok(report)
                })();
                if let Ok(mut result)=slot.lock(){*result=Some(answer);}
                wake.request_repaint();
            });
            return Some(json!({"ok":true,"pending":true}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-backup-settings") {
            let mut value=match serde_json::to_value(&self.settings) { Ok(v)=>v, Err(e)=>return Some(json!({"error":e.to_string()}).to_string()) };
            if let Some(map)=value.as_object_mut() { for key in ["proxy_pass","site_logins","debrid_accounts"] { map.remove(key); } }
            return Some(json!({"settings":value}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-restore-settings") {
            let incoming=serde_json::from_str::<Value>(cmd.queue.as_deref().unwrap_or(""));
            let Ok(mut value)=incoming else {return Some(json!({"error":"Invalid backup settings"}).to_string())};
            let Ok(current)=serde_json::to_value(&self.settings) else {return Some(json!({"error":"Could not read current settings"}).to_string())};
            let Some(map)=value.as_object_mut() else {return Some(json!({"error":"Invalid backup settings"}).to_string())};
            if !map.get("max_connections").and_then(Value::as_u64).is_some_and(|n|(1..=128).contains(&n)) || !map.get("show_complete").is_some_and(Value::is_boolean) {return Some(json!({"error":"Backup is missing valid download preferences"}).to_string())}
            for key in ["proxy_pass","site_logins","debrid_accounts","launch_on_startup"] {if let Some(v)=current.get(key){map.insert(key.into(),v.clone());}}
            map.insert("remote_on".into(),json!(false)); map.insert("automation_api".into(),json!(true));
            let next=match serde_json::from_value::<crate::settings::Settings>(value) {Ok(v)=>v,Err(e)=>return Some(json!({"error":format!("Invalid backup settings: {e}")}).to_string())};
            self.apply_options(next);
            return Some(json!({"ok":true}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-original-settings"){return Some(self.glass_original_settings().to_string());}
        if cmd.query.as_deref() == Some("glass-clipboard-mode") {
            return Some(json!({"mode": self.glass_clipboard_mode()}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-original-setting"){
            let payload=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
            return Some(self.glass_update_original(payload).to_string());
        }
        if cmd.query.as_deref() == Some("glass-video-tracks") {
            let tracks=cmd.queue.as_deref().and_then(|token|self.lookups.glass_tracks(token,Instant::now()));
            return Some(tracks.unwrap_or_else(||json!({"error":"Video lookup is not ready"})).to_string());
        }
        if cmd.query.as_deref() == Some("glass-videos") {
            return Some(json!({"ids":self.glass_videos.keys().copied().collect::<Vec<_>>()}).to_string());
        }
        if cmd.query.as_deref() == Some("glass-video") {
            return Some(match cmd.ids.first().and_then(|id|self.glass_videos.get(id)) {
                Some((url,answer,_)) => json!({"url":url,"result":answer}),
                None => json!({"error":"Video request expired"})
            }.to_string());
        }
        if cmd.action.as_deref() == Some("glass-video") {
            let Some(id)=cmd.ids.first().copied() else {return Some(json!({"error":"Missing video request"}).to_string());};
            if cmd.category.as_deref()==Some("close") {self.glass_videos.remove(&id);return Some(json!({"ok":true}).to_string());}
            let Some((_,answer,private))=self.glass_videos.get(&id) else{return Some(json!({"error":"Video request expired"}).to_string());};
            let Some(token)=answer.token.clone() else{return Some(json!({"error":"Video lookup has no token"}).to_string());};
            let private=*private;
            let payload:Value=cmd.queue.as_deref().and_then(|s|serde_json::from_str(s).ok()).unwrap_or(Value::Null);
            let Some(choice)=payload["choice"].as_u64().and_then(|n|usize::try_from(n).ok()).or_else(||cmd.queue.as_deref().and_then(|s|s.parse().ok())).filter(|n|*n<1000) else{return Some(json!({"error":"Invalid quality"}).to_string());};
            return Some(ipc::api::line(&self.quality_menu(&ipc::Command{private,category:payload.get("subs").map(|_|"glass-subtitles".into()),queue:payload.get("subs").map(Value::to_string),video_pick:Some(ipc::VideoPick{token,choice,store_id:None}),..Default::default()})));
        }
        if cmd.query.as_deref() == Some("glass-file-info") {
            self.glass_next_info();
            let serial = self.glass_info_serial;
            let mut info=self.file_info.as_mut().map(FileInfo::glass_view);
            if let (Some(view),Some(video))=(&mut info,&self.glass_active_video) {
                view["size"]=json!(video.size);view["probing"]=json!(false);view["error"]=Value::Null;view["video"]=json!(true);
            }
            return Some(json!({"id": serial, "info": info,
                "categories":Category::all().into_iter().map(|c|json!({"key":c.key(),"name":c.shown()})).collect::<Vec<_>>(), "waiting": self.file_info_waiting.len()+self.glass_video_waiting.len()}).to_string());
        }
        if cmd.query.as_deref() == Some("glass-completion-details") {
            let Some(item) = cmd.ids.first().and_then(|id| {
                self.items.iter().find(|item| item.id == *id && item.status == Status::Complete)
            }) else {
                return Some(json!({"error": "Completed download not found"}).to_string());
            };
            return Some(json!({
                "url": item.file_address().as_str(),
                "path": item.dest.to_string_lossy(),
                "downloaded_exact": item.downloaded.to_string(),
                "moved_away": item.moved_away,
                "moving": self.moving.iter().any(|(id, _, _)| *id == item.id),
                "notices": item.notices,
            }).to_string());
        }
        if cmd.query.as_deref()==Some("glass-move-status") {
            let Some(id)=cmd.ids.first().copied() else {return Some(json!({"error":"Choose a download"}).to_string());};
            let Some(item)=self.items.iter().find(|item|item.id==id) else {return Some(json!({"error":"Download not found"}).to_string());};
            let moving=self.moving.iter().any(|(item_id,_,_)|*item_id==id);
            return Some(json!({"moving":moving,"path":item.dest.to_string_lossy(),"moved_away":item.moved_away}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-drag-file") {
            #[cfg(windows)]
            {
                let Some(id)=cmd.ids.first().copied() else{return Some(json!({"error":"Choose a download"}).to_string());};
                let Some(item)=self.items.iter().find(|item|item.id==id && item.status==Status::Complete) else{return Some(json!({"error":"Select a completed download"}).to_string());};
                if item.moved_away || self.moving.iter().any(|(moving_id, _, _)| *moving_id == id) {
                    return Some(json!({"error": "The downloaded file is being moved or is no longer at its saved location"}).to_string());
                }
                let payload:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
                let Some(hwnd)=payload["hwnd"].as_i64().and_then(|n|isize::try_from(n).ok()) else{return Some(json!({"error":"Invalid window"}).to_string());};
                let Some(pid)=payload["pid"].as_u64().and_then(|n|u32::try_from(n).ok()) else{return Some(json!({"error":"Invalid window"}).to_string());};
                let from=item.dest.clone();let tracked=from.clone();let wake=self.ui_ctx.clone();
                let result=crate::win32::drag_file_out_from_glass(hwnd,pid,&from,move |out|{crate::dialogs::record_dragged_out(id,tracked,out);wake.request_repaint();});
                return Some(match result{Ok(())=>json!({"ok":true}),Err(error)=>json!({"error":error})}.to_string());
            }
            #[cfg(not(windows))]
            return Some(json!({"error":"File dragging is available on Windows"}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-power") {
            return Some(json!({"id":self.glass_power_serial,"pending":self.turn_off.as_ref().map(dialogs::TurnOffCountdown::glass_view),"exit":self.glass_exit_requested}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-power") {
            let payload:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
            if payload["id"].as_u64()!=Some(self.glass_power_serial) {return Some(json!({"error":"This completion action is no longer pending"}).to_string());}
            let Some(countdown)=self.turn_off.take() else {return Some(json!({"ok":true}).to_string());};
            if payload["action"].as_str()==Some("execute"){countdown.execute();}
            return Some(json!({"ok":true}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-schedule") {
            let payload:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
            let name=payload["name"].as_str().unwrap_or("");
            let schedule=serde_json::from_value::<crate::queue::Schedule>(payload["schedule"].clone());
            let valid_time=|t:Option<(u8,u8,u8)>|t.is_none_or(|(h,m,s)|h<24&&m<60&&s<60);
            let Ok(schedule)=schedule else {return Some(json!({"error":"Invalid schedule"}).to_string());};
            if !valid_time(schedule.start_at)||!valid_time(schedule.stop_at)||schedule.once.is_some_and(|(y,m,d)|chrono::NaiveDate::from_ymd_opt(y,m,d).is_none()){
                return Some(json!({"error":"Choose valid dates and times"}).to_string());
            }
            let Some(q)=self.queues.iter_mut().find(|q|q.name==name) else {return Some(json!({"error":"Queue not found"}).to_string());};
            let Some(count)=payload["files_at_once"].as_u64().filter(|c|(1..=128).contains(c))else{return Some(json!({"error":"Choose 1–128 simultaneous downloads"}).to_string());};
            q.schedule=schedule;q.files_at_once=count as u32;
            self.dirty=true;
            return Some(json!({"ok":true}).to_string());
        }
        if cmd.query.as_deref() == Some("glass-queues") {
            return Some(json!({"queues":self.queues}).to_string());
        }
        let action = cmd.action.as_deref()?;
        if action == "glass-file-info" {
            let fail = |s: &str| json!({"error": s}).to_string();
            if cmd.ids.as_slice() != [self.glass_info_serial] || self.file_info.is_none() {
                return Some(fail("This download request is no longer pending"));
            }
            if cmd.category.as_deref() == Some("cancel") {
                self.file_info.take();
                self.glass_active_video.take();
                self.glass_next_info();
                return Some(json!({"ok":true}).to_string());
            }
            let payload: Value = match serde_json::from_str(cmd.queue.as_deref().unwrap_or("")) {
                Ok(p) => p, Err(_) => return Some(fail("Invalid file information")),
            };
            if cmd.category.as_deref() == Some("category") {
                let category = payload["category"].as_str().and_then(|key| Category::all().into_iter().find(|c| c.key() == key));
                if let (Some(cat), Some(fi)) = (category, self.file_info.as_mut()) {
                    fi.set_category(cat);
                    return Some(json!({"ok":true}).to_string());
                }
                return Some(fail("Unknown category"));
            }
            let Some(path) = payload["save_as"].as_str().filter(|s| !s.trim().is_empty() && s.len() <= 32760) else {
                return Some(fail("Choose a valid destination filename"));
            };
            let path = dialogs::resolve_path(path);
            if !path.is_absolute() || path.file_name().is_none() {
                return Some(fail("Choose an absolute destination filename"));
            }
            if let Some(parent) = path.parent()
                && let Err(e) = std::fs::create_dir_all(parent)
            { return Some(fail(&e.to_string())); }
            let mut fi = self.file_info.take().expect("pending checked above");
            fi.glass_refresh();
            fi.glass_destination(path.to_string_lossy().into_owned());
            fi.description = payload["description"].as_str().unwrap_or("").chars().take(4096).collect();
            fi.remember = payload["remember"].as_bool().unwrap_or(false);
            let count = payload["chunks"].as_u64().filter(|n| (1..=128).contains(n)).map(|n| n as u32);
            // Add through the ORIGINAL add path: category folders, request context,
            // authenticated probes, queue semantics, safe filenames and resume stay intact.
            let later = payload["later"].as_bool().unwrap_or(false);
            fi.context.connections = count;
            let id = self.next_id;
            if let Some(mut video)=self.glass_active_video.take() {
                if let Some((category,dir))=fi.remembered() {
                    self.settings.keep_category_dir(category,std::path::Path::new(&dir),&self.downloads);
                }
                video.dest=path;video.category=fi.category;video.context.connections=count;
                video.start_now=!later;video.named=true;
                self.add_video_checked(video, true);
                if let Some(item)=self.item(id) { item.description=fi.description.clone(); }
            } else {
                self.add(&mut fi, if later { Start::Later } else { Start::Now });
            }
            self.glass_next_info();
            let created=self.items.iter().any(|item|item.id==id);
            return Some(json!({"ok":true,"id":if created {Some(id)} else {None}}).to_string());
        }
        if action != "glass-item" { return None; }
        let id = *cmd.ids.first()?;
        let operation = cmd.category.as_deref()?;
        let value = cmd.queue.as_deref().unwrap_or("");
        let fail = |s: &str| Some(json!({"error":s}).to_string());
        if !self.items.iter().any(|i| i.id == id) { return fail("Download not found"); }
        match operation {
            "completion-options" => {
                let payload:Value=match serde_json::from_str(value){Ok(v)=>v,Err(_)=>return fail("Invalid completion options")};
                if !payload["turn_off"].is_null() && !matches!(payload["turn_off"].as_str(),Some("ShutDown"|"Sleep"|"Hibernate")){return fail("Invalid power action");}
                if !self.progress.iter().any(|p|p.id==id){self.progress.push(Progress::new(id,self.settings.show_complete));}
                if let Some(progress)=self.progress.iter_mut().find(|p|p.id==id){progress.glass_set_completion(&payload,self.settings.show_complete);}
            }
            "move" => {
                if self.moving.iter().any(|(moving_id, _, _)| *moving_id == id) {
                    return fail("This download is already being moved");
                }
                let target = dialogs::resolve_path(value);
                if !target.is_absolute() || target.file_name().is_none() || target.exists() {
                    return fail("Choose a new, unused destination filename");
                }
                if !self.items.iter().find(|i| i.id == id).is_some_and(can_move) {
                    return fail("This download cannot be moved while it is running or partially downloaded");
                }
                self.start_move(id, target);
            }
            "queue-add" => {
                let Some(q) = self.queues.iter().position(|q| q.name == value) else { return fail("Queue not found"); };
                self.selection.set(id);
                self.run(Cmd::AddToQueue(q), Some(id), &self.ui_ctx.clone());
            }
            "queue-remove" => {
                self.selection.set(id);
                self.run(Cmd::RemoveFromQueue, Some(id), &self.ui_ctx.clone());
            }
            "open-with" => {
                let item = self.items.iter().find(|i| i.id == id).unwrap();
                if item.status != Status::Complete { return fail("Download is not complete"); }
                dialogs::open_download_with(&item.dest, item.moved_away);
            }
            "refresh-address" => {
                let Some(url) = url::Url::parse(value).ok().filter(mdm_engine::supported) else { return fail("Enter a supported download URL"); };
                let item = self.items.iter().find(|i| i.id == id).unwrap();
                if item.live.is_some() || item.status == Status::Complete { return fail("Stop this download before updating its address"); }
                self.apply_properties(crate::properties::Changes { id, description:item.description.clone(),
                    referer:item.referer.clone(), login:item.login.clone(), address:Some(url), move_to:None, direct:None });
            }
            "extract" => {
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.status!=Status::Complete||!crate::extractq::archive_name(&item.file_name) {return fail("Select a completed archive");}
                self.extracts.offer(item,&self.items,&self.settings,true);
            }
            "extract-password" => { if !self.extracts.ask.as_ref().is_some_and(|a|a.glass_has(id)){return fail("No password request for this archive");} self.extracts.answer(Some(value.to_owned())); }
            "extract-cancel" => { self.extracts.answer(None); }
            "extract-status" => {
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                return Some(json!({"running":self.extracts.extracting(id),"password_required":self.extracts.ask.as_ref().is_some_and(|a|a.glass_has(id)),"needs_7zip":self.extracts.needs_7zip.is_some(),"message":item.log.last().map(|(_,text)|text)}).to_string());
            }
            "check-saved-result" => {
                let result=self.glass_recovery_checks.get(&id).and_then(|slot|slot.lock().ok().and_then(|v|v.clone()));
                return Some(match result {Some(Ok(report))=>json!({"complete":true,"report":report}),Some(Err(error))=>json!({"complete":true,"failure":error}),None=>json!({"complete":false})}.to_string());
            }
            "check-saved" => {
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.video.is_some() || item.gallery.is_some() {
                    return fail("Stop an incomplete ordinary download before checking its saved data");
                }
                if self.recovery_check_running(id) || self.repair_check_running(id) { return fail("A saved-data operation is already running"); }
                let dest=item.dest.clone();
                let state_path=mdm_engine::state::state_path(&dest);
                if !state_path.exists() { return fail("No saved download state is available for this file"); }
                let slot=std::sync::Arc::new(std::sync::Mutex::new(None));
                self.glass_recovery_checks.insert(id,slot.clone());
                let wake=self.ui_ctx.clone();
                std::thread::spawn(move || {
                    let answer=(|| -> Result<Value,String> {
                        let saved=mdm_engine::state::ResumeState::load(&state_path)?;
                        if saved.dest != dest {return Err("Saved state does not belong to this file".into());}
                        let report=saved.verify_saved_blocks().map_err(|e|e.to_string())?;
                        Ok(json!({"checked_bytes":report.checked_bytes,"unhashed_bytes":report.unhashed_bytes,"damaged_ranges":report.damaged_ranges,"repair_prepared":saved.repair_strict && saved.repair_source.as_ref()==Some(&saved.final_url)}))
                    })();
                    if let Ok(mut result)=slot.lock() {*result=Some(answer);}
                    wake.request_repaint();
                });
                return Some(json!({"ok":true,"pending":true}).to_string());
            }
            "repair-saved-result" => {
                let result=self.glass_repair_checks.get(&id).and_then(|slot|slot.lock().ok().and_then(|s|s.applied.then(||s.result.clone()).flatten()));
                return Some(match result {Some(Ok(report))=>json!({"complete":true,"report":report}),Some(Err(error))=>json!({"complete":true,"failure":error}),None=>json!({"complete":false})}.to_string());
            }
            "find-recovery-torrents-result" => {
                let slot=self.glass_torrent_recovery.get(&id);
                return Some(match slot.and_then(|slot|slot.lock().ok()) {
                    Some(result) => match result.as_ref() {
                        Some(Ok(report)) => json!({"complete":true,"searched":report.searched,"failed":report.failed,"matches":report.matches.iter().enumerate().flat_map(|(candidate_index,candidate)|candidate.files.iter().map(move |file|json!({"candidate":candidate_index,"file_index":file.file_index,"info_hash":candidate.info_hash,"title":candidate.candidate.title,"path":file.path.to_string_lossy(),"matching_pieces":file.evidence.matching.len(),"unavailable_pieces":file.evidence.unavailable.len()}))).collect::<Vec<_>>()}),
                        Some(Err(error))=>json!({"complete":true,"failure":error}),
                        None=>json!({"complete":false})
                    },
                    None=>json!({"complete":true,"failure":"No torrent search is available"})
                }.to_string());
            }
            "start-recovery-torrent-result" => {
                let result=self.glass_torrent_handoffs.get(&id).and_then(|slot|slot.lock().ok().and_then(|value|value.result.clone()));
                return Some(match result { Some(Ok(report))=>json!({"complete":true,"report":report}),Some(Err(error))=>json!({"complete":true,"failure":error}),None=>json!({"complete":false}) }.to_string());
            }
            "cancel-recovery-torrent" => {
                // Cancelling while candidate lookup is still running must also
                // prevent the automatic handoff when the result arrives later.
                self.auto_recovery_pending.remove(&id);
                let Some(slot)=self.glass_torrent_handoffs.get(&id) else {return Some(json!({"ok":true,"already_started":false}).to_string())};
                let Ok(mut value)=slot.lock() else {return fail("Could not cancel torrent recovery")};
                let already_started=value.result.as_ref().is_some_and(Result::is_ok);
                if value.result.is_none(){value.cancelled=true;}
                drop(value);
                if already_started {
                    self.stop_by_hand(id);
                    self.quota.held.retain(|held|*held!=id);
                    self.limit_restarts.retain(|held|*held!=id);
                    if let Some(item)=self.items.iter_mut().find(|item|item.id==id) {
                        if item.live.is_none() && item.status==Status::Queued {item.status=Status::Stopped;}
                    }
                    self.dirty=true;
                }
                return Some(json!({"ok":true,"already_started":already_started}).to_string());
            }
            "start-recovery-torrent" => {
                if !cmd.silent { self.auto_recovery_pending.remove(&id); }
                let selection:Value=match serde_json::from_str(value){Ok(v)=>v,Err(_)=>return fail("Choose a matching torrent file")};
                if selection["accept_partial_match"]!=true {return fail("Confirm that matching saved pieces do not verify the rest of the file");}
                let Some(candidate_index)=selection["candidate"].as_u64().and_then(|n|usize::try_from(n).ok()) else{return fail("Choose a matching torrent file")};
                let Some(file_index)=selection["file_index"].as_u64().and_then(|n|usize::try_from(n).ok()) else{return fail("Choose a matching torrent file")};
                let Some(info_hash)=selection["info_hash"].as_str().filter(|s|s.len()==40&&s.bytes().all(|b|b.is_ascii_hexdigit())) else{return fail("The selected torrent identity is invalid")};
                if self.torrent_hashes().contains(info_hash) || self.torrent_host.get().is_some_and(|session|session.has(info_hash)) {return fail("This torrent is already active or listed")}
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.direct_recovery.is_some() || item.video.is_some() || item.gallery.is_some() || item.remote.is_some() || item.context.private || self.moving.iter().any(|(moving,_,_)|*moving==id) || self.renaming.iter().any(|(renaming,_)|*renaming==id) {
                    return fail("Stop a non-private ordinary download before starting torrent recovery");
                }
                if item.checksum.is_some() {return fail("Torrent recovery cannot yet verify this download's expected whole-file checksum");}
                if self.recovery_check_running(id) || self.repair_check_running(id) {return fail("A saved-data operation is already running");}
                let Some(torrent)=self.glass_torrent_recovery.get(&id).and_then(|slot|slot.lock().ok().and_then(|result|result.as_ref().and_then(|r|r.as_ref().ok()).and_then(|report|report.matches.get(candidate_index)).and_then(|candidate|(candidate.info_hash==info_hash&&candidate.files.iter().any(|file|file.file_index==file_index)).then(||candidate.torrent.clone())))) else {return fail("The matching torrent is no longer available; check it again");};
                let expected_hash=info_hash.to_owned();
                let dest=item.dest.clone();
                let source=item.url.clone();
                let automatic=cmd.silent;
                let state_path=mdm_engine::state::state_path(&dest);
                let Some(parent)=dest.parent().map(PathBuf::from) else{return fail("The download has no recovery folder")};
                let host=self.torrent_host.clone();
                let known=self.session_hashes();
                let slot=std::sync::Arc::new(std::sync::Mutex::new(HandoffSlot { automatic, ..Default::default() }));
                self.glass_torrent_handoffs.insert(id,slot.clone());
                let wake=self.ui_ctx.clone();
                self.rt.spawn(async move {
                    // Initialize the session with the currently known list
                    // before adding this hash. This clears stale persisted
                    // torrents rather than resuming one at an unrelated folder.
                    let answer=match host.session(known).await {
                      Err(error)=>Err(error),
                      Ok(session) if session.has(&expected_hash)=>Err("This torrent is already active or listed; the original partial was kept".into()),
                      Ok(_) if slot.lock().map_or(true,|value|value.cancelled)=>Err("Torrent recovery was cancelled; the original partial was kept".into()),
                      Ok(_)=>tokio::task::spawn_blocking(move || -> Result<mdm_torrent::PreparedRecovery,String> {
                        let saved=mdm_engine::state::ResumeState::load(&state_path)?;
                        if saved.dest!=dest || saved.url!=source {return Err("Saved state does not belong to this file".into());}
                        let stamp=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e|e.to_string())?.as_millis();
                        let folder=(0..100).map(|n|parent.join(format!(".auralis-recovery-{id}-{stamp}-{n}"))).find(|path|!path.exists()).ok_or("Cannot choose a recovery folder")?;
                        let prepared=mdm_torrent::prepare_saved_recovery(&torrent,&saved,file_index,&folder).map_err(|e|e.to_string())?;
                        if prepared.metadata.info_hash!=expected_hash {return Err(format!("The selected torrent changed; the original partial was kept. Prepared files remain at {}.",folder.display()));}
                        if automatic && prepared.staged.evidence.matching.len()<2 {
                            return Err(format!("Automatic recovery needs two matching pieces at handoff. The original partial was kept. Prepared files remain at {}.",folder.display()));
                        }
                        Ok(prepared)
                      }).await.map_err(|_|"Torrent preparation task failed".to_owned()).and_then(|result|result),
                    };
                    if let Ok(mut value)=slot.lock(){value.prepared=Some(answer);}
                    wake.request_repaint();
                });
                return Some(json!({"ok":true,"pending":true}).to_string());
            }
            "check-recovery-magnet" | "check-recovery-torrent-url" => {
                enum MetadataSource {
                    Magnet(mdm_torrent::Source),
                    Url(url::Url),
                }
                let source = if operation=="check-recovery-magnet" {
                    if value.len()>8192 {return fail("Magnet link is too long");}
                    let Some(source)=mdm_torrent::Source::magnet(value) else {return fail("Enter a valid magnet link");};
                    MetadataSource::Magnet(source)
                } else {
                    match mdm_torrent::manual_recovery_source::parse(value) {
                        Ok(url)=>MetadataSource::Url(url),
                        Err(error)=>return fail(&error),
                    }
                };
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.video.is_some() || item.gallery.is_some() || item.remote.is_some() || item.context.private {
                    return fail("Stop an incomplete, non-private ordinary download before checking a torrent link");
                }
                if self.recovery_check_running(id) || self.repair_check_running(id) || self.glass_torrent_recovery.values().any(|slot|slot.lock().map_or(true,|result|result.is_none())) {
                    return fail("Wait for the other saved-data operation to finish");
                }
                let dest=item.dest.clone();
                let state_path=mdm_engine::state::state_path(&dest);
                if !state_path.exists() {return fail("No saved download state is available for this file");}
                self.auto_recovery_pending.remove(&id);
                self.auto_recovery_searches.remove(&id);
                let host=self.torrent_host.clone();
                let known=self.session_hashes();
                let dns=self.settings.dns();
                let route=self.route.clone();
                let slot=std::sync::Arc::new(std::sync::Mutex::new(None));
                self.glass_torrent_handoffs.remove(&id);
                self.glass_torrent_recovery.insert(id,slot.clone());
                let wake=self.ui_ctx.clone();
                self.rt.spawn(async move {
                    let answer=async {
                        let saved=mdm_engine::state::ResumeState::load(&state_path)?;
                        if saved.dest!=dest {return Err("Saved state does not belong to this file".to_owned());}
                        let meta=match source {
                            MetadataSource::Magnet(source)=>{
                                let session=host.session(known).await?;
                                session.metadata(&source,crate::torrentdlg::METADATA_WAIT,None).await.map_err(|e|e.to_string())?
                            }
                            MetadataSource::Url(url)=>mdm_torrent::manual_recovery_source::metadata(url,&dns,&route).await?,
                        };
                        tokio::task::spawn_blocking(move || -> Result<_,String> {
                            let files=mdm_torrent::candidate_search::matching_files(&meta.torrent,&saved)?;
                            let mut report=mdm_torrent::candidate_search::SearchReport{searched:1,..Default::default()};
                            if !files.is_empty() {
                                report.matches.push(mdm_torrent::candidate_search::MatchedCandidate {
                                    candidate:mdm_torrent::candidate_search::Candidate{identifier:String::new(),title:meta.name,torrent_url:url::Url::parse("about:blank").expect("fixed URL")},info_hash:meta.info_hash,torrent:meta.torrent,files
                                });
                            }
                            Ok(report)
                        }).await.map_err(|_|"Torrent comparison task failed".to_owned())?
                    }.await;
                    if let Ok(mut result)=slot.lock(){*result=Some(answer);}
                    wake.request_repaint();
                });
                return Some(json!({"ok":true,"pending":true}).to_string());
            }
            "find-recovery-torrents" => {
                if !cmd.silent { self.auto_recovery_pending.remove(&id); self.auto_recovery_searches.remove(&id); }
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.context.private {return fail("Online torrent recovery search is unavailable for private downloads");}
                if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.video.is_some() || item.gallery.is_some() || item.remote.is_some() {
                    return fail("Stop an incomplete ordinary download before searching for recovery torrents");
                }
                if self.recovery_check_running(id) || self.repair_check_running(id) { return fail("A saved-data operation is already running"); }
                if self.glass_torrent_recovery.values().any(|slot|slot.lock().map_or(true,|result|result.is_none())) { return fail("Wait for the other torrent search to finish"); }
                let dest=item.dest.clone();
                let source=item.url.clone();
                let name=item.file_name.clone();
                let state_path=mdm_engine::state::state_path(&dest);
                if !state_path.exists() {return fail("No saved download state is available for this file");}
                let archive=url::Url::parse("https://archive.org/").expect("fixed URL");
                let opts=self.request_parts(&archive,None,&ipc::Command::default(),true).opts;
                let slot=std::sync::Arc::new(std::sync::Mutex::new(None));
                self.glass_torrent_recovery.remove(&id);
                self.glass_torrent_handoffs.remove(&id);
                self.glass_torrent_recovery.insert(id,slot.clone());
                let wake=self.ui_ctx.clone();
                self.rt.spawn(async move {
                    let answer=match mdm_engine::state::ResumeState::load(&state_path) {
                        Ok(saved) if saved.dest == dest && saved.url == source && saved.segments.iter().any(|segment| segment.cursor > segment.start) => {
                            mdm_torrent::candidate_search::find_archive_matches(&name,&saved,&opts).await
                        }
                        Ok(saved) if saved.dest == dest && saved.url == source => Err("No saved download bytes are available to compare".to_owned()),
                        Ok(_) => Err("Saved state does not belong to this file".to_owned()),
                        Err(error)=>Err(error),
                    };
                    if let Ok(mut result)=slot.lock(){*result=Some(answer);}
                    wake.request_repaint();
                });
                return Some(json!({"ok":true,"pending":true}).to_string());
            }
            "repair-saved" => {
                let item=self.items.iter().find(|i|i.id==id).unwrap();
                if item.live.is_some() || item.status==Status::Complete || item.torrent.is_some() || item.video.is_some() || item.gallery.is_some() || item.remote.is_some() {
                    return fail("Stop an incomplete ordinary download before repairing its saved data");
                }
                if self.recovery_check_running(id) || self.repair_check_running(id) { return fail("A saved-data operation is already running"); }
                let path=mdm_engine::state::state_path(&item.dest);
                let parts=self.request_parts(&item.url,item.login.as_ref(),&item.context,item.direct);
                let slot=std::sync::Arc::new(std::sync::Mutex::new(RepairSlot::default()));
                self.glass_repair_checks.insert(id,slot.clone());
                let wake=self.ui_ctx.clone();
                self.rt.spawn(async move {
                    let answer=mdm_engine::repair::prepare_http_repair(&path,parts.headers,&parts.opts).await.map(|report|json!({"prepared":true,"damaged_ranges":report.damaged_ranges,"retained_bytes":report.retained_bytes,"unhashed_bytes":report.unhashed_bytes})).map_err(|e|e.to_string());
                    if let Ok(mut value)=slot.lock(){value.result=Some(answer);}
                    wake.request_repaint();
                });
                return Some(json!({"ok":true,"pending":true}).to_string());
            }
            "checksum-result" => {
                let result=self.glass_checks.get(&id).and_then(|slot|slot.lock().ok().and_then(|v|v.clone()));
                return Some(match result {Some(Ok(matches))=>json!({"complete":true,"matches":matches}),Some(Err(error))=>json!({"complete":true,"error":error}),None=>json!({"complete":false})}.to_string());
            }
            "checksum" => {
                let Some(hash) = mdm_engine::verify::Hash::parse(value) else { return fail("Enter a valid MD5, SHA-1, SHA-256, SHA-512 or CRC32 checksum"); };
                let item = self.item(id).unwrap();
                if item.checksum.as_ref().map(|h| h.display()) != Some(hash.display()) {
                    item.checksum_from_server = false;
                }
                item.checksum = Some(hash.clone());
                let file=(item.status==Status::Complete).then(||item.dest.clone());
                self.dirty = true;
                if let Some(file)=file {
                    let slot=std::sync::Arc::new(std::sync::Mutex::new(None));
                    self.glass_checks.insert(id,slot.clone());
                    std::thread::spawn(move || {
                        let answer=mdm_engine::verify::matches(&file,&hash).map_err(|e|e.to_string());
                        *slot.lock().unwrap()=Some(answer);
                    });
                    return Some(json!({"ok":true,"pending":true}).to_string());
                }
                return Some(json!({"ok":true,"pending":false,"message":"Checksum saved for verification when the download finishes"}).to_string());
            }
            _ => return None,
        }
        Some(json!({"ok":true}).to_string())
    }
}
