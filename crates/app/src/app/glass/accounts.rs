//! Original service sign-in; credentials stay in MDM and its existing secret store.
use super::*;
impl App {
    pub(super) fn glass_accounts(&mut self,cmd:&ipc::Command)->Option<String>{
        use crate::debrid::SignInState as S;
        if cmd.query.as_deref()==Some("glass-accounts"){
            let state=self.glass_account.as_ref().map(|(_,sign)|match sign.get(){
                S::Idle=>json!({"kind":"idle"}),S::Starting|S::Checking=>json!({"kind":"busy"}),
                S::Waiting{code,page,until}=>json!({"kind":"code","code":code,"page":page,"seconds":until.saturating_duration_since(Instant::now()).as_secs()}),
                S::Done{user,state,..}=>json!({"kind":"ready","user":user,"state":state}),S::Failed(e)=>json!({"kind":"error","message":e})
            });
            return Some(json!({"accounts":self.settings.debrid_accounts.iter().map(|a|json!({"id":a.id,"service":a.service.name(),"enabled":a.enabled,"user":a.user,"state":a.state})).collect::<Vec<_>>(),
                "services":mdm_debrid::ServiceKind::ALL.iter().map(|k|json!({"value":k,"name":k.name(),"code":k.signs_in_by_code()})).collect::<Vec<_>>(),"signin":state}).to_string());
        }
        if cmd.action.as_deref()!=Some("glass-account"){return None;}
        let data:Value=serde_json::from_str(cmd.queue.as_deref().unwrap_or("")).unwrap_or(Value::Null);
        let fail=|e:&str|Some(json!({"error":e}).to_string());
        match data["operation"].as_str().unwrap_or(""){
            "signin"=>{
                let Ok(service)=serde_json::from_value::<mdm_debrid::ServiceKind>(data["service"].clone())else{return fail("Choose a service");};
                if let Some((_,old))=self.glass_account.take(){old.stop.store(true,std::sync::atomic::Ordering::Relaxed);}
                let sign=crate::debrid::SignIn::default();
                match data["method"].as_str(){
                    Some("code") if service.signs_in_by_code()=>sign.by_code(service,&self.ui_ctx),
                    Some("password")=>sign.by_password(service,data["user"].as_str().unwrap_or("").to_owned(),data["password"].as_str().unwrap_or("").to_owned(),&self.ui_ctx),
                    Some("token")=>sign.by_token(service,data["token"].as_str().unwrap_or("").to_owned(),&self.ui_ctx),
                    _=>return fail("Choose a sign-in method")
                }
                self.glass_account=Some((service,sign));
            },
            "cancel"=>{if let Some((_,sign))=self.glass_account.take(){sign.stop.store(true,std::sync::atomic::Ordering::Relaxed);}},
            "save"=>{
                let Some((service,sign))=self.glass_account.as_ref()else{return fail("Sign in first");};
                let S::Done{user,state,credential}=sign.get()else{return fail("Sign-in is not complete");};
                let mut next=self.settings.clone();let id=next.debrid_accounts.iter().map(|a|a.id).max().unwrap_or(0)+1;
                next.debrid_accounts.push(crate::settings::DebridAccount{id,service:*service,enabled:true,user,state,secret:credential});
                self.glass_account=None;self.apply_options(next);
            },
            "update"|"remove"|"up"|"down"=>{
                let mut next=self.settings.clone();let Some(index)=next.debrid_accounts.iter().position(|a|Some(a.id)==data["id"].as_u64())else{return fail("Account not found");};
                match data["operation"].as_str().unwrap_or(""){
                    "remove"=>{next.debrid_accounts.remove(index);},"up" if index>0=>next.debrid_accounts.swap(index,index-1),"down" if index+1<next.debrid_accounts.len()=>next.debrid_accounts.swap(index,index+1),
                    "update"=>{if let Some(enabled)=data["enabled"].as_bool(){next.debrid_accounts[index].enabled=enabled;}},_=>{}
                }
                self.apply_options(next);
            },
            _=>return fail("Unsupported account action")
        }
        Some(json!({"ok":true}).to_string())
    }
}
