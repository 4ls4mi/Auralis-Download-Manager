//! Per-user Auralis startup registration. The downloader's own startup entry is independent.
use crate::ApiResult;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

#[derive(Clone, Serialize, Deserialize)]
pub struct StartupSettings {
    pub enabled: bool,
    pub mode: String,
}

const MINIMIZED: &str = "--auralis-startup-minimized";
const WINDOW: &str = "--auralis-startup-window";

pub fn is_startup(args: impl IntoIterator<Item = String>) -> bool {
    args.into_iter().any(|a| a == MINIMIZED || a == WINDOW)
}
pub fn is_minimized_startup() -> bool {
    std::env::args().any(|a| a == MINIMIZED)
}

fn config_path(app: &AppHandle) -> ApiResult<std::path::PathBuf> {
    Ok(app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("startup.json"))
}
fn saved_mode(app: &AppHandle) -> String {
    std::fs::read(config_path(app).unwrap_or_default())
        .ok()
        .and_then(|b| serde_json::from_slice::<StartupSettings>(&b).ok())
        .map(|s| s.mode)
        .filter(|s| s == "window" || s == "minimized")
        .unwrap_or_else(|| "minimized".into())
}

#[cfg(windows)]
mod registry {
    use std::ffi::c_void;
    use windows_sys::Win32::System::Registry::{
        HKEY_CURRENT_USER, REG_SZ, RRF_RT_REG_SZ, RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW,
    };
    const KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
    const NAME: &str = "Auralis Download Manager";
    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(Some(0)).collect()
    }
    pub fn read() -> Result<Option<String>, String> {
        let key = wide(KEY);
        let name = wide(NAME);
        let mut data = vec![0u16; 32768];
        let mut size = (data.len() * 2) as u32;
        let rc = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                RRF_RT_REG_SZ,
                std::ptr::null_mut(),
                data.as_mut_ptr() as *mut c_void,
                &mut size,
            )
        };
        if rc == 2 {
            return Ok(None);
        }
        if rc != 0 {
            return Err(format!("Unable to read Windows startup entry (error {rc})"));
        }
        let len = (size as usize / 2).saturating_sub(1).min(data.len());
        Ok(Some(String::from_utf16_lossy(&data[..len])))
    }
    pub fn write(value: Option<&str>) -> Result<(), String> {
        let key = wide(KEY);
        let name = wide(NAME);
        let rc = unsafe {
            if let Some(value) = value {
                let data = wide(value);
                RegSetKeyValueW(
                    HKEY_CURRENT_USER,
                    key.as_ptr(),
                    name.as_ptr(),
                    REG_SZ,
                    data.as_ptr() as *const c_void,
                    (data.len() * 2) as u32,
                )
            } else {
                RegDeleteKeyValueW(HKEY_CURRENT_USER, key.as_ptr(), name.as_ptr())
            }
        };
        if rc == 0 || (value.is_none() && rc == 2) {
            Ok(())
        } else {
            Err(format!(
                "Unable to update Windows startup entry (error {rc})"
            ))
        }
    }
}

#[tauri::command]
pub fn startup_settings(app: AppHandle) -> ApiResult<StartupSettings> {
    #[cfg(windows)]
    {
        let value = registry::read()?;
        let mode = match value.as_deref() {
            Some(v) if v.ends_with(WINDOW) => "window".into(),
            Some(v) if v.ends_with(MINIMIZED) => "minimized".into(),
            _ => saved_mode(&app),
        };
        Ok(StartupSettings {
            enabled: value.is_some(),
            mode,
        })
    }
    #[cfg(not(windows))]
    {
        Ok(StartupSettings {
            enabled: false,
            mode: saved_mode(&app),
        })
    }
}

#[tauri::command]
pub fn set_startup_settings(
    app: AppHandle,
    enabled: bool,
    mode: String,
) -> ApiResult<StartupSettings> {
    if mode != "window" && mode != "minimized" {
        return Err("Unsupported startup window mode".into());
    }
    #[cfg(windows)]
    {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let argument = if mode == "minimized" {
            MINIMIZED
        } else {
            WINDOW
        };
        let command = format!("\"{}\" {argument}", exe.display());
        registry::write(if enabled { Some(&command) } else { None })?;
    }
    #[cfg(not(windows))]
    if enabled {
        return Err("Starting with Windows is available only on Windows".into());
    }
    let path = config_path(&app)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let settings = StartupSettings { enabled, mode };
    std::fs::write(
        path,
        serde_json::to_vec(&settings).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    Ok(settings)
}
