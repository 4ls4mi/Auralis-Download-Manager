//! Original duplicate decisions and Download Later's queue panel.
use super::*;
impl App {
    pub(super) fn glass_prompts(&mut self,cmd:&ipc::Command)->Option<String>{
        if cmd.query.as_deref()==Some("glass-prompts"){
            while self.duplicate.is_none()&&let Some((id,pending,dialog))=self.duplicates_waiting.pop_front(){
                self.glass_duplicate_serial=self.glass_duplicate_serial.wrapping_add(1);
                if self.items.iter().any(|i|i.id==id){self.duplicate=Some((id,pending,dialog));}else{self.duplicate_again(pending,&self.ui_ctx.clone());}
            }
            return Some(json!({"duplicate":self.duplicate.as_ref().map(|(id,_,_)|json!({"lease":self.glass_duplicate_serial,"file":self.items.iter().find(|i|i.id==*id).map(|i|&i.file_name)})),
                "queue":self.queue_pick.as_ref().map(|(ids,_)|json!({"lease":ids.first(),"count":ids.len(),"queues":self.queues.iter().map(|q|&q.name).collect::<Vec<_>>()}))}).to_string());
        }
        if cmd.action.as_deref()!=Some("glass-prompt"){return None;}
        let data:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
        let fail=|e:&str|Some(json!({"error":e}).to_string());
        match data["kind"].as_str(){
            Some("duplicate")=>{
                if data["lease"].as_u64()!=Some(self.glass_duplicate_serial)||self.duplicate.is_none(){return fail("This duplicate question is no longer pending");}
                if data["cancel"]!=true&&!data["choice"].as_u64().is_some_and(|c|(1..=3).contains(&c)){return fail("Choose how to handle the duplicate");}
                let (id,pending,_)=self.duplicate.take().unwrap();
                if data["cancel"]!=true{self.resolve_duplicate(id,pending,data["choice"].as_u64().unwrap() as usize,&self.ui_ctx.clone());}
            },
            Some("queue")=>{
                if self.queue_pick.as_ref().and_then(|(ids,_)|ids.first().copied())!=data["lease"].as_u64(){return fail("This queue question is no longer pending");}
                let queue=self.queues.iter().position(|q|Some(q.name.as_str())==data["name"].as_str());
                if data["cancel"]!=true&&queue.is_none(){return fail("Choose a queue");}
                let Some((ids,_))=self.queue_pick.take()else{return fail("No queue selection is pending");};
                if let Some(q)=queue.filter(|_|data["cancel"]!=true){for id in ids{if self.items.iter().any(|i|i.id==id)&&!self.queues[q].items.contains(&id){self.queues[q].items.push(id);}}if data["start"]==true{self.start_queue(q);}self.dirty=true;}
            },_=>return fail("Unknown download question")
        }
        Some(json!({"ok":true}).to_string())
    }
}
