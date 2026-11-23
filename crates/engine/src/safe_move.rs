//! Filesystem operations that preserve the destination and avoid linked files.
#![allow(unsafe_code)]
use std::{
    fs::{File, Metadata, OpenOptions},
    io,
    path::Path,
};

/// Whether metadata obtained without following an entry describes an alias.
pub fn is_link_or_reparse(metadata: &Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;
        metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
    }
    #[cfg(not(windows))]
    metadata.file_type().is_symlink()
}

/// Opens regular writable storage without following its final component or
/// truncating it before verifying it is not shared with another name.
pub fn open_download_file(path: &Path, create: bool) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(create);
    #[cfg(unix)]
    {
        use rustix::fs::OFlags;
        use std::os::unix::fs::OpenOptionsExt;
        // NONBLOCK prevents opening a special entry such as a named pipe from waiting.
        options.custom_flags((OFlags::NOFOLLOW | OFlags::NONBLOCK).bits() as i32);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_FLAG_OPEN_REPARSE_POINT;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    let file = options.open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() || is_link_or_reparse(&metadata) || multiple_links(&file, &metadata)? {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "download storage must be an unlinked regular file",
        ));
    }
    Ok(file)
}

#[cfg(unix)]
fn multiple_links(_file: &File, metadata: &Metadata) -> io::Result<bool> {
    use std::os::unix::fs::MetadataExt;
    Ok(metadata.nlink() != 1)
}

#[cfg(windows)]
fn multiple_links(file: &File, _metadata: &Metadata) -> io::Result<bool> {
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        BY_HANDLE_FILE_INFORMATION, GetFileInformationByHandle,
    };
    let mut info = BY_HANDLE_FILE_INFORMATION::default();
    // SAFETY: the File keeps a valid handle open and info is writable for the call.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(info.nNumberOfLinks != 1)
}

#[cfg(not(any(unix, windows)))]
fn multiple_links(_file: &File, _metadata: &Metadata) -> io::Result<bool> {
    Ok(false)
}

/// Move a file on the same filesystem without replacing any destination.
/// Filesystems that do not support the atomic operation return an error; the
/// source is retained so the user can retry or choose another destination.
#[cfg(any(target_os = "linux", target_os = "android", target_os = "macos"))]
pub fn rename_no_replace(from: &Path, to: &Path) -> io::Result<()> {
    rustix::fs::renameat_with(
        rustix::fs::CWD,
        from,
        rustix::fs::CWD,
        to,
        rustix::fs::RenameFlags::NOREPLACE,
    )
    .map_err(Into::into)
}

#[cfg(windows)]
pub fn rename_no_replace(from: &Path, to: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::MoveFileExW;
    fn wide(path: &Path) -> io::Result<Vec<u16>> {
        let mut value: Vec<u16> = path.as_os_str().encode_wide().collect();
        if value.contains(&0) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "interior NUL"));
        }
        value.push(0);
        Ok(value)
    }
    let from = wide(from)?;
    let to = wide(to)?;
    // SAFETY: both strings are NUL-terminated and valid for the call. A zero
    // flags argument refuses to replace an existing destination.
    if unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), 0) } != 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_os = "macos", windows)))]
pub fn rename_no_replace(from: &Path, to: &Path) -> io::Result<()> {
    std::fs::hard_link(from, to)?;
    std::fs::remove_file(from)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn does_not_replace_existing_file() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        let target = dir.path().join("target");
        std::fs::write(&source, b"new").unwrap();
        std::fs::write(&target, b"old").unwrap();
        assert!(rename_no_replace(&source, &target).is_err());
        assert_eq!(std::fs::read(&source).unwrap(), b"new");
        assert_eq!(std::fs::read(&target).unwrap(), b"old");
        std::fs::remove_file(&target).unwrap();
        rename_no_replace(&source, &target).unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), b"new");
    }

    #[test]
    fn rejects_shared_storage_without_changing_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let sample = dir.path().join("sample");
        let partial = dir.path().join("partial");
        std::fs::write(&sample, b"original data").unwrap();
        std::fs::hard_link(&sample, &partial).unwrap();
        assert!(open_download_file(&partial, true).is_err());
        assert_eq!(std::fs::read(&sample).unwrap(), b"original data");
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symbolic_alias_but_accepts_a_plain_partial() {
        let dir = tempfile::tempdir().unwrap();
        let partial = dir.path().join("partial");
        let alias = dir.path().join("alias");
        let file = open_download_file(&partial, true).unwrap();
        file.set_len(8).unwrap();
        std::os::unix::fs::symlink(&partial, &alias).unwrap();
        assert!(open_download_file(&alias, false).is_err());
        assert_eq!(
            open_download_file(&partial, false)
                .unwrap()
                .metadata()
                .unwrap()
                .len(),
            8
        );
    }
}
