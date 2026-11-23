//! The native host's Windows calls: letting the app come to the front, reading its registry
//! entries.
#![allow(unsafe_code)]

/// Let process `pid` (the app) bring its windows to the front. Windows refuses that to a program
/// in the background (the foreground lock), so a window opened at the browser's request (Options
/// from the video button, Download File Info) would open behind it. The browser is in front and
/// started this host, which lets the host pass that right on. Nothing happens when it can't.
pub fn allow_foreground(pid: u32) {
    use windows_sys::Win32::UI::WindowsAndMessaging::AllowSetForegroundWindow;
    // SAFETY: a plain call with a process id; it fails harmlessly for a wrong or ended one.
    unsafe {
        AllowSetForegroundWindow(pid);
    }
}

/// The default value of `key` under HKLM (`machine`) or HKCU, when it is a string.
pub fn reg_string(machine: bool, key: &str) -> Option<String> {
    use std::ffi::c_void;
    use windows_sys::Win32::System::Registry::{
        HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, RRF_RT_REG_SZ, RegGetValueW,
    };
    let root = if machine {
        HKEY_LOCAL_MACHINE
    } else {
        HKEY_CURRENT_USER
    };
    let key: Vec<u16> = key.encode_utf16().chain(Some(0)).collect();
    let mut buf = vec![0u16; 2048];
    let mut size = (buf.len() * 2) as u32;
    // SAFETY: a registry read into `buf`, whose size in bytes is passed in `size`; a null value
    // name reads the key's default value.
    let rc = unsafe {
        RegGetValueW(
            root,
            key.as_ptr(),
            std::ptr::null(),
            RRF_RT_REG_SZ,
            std::ptr::null_mut(),
            buf.as_mut_ptr() as *mut c_void,
            &mut size,
        )
    };
    if rc != 0 {
        return None;
    }
    let len = (size as usize / 2).saturating_sub(1).min(buf.len());
    Some(String::from_utf16_lossy(&buf[..len]))
}

/// Chromium may launch the native host through cmd.exe. Identify its actual browser executable
/// rather than treating a Chrome-like User-Agent from a Chromium fork as Google Chrome.
pub fn launching_store_browser() -> Option<mdm_ipc::extension::StoreBrowser> {
    use mdm_ipc::extension::StoreBrowser;
    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
        TH32CS_SNAPPROCESS,
    };
    use windows_sys::Win32::System::Threading::{
        OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW,
    };

    struct Handle(HANDLE);
    impl Drop for Handle {
        fn drop(&mut self) {
            // SAFETY: each Handle owns a valid handle returned by Windows.
            unsafe { CloseHandle(self.0) };
        }
    }

    fn image(pid: u32) -> Option<String> {
        // SAFETY: opening for read-only process image information.
        let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
        if process.is_null() {
            return None;
        }
        let process = Handle(process);
        let mut path = vec![0_u16; 32768];
        let mut length = path.len() as u32;
        // SAFETY: Windows writes at most the number of UTF-16 units in length.
        if unsafe { QueryFullProcessImageNameW(process.0, 0, path.as_mut_ptr(), &mut length) } == 0
        {
            return None;
        }
        String::from_utf16(&path[..length as usize]).ok()
    }

    // SAFETY: the snapshot contains metadata only. Both enumeration calls receive a fully
    // initialized, writable PROCESSENTRY32W structure with the required size set.
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == INVALID_HANDLE_VALUE {
        return None;
    }
    let snapshot = Handle(snapshot);
    // SAFETY: PROCESSENTRY32W is a C record of integers and a UTF-16 array.
    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
    let mut parents = std::collections::HashMap::new();
    let mut valid = unsafe { Process32FirstW(snapshot.0, &mut entry) };
    while valid != 0 {
        parents.insert(entry.th32ProcessID, entry.th32ParentProcessID);
        valid = unsafe { Process32NextW(snapshot.0, &mut entry) };
    }
    let parent = *parents.get(&std::process::id())?;
    let parent_image = image(parent)?;
    let parent_path = parent_image.to_ascii_lowercase();
    if parent_path.ends_with(r"\system32\cmd.exe") || parent_path.ends_with(r"\syswow64\cmd.exe") {
        return StoreBrowser::from_windows_executable(&image(*parents.get(&parent)?)?);
    }
    StoreBrowser::from_windows_executable(&parent_image)
}
