//! Glass adapters delegate parsing, imports, categories and queueing to original MDM code.
use super::*;
use std::sync::{Mutex, OnceLock};

// One helper installation at a time. The original verified installers own all
// download, signature/checksum verification and atomic replacement logic.
static GLASS_HELPER_JOB: OnceLock<Mutex<Option<(String,String)>>> = OnceLock::new();
fn helper_job() -> &'static Mutex<Option<(String,String)>> { GLASS_HELPER_JOB.get_or_init(|| Mutex::new(None)) }
static GLASS_UPSTREAM_CHECK: OnceLock<Mutex<Option<crate::help::Slot>>> = OnceLock::new();
fn upstream_check() -> &'static Mutex<Option<crate::help::Slot>> { GLASS_UPSTREAM_CHECK.get_or_init(|| Mutex::new(None)) }

impl App {
    pub(in crate::app) fn glass_tools(&mut self,cmd:&ipc::Command)->Option<String>{
        if cmd.query.as_deref()==Some("glass-upstream-check") {
            let slot=upstream_check().lock().unwrap_or_else(|e|e.into_inner()).clone();
            let value=match slot {
                None=>json!({"state":"not-checked"}),
                Some(slot)=>{
                    let result=slot.lock().unwrap_or_else(|e|e.into_inner()).clone();
                    match result {
                        None=>json!({"state":"checking"}),
                        Some(Ok(crate::help::Found::Latest))=>json!({"state":"latest"}),
                        Some(Ok(crate::help::Found::Newer(release)))=>json!({"state":"newer","version":release.version,"date":release.date}),
                        Some(Err(error))=>json!({"state":"error","message":error}),
                    }
                }
            };
            return Some(value.to_string());
        }
        if cmd.action.as_deref()==Some("glass-upstream-check") {
            *upstream_check().lock().unwrap_or_else(|e|e.into_inner())=Some(crate::help::check(&self.rt,&self.ui_ctx));
            return Some(json!({"ok":true}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-helpers") {
            let Some(dir)=mdm_tools::tools_dir() else {return Some(json!({"error":"Helper tools folder is unavailable"}).to_string());};
            let status=helper_job().lock().unwrap_or_else(|e|e.into_inner()).clone();
            let entry=|name:&str,found:Option<mdm_tools::Installed>|json!({"name":name,"version":found.as_ref().map(|x|&x.version),"path":found.as_ref().map(|x|x.exe.to_string_lossy().into_owned())});
            return Some(json!({"tools":[entry("yt-dlp",mdm_tools::installed(&dir)),entry("ffmpeg",mdm_tools::ffmpeg::installed(&dir)),entry("gallery-dl",mdm_tools::gallery::installed(&dir))],"job":status.map(|(name,state)|json!({"name":name,"state":state}))}).to_string());
        }
        if cmd.action.as_deref()==Some("glass-helpers") {
            let data:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
            let Some(name)=data["name"].as_str().filter(|n|matches!(*n,"yt-dlp"|"ffmpeg"|"gallery-dl")) else{return Some(json!({"error":"Choose a helper"}).to_string());};
            let Some(dir)=mdm_tools::tools_dir() else{return Some(json!({"error":"Helper tools folder is unavailable"}).to_string());};
            let mut job=helper_job().lock().unwrap_or_else(|e|e.into_inner());
            if job.as_ref().is_some_and(|(_,state)|state=="installing"){return Some(json!({"error":"Another helper is being installed"}).to_string());}
            let name=name.to_owned();*job=Some((name.clone(),"installing".into()));drop(job);
            let net=crate::settings::own_net();
            self.rt.spawn(async move {
                let result=match name.as_str(){"ffmpeg"=>mdm_tools::ffmpeg::install_latest(&dir,&net,None).await,"gallery-dl"=>mdm_tools::gallery::install_latest(&dir,&net,None).await,_=>mdm_tools::install_latest(&dir,&net,None).await};
                let state=match result {Ok(_) => "ready".to_owned(),Err(e)=>format!("Error: {}",crate::errors::tools(&e))};
                *helper_job().lock().unwrap_or_else(|e|e.into_inner())=Some((name,state));
            });
            return Some(json!({"ok":true}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-grabber-status") {return Some(json!({"version":self.glass_import_serial,"pending":self.grabber.is_some()}).to_string());}
        if cmd.query.as_deref()==Some("glass-grabber-state") {
            return Some(json!({"version":self.glass_import_serial,"data":self.grabber.as_mut().map(crate::grabber::Grabber::glass_view)}).to_string());
        }
        if cmd.query.as_deref()==Some("glass-categories") {
            return Some(json!({"categories":Category::all().into_iter().map(|c|json!({"key":c.key(),"name":c.label(),"types":c.types_text(),"folder":self.settings.category_dir(c,&self.downloads),"editable":c.editable()})).collect::<Vec<_>>()} ).to_string());
        }
        let action=cmd.action.as_deref()?;
        if !matches!(action,"glass-batch"|"glass-grabber"|"glass-category"){return None;}
        let data:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
        let fail=|error:&str|Some(json!({"error":error}).to_string());
        match action {
            "glass-batch"=>{
                let urls=match crate::batch::Batch::glass_pattern(&data){Ok(urls)=>urls,Err(e)=>return fail(e)};
                if data["commit"]==true {
                    let login=data["login"].as_str().filter(|s|!s.is_empty()).map(|s|(s.to_owned(),data["password"].as_str().unwrap_or("").to_owned()));
                    self.add_batch(crate::batch::Added{urls,login});
                    return Some(json!({"ok":true}).to_string());
                }
                Some(json!({"count":urls.len(),"preview":urls.iter().take(5).collect::<Vec<_>>()} ).to_string())
            }
            "glass-grabber"=>{
                match data["operation"].as_str().unwrap_or("edit"){
                    "import"=>{
                        let text=data["text"].as_str().unwrap_or("");if text.len()>8_000_000{return fail("Import is too large");}
                        let links=crate::transfer::import(text);if links.is_empty(){return fail("No supported download links found");}
                        self.show_import(links,"Imported links".into());
                    },
                    "commit"=>{
                        let Some(g)=self.grabber.as_mut() else{return fail("No links to add");};
                        let packages=g.glass_picked();if packages.is_empty(){return fail("Select at least one link");}
                        self.grabber=None;self.add_grabbed(data["start"]==true,packages);
                    },
                    "clear"=>{self.grabber=None;},
                    _=>{let Some(g)=self.grabber.as_mut()else{return fail("No links to edit");};if let Err(e)=g.glass_edit(&data){return fail(&e);}}
                }
                Some(json!({"ok":true}).to_string())
            }
            "glass-category"=>{
                let key=data["key"].as_str();
                let cat=key.and_then(|key|Category::all().into_iter().find(|c|c.key()==key));
                if key.is_some()&&cat.is_none(){return fail("Category not found");}
                if data["delete"]==true {
                    let Some(cat)=cat.filter(|c|*c!=Category::General&&*c!=Category::Torrents)else{return fail("This category cannot be deleted");};
                    crate::categories::delete(&mut self.settings,cat,&mut self.items);self.dirty=true;
                    return Some(json!({"ok":true}).to_string());
                }
                let name=data["name"].as_str().unwrap_or("").trim();
                if name.is_empty()||name.len()>120||Category::all().iter().any(|c|Some(*c)!=cat&&c.shown().to_lowercase()==name.to_lowercase()){return fail("Choose a unique category name");}
                let target=cat.map(crate::categories::Target::Edit).unwrap_or(crate::categories::Target::New);
                let category=crate::categories::apply(&mut self.settings,crate::categories::CategoryEdit{target,name:name.to_owned(),types:crate::categories::normalize_types(data["types"].as_str().unwrap_or("")),folder:data["folder"].as_str().unwrap_or("").to_owned()},&self.downloads);
                if cat.is_none()&&let Some(fi)=self.file_info.as_mut(){fi.set_category(category);}
                self.dirty=true;Some(json!({"ok":true}).to_string())
            },
            _=>None
        }
    }
}
