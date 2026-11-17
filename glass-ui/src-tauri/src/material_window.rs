//! Native Windows clipping for the material outline. The UI draws inside this
//! region; Windows clips the WebView and native backdrop together.
#[tauri::command]
pub fn set_material_window_shape(window: tauri::WebviewWindow, material: String) -> Result<(), String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::POINT;
        use windows_sys::Win32::Graphics::Gdi::{CreatePolygonRgn, CreateRoundRectRgn, DeleteObject, SetWindowRgn, WINDING};
        let hwnd = window.hwnd().map_err(|e| e.to_string())?.0 as windows_sys::Win32::Foundation::HWND;
        if window.is_maximized().map_err(|e| e.to_string())? {
            // A maximized window must occupy the entire monitor work area.
            unsafe { SetWindowRgn(hwnd, std::ptr::null_mut(), 1); }
            return Ok(());
        }
        let size = window.outer_size().map_err(|e| e.to_string())?;
        let width = i32::try_from(size.width).map_err(|e| e.to_string())?;
        let height = i32::try_from(size.height).map_err(|e| e.to_string())?;
        if width < 2 || height < 2 { return Ok(()); }
        let shape = match material.as_str() {
            "ice-edge" | "diamond-facet" | "prismatic-glass" => {
                let cut = (width.min(height) / 30).clamp(6, 18);
                let points = [POINT{x:cut,y:0},POINT{x:width-cut,y:0},POINT{x:width,y:cut},POINT{x:width,y:height-cut},POINT{x:width-cut,y:height},POINT{x:cut,y:height},POINT{x:0,y:height-cut},POINT{x:0,y:cut}];
                // SAFETY: points remains valid for the duration of the call.
                unsafe { CreatePolygonRgn(points.as_ptr(), points.len() as i32, WINDING) }
            },
            _ => {
                let radius = match material.as_str() {"water-bubble" => 48,"liquid-glass" => 40,"aero-gloss" => 34,"frosted-layers" | "pearl-mist" => 28,_ => 18};
                let radius = radius.min(width / 3).min(height / 3);
                // SAFETY: arguments are finite physical window coordinates.
                unsafe { CreateRoundRectRgn(0, 0, width + 1, height + 1, radius, radius) }
            }
        };
        if shape.is_null() { return Err("Could not create the native material outline".into()); }
        // SAFETY: hwnd belongs to this Tauri window, and shape is a valid owned
        // GDI region. On success Windows owns it; on failure we must free it.
        if unsafe { SetWindowRgn(hwnd, shape, 1) } == 0 {
            unsafe { DeleteObject(shape as _); }
            return Err("Could not apply the native material outline".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    { let _ = (window, material); Err("Native material outlines are available on Windows".into()) }
}
