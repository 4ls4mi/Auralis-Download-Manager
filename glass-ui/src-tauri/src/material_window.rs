//! Native Windows clipping for the material outline. The UI draws inside this
//! region; Windows clips the WebView and native backdrop together.
#[tauri::command]
pub fn set_material_window_shape(
    window: tauri::WebviewWindow,
    material: String,
    outline: Option<Vec<[f64; 2]>>,
    flat: Option<bool>,
    backdrop_radius: Option<f64>,
) -> Result<(), String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::POINT;
        use windows_sys::Win32::Graphics::Gdi::{
            CreatePolygonRgn, CreateRoundRectRgn, DeleteObject, SetWindowRgn, WINDING,
        };
        let hwnd =
            window.hwnd().map_err(|e| e.to_string())?.0 as windows_sys::Win32::Foundation::HWND;
        if flat.unwrap_or(false) || window.is_maximized().map_err(|e| e.to_string())? {
            // Snapped and maximized windows must fill their allocated rectangle.
            unsafe {
                SetWindowRgn(hwnd, std::ptr::null_mut(), 1);
            }
            return Ok(());
        }
        let size = window.outer_size().map_err(|e| e.to_string())?;
        let width = i32::try_from(size.width).map_err(|e| e.to_string())?;
        let height = i32::try_from(size.height).map_err(|e| e.to_string())?;
        if width < 2 || height < 2 {
            return Ok(());
        }
        let shape = if let Some(radius) = backdrop_radius {
            // Match the WebView's flush border at the current monitor scale.
            // The window region is measured from the HWND's outer origin.
            let client = window.inner_size().map_err(|e| e.to_string())?;
            let inner = window.inner_position().map_err(|e| e.to_string())?;
            let outer = window.outer_position().map_err(|e| e.to_string())?;
            let scale = window.scale_factor().map_err(|e| e.to_string())?;
            let left = (i64::from(inner.x) - i64::from(outer.x)).clamp(0, i64::from(width)) as i32;
            let top = (i64::from(inner.y) - i64::from(outer.y)).clamp(0, i64::from(height)) as i32;
            let right = (i64::from(left) + i64::from(client.width)).min(i64::from(width)) as i32;
            let bottom = (i64::from(top) + i64::from(client.height)).min(i64::from(height)) as i32;
            if right <= left || bottom <= top {
                return Ok(());
            }
            // GDI takes a diameter; CSS takes a radius, both in their own pixel units.
            let diameter = (2.0 * radius.clamp(0.0, 40.0) * scale).round() as i32;
            let diameter = diameter.clamp(0, (right - left).min(bottom - top));
            unsafe { CreateRoundRectRgn(left, top, right, bottom, diameter, diameter) }
        } else {
            match material.as_str() {
                "frosted-water-351" => {
                    let Some(outline) = outline.filter(|p| {
                        p.len() >= 3
                            && p.len() <= 4096
                            && p.iter()
                                .flatten()
                                .all(|v| v.is_finite() && (0.0..=1.0).contains(v))
                    }) else {
                        // The renderer will supply its outline after its first frame.
                        unsafe {
                            SetWindowRgn(hwnd, std::ptr::null_mut(), 1);
                        }
                        return Ok(());
                    };
                    // Keep the hard Windows region just outside the shader's antialiased edge.
                    // The tiny transparent margin preserves smooth pixels without restoring a
                    // large rectangular area that intercepts clicks.
                    let middle = outline.len() / 2;
                    let points: Vec<POINT> = outline
                        .iter()
                        .enumerate()
                        .map(|(i, p)| POINT {
                            x: ((p[0] * f64::from(width)).round() as i32
                                + if i < middle { -2 } else { 2 })
                            .clamp(0, width),
                            y: ((p[1] * f64::from(height)).round() as i32
                                + if p[1] < 0.5 { -2 } else { 2 })
                            .clamp(0, height),
                        })
                        .collect();
                    unsafe { CreatePolygonRgn(points.as_ptr(), points.len() as i32, WINDING) }
                }
                "ice-edge" | "diamond-facet" | "prismatic-glass" => {
                    let cut = (width.min(height) / 30).clamp(6, 18);
                    let points = [
                        POINT { x: cut, y: 0 },
                        POINT {
                            x: width - cut,
                            y: 0,
                        },
                        POINT { x: width, y: cut },
                        POINT {
                            x: width,
                            y: height - cut,
                        },
                        POINT {
                            x: width - cut,
                            y: height,
                        },
                        POINT { x: cut, y: height },
                        POINT {
                            x: 0,
                            y: height - cut,
                        },
                        POINT { x: 0, y: cut },
                    ];
                    // SAFETY: points remains valid for the duration of the call.
                    unsafe { CreatePolygonRgn(points.as_ptr(), points.len() as i32, WINDING) }
                }
                _ => {
                    let radius = match material.as_str() {
                        "water-bubble" => 48,
                        "liquid-glass" => 40,
                        "aero-gloss" => 34,
                        "frosted-layers" | "pearl-mist" => 28,
                        _ => 18,
                    };
                    let radius = radius.min(width / 3).min(height / 3);
                    // SAFETY: arguments are finite physical window coordinates.
                    unsafe { CreateRoundRectRgn(0, 0, width + 1, height + 1, radius, radius) }
                }
            }
        };
        if shape.is_null() {
            return Err("Could not create the native material outline".into());
        }
        // SAFETY: hwnd belongs to this Tauri window, and shape is a valid owned
        // GDI region. On success Windows owns it; on failure we must free it.
        if unsafe { SetWindowRgn(hwnd, shape, 1) } == 0 {
            unsafe {
                DeleteObject(shape as _);
            }
            return Err("Could not apply the native material outline".into());
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = (window, material, outline, flat, backdrop_radius);
        Err("Native material outlines are available on Windows".into())
    }
}
