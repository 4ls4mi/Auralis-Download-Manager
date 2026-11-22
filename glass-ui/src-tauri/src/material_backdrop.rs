//! Apply Windows Desktop Acrylic to the whole transparent WebView client area.
#[tauri::command]
pub async fn set_material_acrylic(
    window: tauri::WebviewWindow,
    enabled: bool,
    dark: bool,
) -> Result<bool, String> {
    #[cfg(windows)]
    {
        let (result, mut completed) = tauri::async_runtime::channel(1);
        let target = window.clone();
        window
            .run_on_main_thread(move || {
                let _ = result.try_send(apply_acrylic(&target, enabled, dark));
            })
            .map_err(|error| error.to_string())?;
        completed
            .recv()
            .await
            .ok_or_else(|| "Windows backdrop update was interrupted".to_owned())?
    }
    #[cfg(not(windows))]
    {
        let _ = (window, enabled, dark);
        Ok(false)
    }
}

#[cfg(windows)]
fn apply_acrylic(window: &tauri::WebviewWindow, enabled: bool, dark: bool) -> Result<bool, String> {
    use windows_sys::Win32::{
        Graphics::Dwm::{
            DWMSBT_NONE, DWMSBT_TRANSIENTWINDOW, DWMWA_SYSTEMBACKDROP_TYPE,
            DWMWA_USE_IMMERSIVE_DARK_MODE, DwmExtendFrameIntoClientArea, DwmSetWindowAttribute,
        },
        UI::Controls::MARGINS,
    };

    let hwnd = window.hwnd().map_err(|error| error.to_string())?.0 as _;
    if system_backdrop(hwnd).is_none() {
        // Windows 10 and earlier Windows 11 releases use Tauri's legacy effect.
        return Ok(false);
    }

    let margin = if enabled { -1 } else { 0 };
    let margins = MARGINS {
        cxLeftWidth: margin,
        cxRightWidth: margin,
        cyTopHeight: margin,
        cyBottomHeight: margin,
    };
    let backdrop = if enabled {
        DWMSBT_TRANSIENTWINDOW
    } else {
        DWMSBT_NONE
    };
    let dark_mode = i32::from(dark);
    // The DWM consumes the two attribute values and margins synchronously.
    let result = unsafe {
        if enabled {
            DwmSetWindowAttribute(
                hwnd,
                DWMWA_USE_IMMERSIVE_DARK_MODE as u32,
                (&dark_mode as *const i32).cast(),
                size_of::<i32>() as u32,
            );
        }
        let frame_result = DwmExtendFrameIntoClientArea(hwnd, &margins);
        if frame_result < 0 {
            return Err(format!(
                "Could not extend the Windows glass frame ({frame_result:#x})"
            ));
        }
        DwmSetWindowAttribute(
            hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE as u32,
            (&backdrop as *const i32).cast(),
            size_of::<i32>() as u32,
        )
    };
    if result < 0 {
        let reset = MARGINS {
            cxLeftWidth: 0,
            cxRightWidth: 0,
            cyTopHeight: 0,
            cyBottomHeight: 0,
        };
        unsafe { DwmExtendFrameIntoClientArea(hwnd, &reset) };
        return Err(format!(
            "Could not set the Windows glass backdrop ({result:#x})"
        ));
    }
    Ok(true)
}

#[cfg(windows)]
pub fn system_backdrop(hwnd: windows_sys::Win32::Foundation::HWND) -> Option<i32> {
    use windows_sys::Win32::Graphics::Dwm::{DWMWA_SYSTEMBACKDROP_TYPE, DwmGetWindowAttribute};

    let mut backdrop = 0;
    let result = unsafe {
        DwmGetWindowAttribute(
            hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE as u32,
            (&mut backdrop as *mut i32).cast(),
            size_of::<i32>() as u32,
        )
    };
    (result >= 0).then_some(backdrop)
}
