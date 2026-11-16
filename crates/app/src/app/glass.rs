//! Authenticated, local-only adapter to the original MDM actions and file-info queue.
//! Browser cookies/credentials remain in FileInfo.context and are never sent to a WebView.
mod settings;
mod tools;
mod accounts;
mod prompts;
use super::*;
use serde_json::{Value, json};

pub(super) type CheckSlots = HashMap<u64, std::sync::Arc<std::sync::Mutex<Option<Result<bool,String>>>>>;

impl App {
    pub(super) fn glass_owned(&self) -> bool {
        self.headless && std::env::var_os("MDM_GLASS_HEADLESS").is_some_and(|v| v == "1")
    }

    fn glass_next_info(&mut self) {
        if self.file_info.is_none()
            && let Some((new, context)) = self.file_info_waiting.pop_front()
        {
            let ctx = self.ui_ctx.clone();
            self.open_file_info(new, context, &ctx);
        }
    }

    pub(super) fn glass_answer(&mut self, cmd: &ipc::Command) -> Option<String> {
        if let Some(answer)=self.glass_prompts(cmd){return Some(answer);}
        if let Some(answer)=self.glass_accounts(cmd){return Some(answer);}
        if let Some(answer)=self.glass_tools(cmd){return Some(answer);}
        if cmd.query.as_deref()==Some("glass-original-settings"){return Some(self.glass_original_settings().to_string());}
        if cmd.action.as_deref()==Some("glass-original-setting"){
            let payload=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
            return Some(self.glass_update_original(payload).to_string());
        }
        if cmd.query.as_deref() == Some("glass-file-info") {
            self.glass_next_info();
            let serial = self.glass_info_serial;
            return Some(json!({"id": serial, "info": self.file_info.as_mut().map(FileInfo::glass_view),
                "categories":Category::all().into_iter().map(|c|json!({"key":c.key(),"name":c.label()})).collect::<Vec<_>>(), "waiting": self.file_info_waiting.len()}).to_string());
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
            self.add(&mut fi, if later { Start::Later } else { Start::Now });
            self.glass_next_info();
            return Some(json!({"ok":true,"id":id}).to_string());
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
            "checksum-result" => {
                let result=self.glass_checks.get(&id).and_then(|slot|slot.lock().ok().and_then(|v|v.clone()));
                return Some(match result {Some(Ok(matches))=>json!({"complete":true,"matches":matches}),Some(Err(error))=>json!({"complete":true,"error":error}),None=>json!({"complete":false})}.to_string());
            }
            "checksum" => {
                let Some(hash) = mdm_engine::verify::Hash::parse(value) else { return fail("Enter a valid MD5, SHA-1, SHA-256, SHA-512 or CRC32 checksum"); };
                let item = self.item(id).unwrap();
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
