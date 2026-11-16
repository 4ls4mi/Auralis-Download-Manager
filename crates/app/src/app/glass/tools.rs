//! Glass adapters delegate parsing, imports, categories and queueing to original MDM code.
use super::*;
impl App {
    pub(super) fn glass_tools(&mut self,cmd:&ipc::Command)->Option<String>{
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
