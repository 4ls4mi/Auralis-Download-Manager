import {invoke} from '@tauri-apps/api/core';
const extra=new Set(['auralis-update-presentation','auralis-download-columns','auralis-setup-auto-close']);
const allowed=(key:string)=>key.startsWith('mh-glass-')||extra.has(key);
export function appearanceBackup():Record<string,string>{const result:Record<string,string>={};for(let i=0;i<localStorage.length;i++){const key=localStorage.key(i);if(key&&allowed(key)){const value=localStorage.getItem(key);if(value!==null)result[key]=value}}return result}
export async function savePreferences(){return invoke<string|null>('export_preferences',{ui:appearanceBackup()})}
export async function restorePreferences(){const data=await invoke<Record<string,unknown>|null>('import_preferences');if(!data)return false;for(const [key,value] of Object.entries(data)){if(allowed(key)&&typeof value==='string'&&value.length<=16384)localStorage.setItem(key,value)}return true}
