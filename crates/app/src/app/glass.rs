//! Authenticated, local-only adapter to the original MDM actions and file-info queue.
//! Browser cookies/credentials remain in FileInfo.context and are never sent to a WebView.
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
        if cmd.query.as_deref() == Some("glass-file-info") {
            self.glass_next_info();
            let serial = self.glass_info_serial;
            return Some(json!({"id": serial, "info": self.file_info.as_mut().map(FileInfo::glass_view),
                "categories":Category::all().into_iter().map(|c|json!({"key":c.key(),"name":c.label()})).collect::<Vec<_>>(), "waiting": self.file_info_waiting.len()}).to_string());
        }
        if cmd.query.as_deref() == Some("glass-queues") {
            return Some(json!({"queues":self.queues}).to_string());
        }
        if cmd.action.as_deref() == Some("glass-category") {
            let Ok(data)=serde_json::from_str::<Value>(cmd.queue.as_deref().unwrap_or("")) else {return Some(json!({"error":"Invalid category"}).to_string());};
            let name=data["name"].as_str().unwrap_or("").trim();
            if name.is_empty()||name.len()>120||self.settings.custom_categories.iter().any(|c|c.name.eq_ignore_ascii_case(name)) {
                return Some(json!({"error":"Choose a unique category name"}).to_string());
            }
            let id=self.settings.custom_categories.iter().map(|c|c.id).max().unwrap_or(0)+1;
            let category=crate::model::CustomCategory {id,name:name.into(),types:data["types"].as_str().unwrap_or("").chars().take(2048).collect(),folder:data["folder"].as_str().filter(|s|!s.is_empty()).map(str::to_owned)};
            self.settings.custom_categories.push(category);
            crate::model::set_custom(&self.settings.custom_categories);
            if let Some(fi)=self.file_info.as_mut(){fi.set_category(Category::Custom(id));}
            self.dirty=true;
            return Some(json!({"ok":true}).to_string());
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
