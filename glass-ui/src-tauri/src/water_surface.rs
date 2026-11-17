//! Experimental native background. The opt-in is process-wide and applies
//! only to download windows; no desktop capture or production material toggle.
use tauri::WebviewWindow;

#[cfg(target_os = "windows")]
unsafe extern "C" { fn mhg_water_surface(hwnd: isize, rgb: u32, light: i32) -> i32; fn mhg_water_remove(hwnd: isize); fn mhg_d3d11_water_surface(hwnd: isize, rgb: u32, light: i32, opacity: u32, tint: u32) -> i32; fn mhg_d3d11_water_remove(hwnd: isize); fn mhg_d3d11_water_panels(hwnd: isize, values: *const f32, count: u32) -> i32; }

#[tauri::command]
pub async fn experimental_water_surface(window: WebviewWindow, rgb: u32, light: bool, enabled: bool, opacity: u32, tint: u32) -> Result<u8, String> {
    if std::env::var_os("MHG_EXPERIMENTAL_WATER").as_deref() != Some(std::ffi::OsStr::new("1"))
        || !window.label().starts_with("download-") {
        return Ok(0);
    }
    #[cfg(target_os = "windows")]
    {
        // SetWindowSubclass and Direct2D resources must be created on the HWND's UI thread.
        let hwnd = window.hwnd().map_err(|e| e.to_string())?.0 as isize;
        let d3d = std::env::var_os("MHG_EXPERIMENTAL_RENDERER").as_deref() == Some(std::ffi::OsStr::new("d3d11"));
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        window.run_on_main_thread(move || {
            // SAFETY: the HWND is owned by the requesting Tauri window. The native
            // subclass removes itself and frees its resources at WM_NCDESTROY.
            let result = unsafe { if enabled { if d3d { mhg_d3d11_water_surface(hwnd, rgb & 0x00ff_ffff, i32::from(light), opacity, tint) } else { mhg_water_surface(hwnd, rgb & 0x00ff_ffff, i32::from(light)) } } else { if d3d { mhg_d3d11_water_remove(hwnd) } else { mhg_water_remove(hwnd) }; 0 } };
            let result = u8::try_from(result).unwrap_or(0);
            let _ = tx.send(result);
        }).map_err(|e| e.to_string())?;
        return tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(std::time::Duration::from_secs(5)).map_err(|e| e.to_string()))
            .await.map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    { let _ = (rgb, light, enabled, opacity, tint); Ok(0) }
}

/// Updates only experimental GPU panel geometry. Bounds are physical pixels;
/// invalid or excessive data is rejected before crossing the native boundary.
#[tauri::command]
pub async fn experimental_water_panels(window: WebviewWindow, panels: Vec<[f32; 4]>) -> Result<bool, String> {
    if std::env::var_os("MHG_EXPERIMENTAL_WATER").as_deref() != Some(std::ffi::OsStr::new("1"))
        || std::env::var_os("MHG_EXPERIMENTAL_RENDERER").as_deref() != Some(std::ffi::OsStr::new("d3d11"))
        || !window.label().starts_with("download-") || panels.len() > 3
        || panels.iter().any(|p| !p.iter().all(|v| v.is_finite() && v.abs() <= 32768.0) || p[2] <= 0.0 || p[3] <= 0.0) {
        return Ok(false);
    }
    #[cfg(target_os = "windows")]
    {
        let hwnd = window.hwnd().map_err(|e| e.to_string())?.0 as isize;
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        window.run_on_main_thread(move || {
            // SAFETY: the HWND belongs to this window; Vec<[f32;4]> is contiguous,
            // remains alive through the call, and its validated count is <= 3.
            let ok = unsafe { mhg_d3d11_water_panels(hwnd, panels.as_ptr().cast(), panels.len() as u32) } != 0;
            let _ = tx.send(ok);
        }).map_err(|e| e.to_string())?;
        return tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(std::time::Duration::from_secs(5)).map_err(|e| e.to_string()))
            .await.map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    { Ok(false) }
}
