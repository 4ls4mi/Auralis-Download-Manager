//! Match the compositor's square window frame to the WebView client area.
#[tauri::command]
pub fn set_material_window_shape(
    window: tauri::WebviewWindow,
    flat: Option<bool>,
) -> Result<(), String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Graphics::Dwm::{
            DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_DONOTROUND, DwmSetWindowAttribute,
        };
        use windows_sys::Win32::Graphics::Gdi::{CreateRectRgn, DeleteObject, SetWindowRgn};

        let hwnd = window.hwnd().map_err(|error| error.to_string())?.0 as _;
        let preference = DWMWCP_DONOTROUND;
        // Windows 11 may round undecorated windows independently of the WebView.
        // Older versions ignore this preference and use the rectangular region.
        unsafe {
            DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE as u32,
                std::ptr::from_ref(&preference).cast(),
                std::mem::size_of_val(&preference) as u32,
            );
        }
        if flat.unwrap_or(false) || window.is_maximized().map_err(|error| error.to_string())? {
            // Snapped and maximized windows use the system's full allocated area.
            unsafe {
                SetWindowRgn(hwnd, std::ptr::null_mut(), 1);
            }
            return Ok(());
        }

        let client = window.inner_size().map_err(|error| error.to_string())?;
        let inner = window.inner_position().map_err(|error| error.to_string())?;
        let outer = window.outer_position().map_err(|error| error.to_string())?;
        let size = window.outer_size().map_err(|error| error.to_string())?;
        let width = i32::try_from(size.width).map_err(|error| error.to_string())?;
        let height = i32::try_from(size.height).map_err(|error| error.to_string())?;
        // Region coordinates use the outer HWND origin. Trim any non-client border
        // so acrylic ends at the same edge as the WebView's square client area.
        let left = (i64::from(inner.x) - i64::from(outer.x)).clamp(0, i64::from(width)) as i32;
        let top = (i64::from(inner.y) - i64::from(outer.y)).clamp(0, i64::from(height)) as i32;
        let right = (i64::from(left) + i64::from(client.width)).min(i64::from(width)) as i32;
        let bottom = (i64::from(top) + i64::from(client.height)).min(i64::from(height)) as i32;
        if right <= left || bottom <= top {
            return Ok(());
        }
        let region = unsafe { CreateRectRgn(left, top, right, bottom) };
        if region.is_null() {
            return Err("Could not create the square window frame".into());
        }
        // SetWindowRgn takes ownership only on success.
        if unsafe { SetWindowRgn(hwnd, region, 1) } == 0 {
            unsafe {
                DeleteObject(region as _);
            }
            return Err("Could not apply the square window frame".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = (window, flat);
        Err("Native window frames are available on Windows".into())
    }
}

/// Read back the actual region from the HWND that rendered the smoke-test page.
#[tauri::command]
pub fn inspect_material_window_region(
    window: tauri::WebviewWindow,
) -> Result<serde_json::Value, String> {
    if !super::is_isolated_test() {
        return Err("Material region inspection requires an isolated test session".into());
    }
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::RECT;
        use windows_sys::Win32::Graphics::Gdi::{
            CreateRectRgn, DeleteObject, GetRgnBox, GetWindowRgn, PtInRegion, SIMPLEREGION,
        };

        let hwnd = window.hwnd().map_err(|error| error.to_string())?.0 as _;
        let scale = window.scale_factor().map_err(|error| error.to_string())?;
        let region = unsafe { CreateRectRgn(0, 0, 0, 0) };
        if region.is_null() {
            return Err("Could not allocate a region for inspection".into());
        }

        let mut bounds = RECT::default();
        let kind = unsafe { GetWindowRgn(hwnd, region) };
        let bounds_kind = unsafe { GetRgnBox(region, &mut bounds) };
        let RECT {
            left,
            top,
            right,
            bottom,
        } = bounds;
        let mid_x = left + (right - left) / 2;
        let mid_y = top + (bottom - top) / 2;
        let corner = (4.0 * scale).floor().max(1.0) as i32;
        let edge = (2.0 * scale).ceil().max(1.0) as i32;
        let contains = |x, y| unsafe { PtInRegion(region, x, y) != 0 };
        // GDI excludes right and bottom coordinates. Sample just inside each
        // edge to avoid treating differences at the outermost pixel as a gap.
        let corners = [
            contains(left + corner, top + corner),
            contains(right - 1 - corner, top + corner),
            contains(left + corner, bottom - 1 - corner),
            contains(right - 1 - corner, bottom - 1 - corner),
        ];
        let edges = [
            contains(mid_x, top + edge),
            contains(mid_x, bottom - 1 - edge),
            contains(left + edge, mid_y),
            contains(right - 1 - edge, mid_y),
        ];
        unsafe { DeleteObject(region as _) };

        Ok(serde_json::json!({
            "square": kind == SIMPLEREGION && bounds_kind == SIMPLEREGION
                && corners.iter().all(|inside| *inside) && edges.iter().all(|inside| *inside),
            "nativeHandle": hwnd as usize,
            "systemBackdrop": super::material_backdrop::system_backdrop(hwnd),
            "foreground": unsafe { windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow() } == hwnd,
            "regionKind": kind,
            "boundsKind": bounds_kind,
            "bounds": [left, top, right, bottom],
            "cornersInside": corners,
            "edgesInside": edges,
            "scale": scale,
        }))
    }
    #[cfg(not(windows))]
    {
        Err("Native material outlines are available on Windows".into())
    }
}
