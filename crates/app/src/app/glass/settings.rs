//! Full typed adapters for original download, proxy, capture and authentication preferences.
//! Password values are never returned. Blank password edits preserve the saved secret.
use super::*;

fn extension_capture_browsers() -> impl Iterator<Item = &'static str> {
    crate::settings::BROWSERS.into_iter().filter(|&name| {
        !matches!(name, "Internet Explorer" | "Microsoft Edge Legacy" | "Apple Safari")
    })
}

fn set_browser_capture(browsers: &mut Vec<(String, bool)>, browser: &str, enabled: bool) -> bool {
    if !extension_capture_browsers().any(|name| name == browser) {
        return false;
    }
    let mut found = false;
    for (_, capture) in browsers.iter_mut().filter(|(name, _)| name == browser) {
        *capture = enabled;
        found = true;
    }
    if !found {
        browsers.push((browser.to_owned(), enabled));
    }
    true
}

impl App {
    pub(super) fn glass_clipboard_mode(&self) -> &'static str {
        match (self.settings.clipboard_autostart, self.settings.glass_clipboard_auto_download) {
            (false, _) => "off",
            (true, false) => "paste",
            (true, true) => "download",
        }
    }

    pub(super) fn glass_original_settings(&self)->Value {
        let mut fields:Vec<Value>=Vec::new();
        fields.push(json!({"key":"update_check","label":"Check original MDM releases on startup","section":"General","kind":"boolean","value":self.settings.update_check}));
        fields.push(json!({
            "key": "clipboard_mode", "label": "Clipboard links", "section": "General", "kind": "select",
            "options": [
                {"label": "Off", "value": "off"},
                {"label": "Paste into Add URL", "value": "paste"},
                {"label": "Download copied links automatically", "value": "download"}
            ],
            "value": self.glass_clipboard_mode()
        }));
        fields.push(json!({"key":"speed_limit_on","label":"Speed Limiter enabled","section":"General","kind":"boolean","value":self.settings.speed_limit_on}));
        fields.push(json!({"key":"limiter_on_startup","label":"Enable the speed limiter on startup","section":"General","kind":"boolean","value":self.settings.limiter_on_startup}));
        fields.push(json!({"key":"global_only_active","label":"Apply the total cap only while the computer is in use","section":"General","kind":"boolean","value":self.settings.global_only_active}));
        fields.push(json!({"key":"delete_files_too","label":"Remember disk deletion in the delete confirmation","section":"General","kind":"boolean","value":self.settings.delete_files_too}));
        fields.push(json!({"key":"change_folder_on_last","label":"Remember the last folder for each category","section":"General","kind":"boolean","value":self.settings.change_folder_on_last}));
        fields.push(json!({"key":"queue_panel_later","label":"Show queue selection for Download Later","section":"General","kind":"boolean","value":self.settings.queue_panel_later}));
        fields.push(json!({"key":"queue_panel_batch","label":"Show queue selection for batch downloads","section":"General","kind":"boolean","value":self.settings.queue_panel_batch}));
        fields.push(json!({"key":"set_creation_date","label":"Use the server file timestamp","section":"Downloads","kind":"boolean","value":self.settings.set_creation_date}));
        fields.push(json!({"key":"mark_downloads","label":"Mark downloaded files with their web origin","section":"Downloads","kind":"boolean","value":self.settings.mark_downloads}));
        fields.push(json!({"key":"ignore_mtime","label":"Ignore modified timestamps when resuming","section":"Downloads","kind":"boolean","value":self.settings.ignore_mtime}));
        fields.push(json!({"key":"duplicate_action","label":"When the same address is added again","section":"Downloads","kind":"select","options":["Ask what to do","Add with a numbered filename","Replace the existing file","Open or resume the existing file"],"value":self.settings.duplicate_action}));
        fields.push(json!({"key":"category_dirs","label":"Category folders","section":"Downloads","kind":"table","columns":[{"label":"Category","kind":"text"},{"label":"Folder","kind":"text"}],"value":self.settings.category_dirs}));
        fields.push(json!({"key":"extract_auto","label":"Automatically extract completed archives","section":"Downloads","kind":"boolean","value":self.settings.extract_auto}));
        fields.push(json!({"key":"extract_delete","label":"Delete archives after successful extraction","section":"Downloads","kind":"boolean","value":self.settings.extract_delete}));
        fields.push(json!({"key":"extract_in_place","label":"Use in-place archive extraction","section":"Downloads","kind":"boolean","value":self.settings.extract_in_place}));
        fields.push(json!({"key":"extract_subfolder","label":"Extraction folder","section":"Downloads","kind":"select","options":["Choose automatically","Always create a folder","Extract into the current folder"],"value":self.settings.extract_subfolder}));
        fields.push(json!({"key":"grabber_check","label":"Check links before importing","section":"Downloads","kind":"boolean","value":self.settings.grabber_check}));
        fields.push(json!({"key":"grabber_hide_pages","label":"Hide web pages from link results","section":"Downloads","kind":"boolean","value":self.settings.grabber_hide_pages}));
        fields.push(json!({"key":"many_connections","label":"Allow more than 32 connections","section":"Connection","kind":"boolean","value":self.settings.many_connections}));
        fields.push(json!({"key":"user_agent","label":"Default User-Agent","section":"Connection","kind":"text","value":self.settings.user_agent}));
        fields.push(json!({"key":"conn_exceptions","label":"Per-server connection limits","section":"Connection","kind":"table","columns":[{"label":"Server pattern","kind":"text"},{"label":"Connections","kind":"number"}],"value":self.settings.conn_exceptions}));
        fields.push(json!({"key":"proxy_mode","label":"Proxy mode","section":"Connection","kind":"select","options":["No proxy","System proxy settings","Automatic configuration (PAC)","Manual proxy"],"value":self.settings.proxy_mode}));
        fields.push(json!({"key":"proxy_script","label":"Proxy auto-configuration script URL","section":"Connection","kind":"text","value":self.settings.proxy_script}));
        fields.push(json!({"key":"proxy_host","label":"Proxy server","section":"Connection","kind":"text","value":self.settings.proxy_host}));
        fields.push(json!({"key":"proxy_port","label":"Proxy port","section":"Connection","kind":"text","value":self.settings.proxy_port}));
        fields.push(json!({"key":"proxy_user","label":"Proxy username","section":"Connection","kind":"text","value":self.settings.proxy_user}));
        fields.push(json!({"key":"proxy_http","label":"Use the proxy for HTTP","section":"Connection","kind":"boolean","value":self.settings.proxy_http}));
        fields.push(json!({"key":"proxy_https","label":"Use the proxy for HTTPS","section":"Connection","kind":"boolean","value":self.settings.proxy_https}));
        fields.push(json!({"key":"proxy_ftp","label":"Use the proxy for FTP","section":"Connection","kind":"boolean","value":self.settings.proxy_ftp}));
        fields.push(json!({"key":"dns_mode","label":"DNS transport","section":"Connection","kind":"select","options":["System DNS","Plain DNS","DNS over TLS","DNS over HTTPS"],"value":self.settings.dns_mode}));
        fields.push(json!({"key":"dns_provider","label":"DNS provider preset or custom","section":"Connection","kind":"text","value":self.settings.dns_provider}));
        fields.push(json!({"key":"dns_servers","label":"Custom DNS server addresses","section":"Connection","kind":"text","value":self.settings.dns_servers}));
        fields.push(json!({"key":"dns_tls_name","label":"DNS over TLS certificate hostname","section":"Connection","kind":"text","value":self.settings.dns_tls_name}));
        fields.push(json!({"key":"dns_doh_url","label":"DNS over HTTPS URL","section":"Connection","kind":"text","value":self.settings.dns_doh_url}));
        fields.push(json!({"key":"dns_nextdns_id","label":"NextDNS configuration ID","section":"Connection","kind":"text","value":self.settings.dns_nextdns_id}));
        fields.push(json!({"key":"dns_fallback","label":"Fall back to system DNS","section":"Connection","kind":"boolean","value":self.settings.dns_fallback}));
        fields.push(json!({"key":"ftp_passive","label":"Passive FTP","section":"Connection","kind":"boolean","value":self.settings.ftp_passive}));
        fields.push(json!({"key":"site_logins","label":"Site authentication","section":"Connection","kind":"table","columns":[{"label":"Site / path","kind":"text"},{"label":"Username","kind":"text"},{"label":"Password","kind":"password"}],"value":self.settings.site_logins.iter().map(|(site,user,_)|(site,user,"")).collect::<Vec<_>>()}));
        fields.push(json!({
            "key": "browsers", "label": "Capture downloads from these browsers", "section": "Browser Integration",
            "kind": "table", "columns": [{"label":"Browser","kind":"text"},{"label":"Capture","kind":"boolean"}],
            "value": self.settings.browsers,
            "captureBrowsers": extension_capture_browsers().map(|name| json!({
                "name": name,
                "enabled": !self.settings.browsers.iter().any(|(browser, enabled)| browser == name && !enabled)
            })).collect::<Vec<_>>()
        }));
        fields.push(json!({"key":"auto_types","label":"Automatically captured file extensions","section":"Browser Integration","kind":"text","value":self.settings.auto_types}));
        fields.push(json!({"key":"excluded_sites","label":"Excluded sites","section":"Browser Integration","kind":"text","value":self.settings.excluded_sites}));
        fields.push(json!({"key":"excluded_addresses","label":"Excluded download addresses","section":"Browser Integration","kind":"lines","value":self.settings.excluded_addresses}));
        fields.push(json!({"key":"video_panel","label":"Show the download panel over videos","section":"Browser Integration","kind":"boolean","value":self.settings.video_panel}));
        fields.push(json!({"key":"video_panel_sites","label":"Sites without a video panel","section":"Browser Integration","kind":"text","value":self.settings.video_panel_sites}));
        fields.push(json!({"key":"capture_min_kb","label":"Minimum captured file size (KB)","section":"Browser Integration","kind":"number","value":self.settings.capture_min_kb}));
        fields.push(json!({"key":"mv2_extensions","label":"Support Manifest V2 browser extensions","section":"Browser Integration","kind":"boolean","value":self.settings.mv2_extensions}));
        fields.push(json!({"key":"torrent_incoming","label":"Accept incoming peer connections","section":"Torrents","kind":"boolean","value":self.settings.torrent_incoming}));
        fields.push(json!({"key":"torrent_upnp","label":"Map the peer port with UPnP","section":"Torrents","kind":"boolean","value":self.settings.torrent_upnp}));
        fields.push(json!({"key":"torrent_port","label":"Incoming peer port (0 = automatic)","section":"Torrents","kind":"number","value":self.settings.torrent_port}));
        fields.push(json!({"key":"torrent_proxy","label":"Use the configured SOCKS5 proxy for torrents","section":"Torrents","kind":"boolean","value":self.settings.torrent_proxy}));
        fields.push(json!({"key":"torrent_blocklist","label":"Peer blocklist URL","section":"Torrents","kind":"text","value":self.settings.torrent_blocklist}));
        fields.push(json!({"key":"torrent_stop_idle","label":"Stop the torrent engine while idle","section":"Torrents","kind":"boolean","value":self.settings.torrent_stop_idle}));
        fields.push(json!({"key":"torrent_upload_on","label":"Limit total torrent uploading","section":"Torrents","kind":"boolean","value":self.settings.torrent_upload_on}));
        fields.push(json!({"key":"torrent_upload_kb","label":"Total torrent upload limit (KB/sec)","section":"Torrents","kind":"number","value":self.settings.torrent_upload_kb}));
        fields.push(json!({"key":"torrent_stop_ratio_on","label":"Stop seeding at a share ratio","section":"Torrents","kind":"boolean","value":self.settings.torrent_stop_ratio_on}));
        fields.push(json!({"key":"torrent_stop_ratio","label":"Share ratio in hundredths (200 = 2.00)","section":"Torrents","kind":"number","value":self.settings.torrent_stop_ratio}));
        fields.push(json!({"key":"torrent_stop_minutes_on","label":"Stop seeding after a time limit","section":"Torrents","kind":"boolean","value":self.settings.torrent_stop_minutes_on}));
        fields.push(json!({"key":"torrent_stop_minutes","label":"Seeding time limit (minutes)","section":"Torrents","kind":"number","value":self.settings.torrent_stop_minutes}));
        fields.push(json!({"key":"limits_on","label":"Enable download quota","section":"Scheduler","kind":"boolean","value":self.settings.limits_on}));
        fields.push(json!({"key":"limits_mb","label":"Download quota (MB)","section":"Scheduler","kind":"number","value":self.settings.limits_mb}));
        fields.push(json!({"key":"limits_hours","label":"Quota period (hours)","section":"Scheduler","kind":"number","value":self.settings.limits_hours}));
        fields.push(json!({"key":"limits_warn","label":"Warn before reaching the quota","section":"Scheduler","kind":"boolean","value":self.settings.limits_warn}));
        fields.push(json!({"key":"debrid_on","label":"Use connected file-host service accounts","section":"Advanced","kind":"boolean","value":self.settings.debrid_on}));
        fields.push(json!({"key":"debrid_torrents","label":"Download torrents through supported service accounts","section":"Advanced","kind":"boolean","value":self.settings.debrid_torrents}));
        fields.push(json!({"key":"sounds","label":"Notification sounds","section":"Advanced","kind":"table","columns":[{"label":"Enabled","kind":"boolean"},{"label":"Sound file","kind":"text"}],"fixed":true,"value":self.settings.sounds}));
        fields.push(json!({"key":"regional","label":"Date and time format","section":"Advanced","kind":"regional","value":self.settings.regional}));
        fields.push(json!({"key":"video_chapters","label":"Embed video chapters","section":"Advanced","kind":"boolean","value":self.settings.video_chapters}));
        fields.push(json!({"key":"video_cookies","label":"Browser for video-helper cookies","section":"Advanced","kind":"text","value":self.settings.video_cookies}));
        fields.push(json!({"key":"video_cookies_file","label":"Manual video cookies file (Netscape)","section":"Advanced","kind":"text","value":self.settings.video_cookies_file}));
        fields.push(json!({"key":"video_cookies_profile","label":"Video-helper browser profile","section":"Advanced","kind":"text","value":self.settings.video_cookies_profile}));
        fields.push(json!({"key":"cnl_on","label":"Enable Click’n’Load","section":"Advanced","kind":"boolean","value":self.settings.cnl_on}));
        fields.push(json!({"key":"cnl_sites","label":"Remembered Click’n’Load sites","section":"Advanced","kind":"table","columns":[{"label":"Site","kind":"text"},{"label":"Allowed","kind":"boolean"}],"value":self.settings.cnl_sites}));
        fields.push(json!({"key":"proxy_pass","label":"Proxy password","section":"Connection","kind":"password","value":"","saved":!self.settings.proxy_pass.is_empty()}));
        if let Some(field)=fields.iter_mut().find(|f|f["key"]=="category_dirs") {
            field["columns"][0]["options"]=json!(Category::all().into_iter().map(|c|json!({"label":c.shown(),"value":c.key()})).collect::<Vec<_>>());
        }
        json!({"fields":fields})
    }

    pub(super) fn glass_update_original(&mut self,payload:Value)->Value {
        let Some(key)=payload["key"].as_str() else {return json!({"error":"Choose a setting"});};
        let value=payload["value"].clone();
        if value.to_string().len()>131072 {return json!({"error":"Setting is too large"});}
        let mut next=self.settings.clone();
        let apply=(||->Result<(),String>{
            match key {
                "update_check" => next.update_check=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "clipboard_mode" => {
                    let (paste, download) = match value.as_str() {
                        Some("off") => (false, false),
                        Some("paste") => (true, false),
                        Some("download") => (true, true),
                        _ => return Err("Choose a valid clipboard mode".into()),
                    };
                    next.clipboard_autostart = paste;
                    next.glass_clipboard_auto_download = download;
                }
                "clipboard_autostart" => next.clipboard_autostart=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "glass_clipboard_auto_download" => next.glass_clipboard_auto_download=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "speed_limit_on" => next.speed_limit_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "limiter_on_startup" => next.limiter_on_startup=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "global_only_active" => next.global_only_active=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "delete_files_too" => next.delete_files_too=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "change_folder_on_last" => next.change_folder_on_last=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "queue_panel_later" => next.queue_panel_later=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "queue_panel_batch" => next.queue_panel_batch=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "set_creation_date" => next.set_creation_date=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "mark_downloads" => next.mark_downloads=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "ignore_mtime" => next.ignore_mtime=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "duplicate_action" => next.duplicate_action=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "category_dirs" => next.category_dirs=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "extract_auto" => next.extract_auto=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "extract_delete" => next.extract_delete=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "extract_in_place" => next.extract_in_place=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "extract_subfolder" => next.extract_subfolder=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "grabber_check" => next.grabber_check=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "grabber_hide_pages" => next.grabber_hide_pages=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "many_connections" => next.many_connections=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "user_agent" => next.user_agent=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "conn_exceptions" => next.conn_exceptions=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_mode" => next.proxy_mode=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_script" => next.proxy_script=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_host" => next.proxy_host=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_port" => next.proxy_port=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_user" => next.proxy_user=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_http" => next.proxy_http=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_https" => next.proxy_https=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_ftp" => next.proxy_ftp=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_mode" => next.dns_mode=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_provider" => next.dns_provider=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_servers" => next.dns_servers=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_tls_name" => next.dns_tls_name=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_doh_url" => next.dns_doh_url=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_nextdns_id" => next.dns_nextdns_id=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "dns_fallback" => next.dns_fallback=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "ftp_passive" => next.ftp_passive=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "browsers" => {
                    if let Some(browser) = payload["browser"].as_str() {
                        let enabled = value.as_bool().ok_or("Choose whether to capture browser downloads")?;
                        if !set_browser_capture(&mut next.browsers, browser, enabled) {
                            return Err("Choose a supported browser".into());
                        }
                    } else {
                        next.browsers = serde_json::from_value(value.clone()).map_err(|e| e.to_string())?;
                    }
                },
                "auto_types" => next.auto_types=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "excluded_sites" => next.excluded_sites=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "excluded_addresses" => next.excluded_addresses=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "video_panel" => next.video_panel=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "video_panel_sites" => next.video_panel_sites=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "capture_min_kb" => next.capture_min_kb=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "mv2_extensions" => next.mv2_extensions=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_incoming" => next.torrent_incoming=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_upnp" => next.torrent_upnp=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_port" => next.torrent_port=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_proxy" => next.torrent_proxy=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_blocklist" => next.torrent_blocklist=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_stop_idle" => next.torrent_stop_idle=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_upload_on" => next.torrent_upload_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_upload_kb" => next.torrent_upload_kb=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_stop_ratio_on" => next.torrent_stop_ratio_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_stop_ratio" => next.torrent_stop_ratio=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_stop_minutes_on" => next.torrent_stop_minutes_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "torrent_stop_minutes" => next.torrent_stop_minutes=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "limits_on" => next.limits_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "limits_mb" => next.limits_mb=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "limits_hours" => next.limits_hours=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "limits_warn" => next.limits_warn=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "debrid_on" => next.debrid_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "debrid_torrents" => next.debrid_torrents=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "sounds" => next.sounds=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "regional" => next.regional=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "video_chapters" => next.video_chapters=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "video_cookies" => next.video_cookies=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "video_cookies_file" => {
                    let path=value.as_str().ok_or("Enter a cookie file path")?.trim();
                    if !path.is_empty() && (!std::path::Path::new(path).is_absolute() || !std::path::Path::new(path).is_file()) { return Err("Choose an existing absolute path to a Netscape cookies.txt file".into()); }
                    next.video_cookies_file=path.to_owned();
                },
                "video_cookies_profile" => next.video_cookies_profile=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "cnl_on" => next.cnl_on=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "cnl_sites" => next.cnl_sites=serde_json::from_value(value.clone()).map_err(|e|e.to_string())?,
                "proxy_pass"=>{
                    let value=value.as_str().ok_or("Enter a password")?;
                    if !value.is_empty()||payload["clear"].as_bool()==Some(true){next.proxy_pass=value.to_owned();}
                },
                "site_logins"=>{
                    let mut logins:Vec<(String,String,String)>=serde_json::from_value(value).map_err(|e|e.to_string())?;
                    if logins.len()>500 {return Err("Too many site logins".into());}
                    let clear=payload["clear_passwords"].as_array();
                    for (index,(site,user,password)) in logins.iter_mut().enumerate(){
                        let clear=clear.is_some_and(|v|v.iter().any(|v|v.as_u64()==Some(index as u64)));
                        if password.is_empty()&&!clear&&let Some(old)=self.settings.site_logins.iter().find(|(s,u,_)|s==site&&u==user){password.clone_from(&old.2);}
                    }
                    next.site_logins=logins;
                },
                _=>return Err("Unsupported setting".into()),
            }
            if key=="proxy_mode"&&next.proxy_mode>3||key=="dns_mode"&&next.dns_mode>3||key=="duplicate_action"&&next.duplicate_action>3||key=="extract_subfolder"&&next.extract_subfolder>2 {return Err("Choose a valid option".into());}
            if key=="proxy_port"&&!next.proxy_port.is_empty()&&next.proxy_port.trim().parse::<u16>().ok().filter(|p|*p>0).is_none(){return Err("Proxy port must be 1–65535".into());}
            if key=="conn_exceptions"&&next.conn_exceptions.iter().any(|(_,n)|!(1..=128).contains(n)){return Err("Connection counts must be 1–128".into());}
            if key=="regional"&&next.regional.week_start>6 {return Err("Choose a valid first day of the week".into());}
            if key=="category_dirs"&&next.category_dirs.iter().any(|(key,_)|!Category::all().iter().any(|c|c.key()==key.as_str())) {return Err("Choose a known category".into());}
            Ok(())
        })();
        if let Err(error)=apply {return json!({"error":error});}
        self.apply_options(next);
        json!({"ok":true})
    }
}
