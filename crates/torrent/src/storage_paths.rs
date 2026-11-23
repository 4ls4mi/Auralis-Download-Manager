//! Validate the on-disk paths that the torrent library may open.

use std::io;
use std::path::Path;

use mdm_engine::safe_move::{is_link_or_reparse, open_download_file};

use crate::{FileEntry, check_relative_path};

fn invalid(path: &Path) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        format!(
            "torrent storage must use plain files and directories: {}",
            path.display()
        ),
    )
}

/// Covers all files, including unselected files that share pieces with the selected ones.
pub(crate) fn validate(root: &Path, files: &[FileEntry]) -> io::Result<()> {
    match std::fs::symlink_metadata(root) {
        Ok(metadata) if !metadata.is_dir() || is_link_or_reparse(&metadata) => {
            return Err(invalid(root));
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    for entry in files.iter().filter(|entry| !entry.padding) {
        check_relative_path(&entry.path).map_err(|_| invalid(&entry.path))?;
        let mut current = root.to_path_buf();
        let mut parts = entry.path.components().peekable();
        while let Some(part) = parts.next() {
            current.push(part);
            let metadata = match std::fs::symlink_metadata(&current) {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == io::ErrorKind::NotFound => break,
                Err(error) => return Err(error),
            };
            if is_link_or_reparse(&metadata) {
                return Err(invalid(&current));
            }
            if parts.peek().is_some() {
                if !metadata.is_dir() {
                    return Err(invalid(&current));
                }
            } else {
                // Open without truncating and verify there is no hard-link alias.
                open_download_file(&current, false)?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(path: &str) -> FileEntry {
        FileEntry {
            path: path.into(),
            size: 1,
            padding: false,
        }
    }

    #[test]
    fn accepts_resume_and_rejects_shared_file_storage() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("saved.bin");
        std::fs::write(&file, b"x").unwrap();
        assert!(validate(root.path(), &[entry("saved.bin"), entry("new.bin")]).is_ok());
        std::fs::hard_link(&file, root.path().join("alias.bin")).unwrap();
        assert!(validate(root.path(), &[entry("alias.bin")]).is_err());
        assert_eq!(std::fs::read(&file).unwrap(), b"x");
    }

    #[cfg(unix)]
    #[test]
    fn refuses_linked_directories_below_the_output_root() {
        let root = tempfile::tempdir().unwrap();
        let other = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink(other.path(), root.path().join("subfolder")).unwrap();
        assert!(validate(root.path(), &[entry("subfolder/file.bin")]).is_err());
        assert_eq!(std::fs::read_dir(other.path()).unwrap().count(), 0);
    }
}
