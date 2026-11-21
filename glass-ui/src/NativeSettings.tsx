import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { AlertCircle, CheckCircle2, ChevronRight, Folder, HardDrive, LoaderCircle, Settings2, Shield, X } from "lucide-react";
import "./native-settings.css";

export type NativeTab = "General" | "Connection" | "Downloads" | "Torrents" | "Integration" | "Scheduler";
type Props = {
  initialTab: NativeTab;
  onClose: () => void;
  queues: { name: string; running: boolean; ids: number[] }[];
  refresh: () => Promise<void>;
};
type SettingsSnapshot = {
  max_connections: number;
  speed_limit_on: boolean;
  speed_limit_kb: number;
  global_limit_on: boolean;
  global_limit_kb: number;
  start_immediately: boolean;
  only_add_to_queue: boolean;
  confirm_delete: boolean;
  torrent_keep_sharing: boolean;
  torrent_dht: boolean;
  torrent_lsd: boolean;
  proxy_from_browser: boolean;
  capture_opened: boolean;
  show_progress: boolean;
  show_complete: boolean;
  net_adapter: string;
  category_dirs: [string, string][];
};
type Key = keyof SettingsSnapshot;
const tabs: { tab: NativeTab; description: string }[] = [
  { tab: "General", description: "Behavior and confirmations" },
  { tab: "Connection", description: "Concurrency and limits" },
  { tab: "Downloads", description: "Download workflow and paths" },
  { tab: "Torrents", description: "Sharing and peer discovery" },
  { tab: "Integration", description: "Browser requests and network" },
  { tab: "Scheduler", description: "Running queues" }
];

export default function NativeSettings({ initialTab, onClose, queues, refresh }: Props) {
  const [tab, setTab] = useState<NativeTab>(initialTab);
  const [settings, setSettings] = useState<SettingsSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<Key | null>(null);
  const [warning, setWarning] = useState("");
  const [success, setSuccess] = useState("");

  const load = useCallback(async () => {
    try {
      const cfg = await invoke<SettingsSnapshot>("glass_settings");
      setSettings(cfg); setWarning("");
    } catch (e) {
      setWarning("The headless downloader could not provide its settings: " + String(e));
    } finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const edit = async (key: Key, value: string | boolean | number) => {
    setSaving(key); setWarning(""); setSuccess("");
    try {
      await invoke("update_glass_setting", { key, value: String(value) });
      await load();
      setSuccess("Saved to the active Rust downloader.");
    } catch (e) { setWarning(String(e)); }
    finally { setSaving(null); }
  };
  const toggle = (key: keyof SettingsSnapshot, label: string, description: string) => {
    const value = Boolean(settings?.[key]);
    return <label className="native-toggle" key={key}>
      <span><strong>{label}</strong><small>{description}</small></span>
      <input type="checkbox" checked={value} disabled={!settings || saving!==null}
        onChange={e => void edit(key,e.target.checked)}/>
    </label>;
  };
  const number = (key: keyof SettingsSnapshot, title: string, min: number, max: number, description: string) =>
    <label className="native-number" key={key}>
      <span><strong>{title}</strong><small>{description}</small></span>
      <input type="number" min={min} max={max} key={String(settings?.[key])}
        disabled={!settings || saving!==null}
        defaultValue={typeof settings?.[key] === "number" ? Number(settings?.[key]) : 0}
        onBlur={e => {
          const n=Number(e.target.value);
          if(Number.isInteger(n) && n>=min && n<=max && n!==settings?.[key])
            void edit(key,n);
          else if(n<min || n>max) setWarning(title+" must be between "+min+" and "+max);
        }}/>
    </label>;
  const section = () => {
    switch(tab) {
      case "General":
        return <>
          {toggle("start_immediately","Start new downloads automatically","Use the existing downloader's start-immediately setting")}
          {toggle("only_add_to_queue","Queue new downloads instead","Add requests to the download queue")}
          {toggle("confirm_delete","Confirm before deleting","Ask before deleting download items")}
          <p className="native-hint">The desktop window and system tray are now owned by Mister Hybrid Glass. The original egui window is not launched.</p>
        </>;
      case "Connection":
        return <>
          {number("max_connections","Maximum connections per file",1,128,"Original Rust engine's parallel connection limit")}
          {toggle("speed_limit_on","Enable download speed limiter","Use the global speed limiter")}
          {number("speed_limit_kb","Speed limit (KB/s)",0,10_000_000,"Zero means no set speed threshold")}
          {toggle("global_limit_on","Enable cumulative download limit","Apply an overall transfer budget")}
          {number("global_limit_kb","Cumulative limit (KB)",0,10_000_000,"Original download manager limit")}
          <p className="native-hint">Advanced proxy authentication and custom DNS editing are still being migrated; their existing saved values are preserved.</p>
        </>;
      case "Downloads":
        return <>
          <div className="native-info"><HardDrive size={20}/><span>Existing folders are loaded from the original MDM data and have not been changed.</span></div>
          {(settings?.category_dirs?.length ?? 0)>0 ?
            <div className="native-folders">{settings?.category_dirs.map(([category,path],i)=><div key={category+i}><Folder size={15}/><strong>{category}</strong><span title={path}>{path}</span></div>)}</div> :
            <p className="native-hint">No custom category folder mappings saved. The original default download locations remain in effect.</p>}
          {toggle("confirm_delete","Confirm deleting downloads","Confirmation before removing files or entries")}
          <p className="native-hint">Folder editing and other advanced file operations are planned for the next settings migration milestone.</p>
        </>;
      case "Torrents":
        return <>
          {toggle("torrent_keep_sharing","Keep sharing completed torrents","Seeding behavior handled by the original torrent engine")}
          {toggle("torrent_dht","Enable DHT","Peer discovery through distributed hash table")}
          {toggle("torrent_lsd","Enable local peer discovery","Discover peers on your local network")}
          <p className="native-hint">Peer lists and torrent file selection still require additional native APIs. Existing torrent jobs are retained.</p>
        </>;
      case "Integration":
        return <>
          {toggle("proxy_from_browser","Use browser-provided proxy","Preserve network context sent by the browser extension")}
          {toggle("capture_opened","Capture browser-opened downloads","Original download-capture preference")}
          <div className="native-info"><Shield size={20}/><span>The headless process exposes authenticated IPC on loopback. Its separate remote HTTP control is disabled when launched by Glass.</span></div>
          <p className="native-hint">Browser-extension registration, network adapter selection and site login editing need their own Glass-native controls. Nothing has been deleted from your settings.</p>
        </>;
      case "Scheduler":
        return <div className="native-queues">{queues.length ? queues.map(q=>
          <div key={q.name} className="native-queue">
            <span><strong>{q.name}</strong><small>{q.ids.length} queued downloads • {q.running?"Running":"Stopped"}</small></span>
            <button disabled={saving!==null}
              onClick={async()=>{
                setWarning(""); setSuccess("");
                try {
                  await invoke("queue_action",{name:q.name,action:q.running?"stop_queue":"start_queue"});
                  await refresh(); setSuccess(q.running?"Queue stopped":"Queue started");
                } catch(e){setWarning(String(e))}
              }}>{q.running?"Stop queue":"Start queue"} <ChevronRight size={15}/></button>
          </div>) : <p>No queues are available from the Rust engine.</p>}</div>;
    }
  };

  return <div className="native-settings-overlay" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}>
    <section className="native-settings-window" role="dialog" aria-modal="true" aria-label="Mister Hybrid engine settings">
      <div className="native-header"><div><Settings2 size={23}/><span><strong>Mister Hybrid — Engine Options</strong><small>Native controls backed by the real headless Rust downloader</small></span></div><button onClick={onClose} aria-label="Close"><X size={19}/></button></div>
      <div className="native-body"><aside>{tabs.map(t=><button key={t.tab} className={tab===t.tab?"selected":""} onClick={()=>{setTab(t.tab);setSuccess("");setWarning("")}}><strong>{t.tab}</strong><small>{t.description}</small></button>)}</aside>
        <div className="native-content"><div className="native-content-heading"><h2>{tab}</h2><span>{saving?<><LoaderCircle size={14}/> Saving</>:loading?<><LoaderCircle size={14}/> Loading</>:<><CheckCircle2 size={14}/> Connected</>}</span></div>
          {loading?<div className="native-loading">Loading live settings from Rust downloader…</div>:section()}
          {warning&&<div className="native-error"><AlertCircle size={17}/>{warning}</div>}
          {success&&<div className="native-success"><CheckCircle2 size={17}/>{success}</div>}
        </div>
      </div>
      <div className="native-footer"><p>Safe migration: these controls modify the existing MDM backend. Unmigrated advanced options remain stored, but aren't editable here yet.</p><button onClick={onClose}>Close settings</button></div>
    </section>
  </div>;
}
