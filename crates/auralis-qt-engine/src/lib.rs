//! Private C ABI between the Qt UI and the embedded Rust downloader.
use serde_json::{Value, json};
use std::{
    ffi::{CString, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
};

#[cfg(windows)]
mod updater;

const MAX_COMMAND: usize = 1024 * 1024;

fn response(action: impl FnOnce() -> Result<Value, String>) -> *mut c_char {
    let response = match catch_unwind(AssertUnwindSafe(action)) {
        Ok(Ok(result)) => json!({ "result": result }),
        Ok(Err(error)) => json!({ "error": error }),
        Err(_) => json!({ "error": "Auralis engine encountered an internal error" }),
    };
    CString::new(response.to_string())
        .expect("serialized JSON escapes interior NUL bytes")
        .into_raw()
}

fn ensure_owner() -> Result<(), String> {
    match mdm_ipc::app_pid() {
        Some(pid) if pid == std::process::id() => Ok(()),
        Some(_) => Err("Another instance may be using this profile".into()),
        None => Err("The Auralis engine is starting or unavailable".into()),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn auralis_engine_run() -> *mut c_char {
    response(|| mdm_app::run_embedded_downloader().map(|()| json!({ "ok": true })))
}

#[unsafe(no_mangle)]
pub extern "C" fn auralis_engine_profile() -> *mut c_char {
    response(|| {
        mdm_ipc::data_dir()
            .map(|path| json!(path))
            .ok_or_else(|| "The download profile is unavailable".into())
    })
}

/// # Safety
/// `input` must point to `length` readable bytes for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_engine_request(input: *const u8, length: usize) -> *mut c_char {
    response(|| {
        if input.is_null() || length == 0 || length > MAX_COMMAND {
            return Err("Invalid engine request length".into());
        }
        let input = unsafe { std::slice::from_raw_parts(input, length) };
        let request: Value = serde_json::from_slice(input).map_err(|e| e.to_string())?;
        if let Some(action) = request.get("shellAction").and_then(Value::as_str) {
            if action == "interface-language" {
                return Ok(json!(mdm_app::embedded_interface_language()));
            }
            if action == "appearance-presets" {
                return Ok(mdm_app::embedded_appearance_presets(
                    request["systemAccent"].as_str().unwrap_or_default(),
                ));
            }
            #[cfg(windows)]
            if action.starts_with("update-") {
                return updater::dispatch(action, &request);
            }
            #[cfg(windows)]
            if action == "installed-browsers" {
                return Ok(json!(
                    mdm_app::embedded_windows_browsers()
                        .into_iter()
                        .map(|(name, program)| {
                            json!({"name": name, "executable": program.to_string_lossy()})
                        })
                        .collect::<Vec<_>>()
                ));
            }
            if action == "browser-extension-status" {
                use mdm_ipc::extension::StoreBrowser;
                let executable = request["executable"].as_str().unwrap_or_default();
                let Some(browser) = StoreBrowser::from_windows_executable(executable) else {
                    return Ok(json!({"browserSupported": false}));
                };
                let presence = browser.windows_extension_presence(executable);
                let status = mdm_ipc::extension::browser_store_status(browser, presence);
                return Ok(json!({
                    "browserId": browser.id(),
                    "browser": browser.name(),
                    "browserSupported": true,
                    "storeUrl": mdm_ipc::extension::store_page(),
                    "extensionPresent": presence.source().is_some(),
                    "extensionDiscovery": presence.discovery(),
                    "extensionSource": status.connected_source.or(presence.source()),
                    "connectedRecently": status.connected_recently,
                    "extensionPreviouslyConnected": status.extension_previously_connected,
                    "storePreviouslyConnected": status.store_previously_connected,
                    "browserPreviouslyConnected": status.browser_previously_connected,
                }));
            }
            if action == "register-interface" {
                ensure_owner()?;
                let profile = mdm_ipc::data_dir().ok_or("The download profile is unavailable")?;
                std::fs::write(
                    profile.join("auralis-interface-version"),
                    env!("CARGO_PKG_VERSION"),
                )
                .map_err(|e| e.to_string())?;
                return Ok(json!({ "ok": true }));
            }
            if action == "clipboard-prefill" {
                ensure_owner()?;
                let mode = mdm_ipc::request_checked(&mdm_ipc::Command {
                    query: Some("glass-clipboard-mode".into()),
                    ..Default::default()
                })
                .map_err(|e| e.to_string())?;
                let mode: Value = serde_json::from_str(&mode).map_err(|e| e.to_string())?;
                let address = if mode["mode"] == "paste" {
                    mdm_app::add_url_clipboard_prefill()
                } else {
                    None
                };
                return Ok(address.map_or(Value::Null, |url| json!({ "url": url })));
            }
            return Err("Unsupported shell action".into());
        }

        ensure_owner()?;
        let command: mdm_ipc::Command =
            serde_json::from_value(request).map_err(|e| format!("Invalid engine request: {e}"))?;
        if command.exit {
            let status = mdm_ipc::request_checked(&mdm_ipc::Command {
                query: Some("glass-full-backup-status".into()),
                ..Default::default()
            })
            .map_err(|e| e.to_string())?;
            let status: Value = serde_json::from_str(&status).map_err(|e| e.to_string())?;
            if status["pending"] == true {
                return Err(
                    "Wait for the download backup or restore to finish before exiting".into(),
                );
            }
        }

        let reply = mdm_ipc::request_checked(&command).map_err(|e| e.to_string())?;
        match reply.as_str() {
            "ok" | "" => Ok(json!({ "ok": true })),
            "timeout" => Err("The engine did not answer in time".into()),
            text => Ok(serde_json::from_str(text).unwrap_or_else(|_| json!(text))),
        }
    })
}

/// # Safety
/// `output` must be null or an owned pointer returned by this library, freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn auralis_engine_free(output: *mut c_char) {
    if !output.is_null() {
        drop(unsafe { CString::from_raw(output) });
    }
}
