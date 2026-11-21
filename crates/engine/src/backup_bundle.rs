//! Multi-file backup building block. Callers must stop transfers and sanitize
//! metadata before exporting. This module does not alter the app's download list.
use crate::{
    backup_archive::{self, BackupRange, RestoreRange},
    naming,
    planner::Planner,
    state::{ResumeState, state_path},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
};

const MAX_MANIFEST: u64 = 64 * 1024 * 1024;
static NEXT_TEMP: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
fn invalid(s: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, s)
}

/// Items must remain unchanged until the export completes.
pub enum BackupItem<'a> {
    Completed(&'a Path),
    Partial(&'a ResumeState),
}

/// Create an archive beside its destination and publish it only after it has
/// been flushed. An existing destination is never replaced. The destination
/// filesystem must support hard links for this no-replace operation.
pub fn write_bundle_file(
    destination: &Path,
    metadata: serde_json::Value,
    items: &[BackupItem<'_>],
) -> io::Result<()> {
    write_bundle_file_with_progress(destination, metadata, items, |_| Ok(()))
}

/// Report archive bytes written; returning an error cancels the export and
/// removes its staging file without publishing a partial archive.
pub fn write_bundle_file_with_progress<F: FnMut(u64) -> io::Result<()>>(
    destination: &Path,
    metadata: serde_json::Value,
    items: &[BackupItem<'_>],
    mut progress: F,
) -> io::Result<()> {
    let parent = destination
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temporary = None;
    for _ in 0..100 {
        let serial = NEXT_TEMP.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let candidate = parent.join(format!(
            ".auralis-backup-{}-{serial}.tmp",
            std::process::id()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&candidate) {
            Ok(file) => {
                temporary = Some((candidate, file));
                break;
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    let (temporary_path, file) = temporary.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::AlreadyExists,
            "could not reserve backup staging file",
        )
    })?;
    let result = (|| {
        let mut writer = ProgressWriter {
            file,
            progress: &mut progress,
            written: 0,
        };
        write_bundle(&mut writer, metadata, items)?;
        writer.file.sync_all()?;
        drop(writer);
        fs::hard_link(&temporary_path, destination)?;
        Ok(())
    })();
    let _ = fs::remove_file(&temporary_path);
    result
}

struct ProgressWriter<'a, F> {
    file: File,
    progress: &'a mut F,
    written: u64,
}
impl<F: FnMut(u64) -> io::Result<()>> Write for ProgressWriter<'_, F> {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        let n = self.file.write(data)?;
        self.written = self.written.saturating_add(n as u64);
        if let Err(error) = (self.progress)(self.written) {
            // write_all retries Interrupted, which would repeat bytes already written.
            return Err(if error.kind() == io::ErrorKind::Interrupted {
                io::Error::other(error)
            } else {
                error
            });
        }
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}
#[derive(Serialize, Deserialize)]
struct Manifest {
    version: u32,
    metadata: serde_json::Value,
    items: Vec<Entry>,
}
#[derive(Serialize, Deserialize)]
#[serde(tag = "kind")]
enum Entry {
    Completed {
        id: String,
        length: u64,
    },
    Partial {
        state: ResumeState,
        ranges: Vec<RestoreRange>,
    },
}
/// The metadata belongs to the caller and must contain neither passwords nor
/// other secrets. URLs may themselves be sensitive and archives are not encrypted.
pub fn write_bundle<W: Write>(
    out: &mut W,
    metadata: serde_json::Value,
    items: &[BackupItem<'_>],
) -> io::Result<()> {
    let mut entries = Vec::with_capacity(items.len());
    let mut sources = Vec::new();
    for (i, item) in items.iter().enumerate() {
        match item {
            BackupItem::Completed(path) => {
                let stat = fs::symlink_metadata(path)?;
                if !stat.file_type().is_file() {
                    return Err(invalid("backup source is not a regular file"));
                }
                let id = format!("f{i}");
                sources.push(BackupRange {
                    id: id.clone(),
                    path: (*path).into(),
                    offset: 0,
                    length: stat.len(),
                });
                entries.push(Entry::Completed {
                    id,
                    length: stat.len(),
                });
            }
            BackupItem::Partial(state) => {
                if state.version != 1 || Planner::resume(state.size, 1, &state.segments).is_err() {
                    return Err(invalid("invalid saved ranges"));
                }
                let path = naming::part_path(&state.dest);
                let stat = fs::symlink_metadata(&path)?;
                if !stat.file_type().is_file() || stat.len() != state.size {
                    return Err(invalid("partial file has the wrong size"));
                }
                let report = state.verify_saved_blocks()?;
                if !report.damaged_ranges.is_empty() {
                    return Err(invalid("saved data does not match its checkpoint hashes"));
                }
                let mut ranges = Vec::new();
                for (j, segment) in state.segments.iter().enumerate() {
                    if segment.cursor == segment.start {
                        continue;
                    }
                    let id = format!("p{i}r{j}");
                    let length = segment.cursor - segment.start;
                    sources.push(BackupRange {
                        id: id.clone(),
                        path: path.clone(),
                        offset: segment.start,
                        length,
                    });
                    ranges.push(RestoreRange {
                        id,
                        offset: segment.start,
                        length,
                    });
                }
                let mut state = (*state).clone();
                state.dest = PathBuf::new();
                entries.push(Entry::Partial { state, ranges });
            }
        }
    }
    let manifest = serde_json::to_vec(&Manifest {
        version: 1,
        metadata,
        items: entries,
    })
    .map_err(io::Error::other)?;
    if manifest.len() as u64 > MAX_MANIFEST {
        return Err(invalid("backup metadata is too large"));
    }
    backup_archive::write_ranges_with_manifest(out, Some(&manifest), &sources)
}

pub struct RestoredItem {
    pub path: PathBuf,
    pub partial: bool,
    pub unhashed_bytes: u64,
}
pub struct RestoredBundle {
    pub metadata: serde_json::Value,
    pub items: Vec<RestoredItem>,
}

/// Restore to an entirely new directory. The returned numeric paths are safe
/// placeholders; the caller may offer to rename them without replacing files.
pub fn restore_bundle<R: Read>(input: &mut R, root: &Path) -> io::Result<RestoredBundle> {
    fs::create_dir(root)?;
    let result = restore_owned(input, root);
    if result.is_err() {
        let _ = fs::remove_dir_all(root);
    }
    result
}
fn restore_owned<R: Read>(input: &mut R, root: &Path) -> io::Result<RestoredBundle> {
    let staging = root.join("staging");
    let ids = backup_archive::restore_archive(input, &staging)?;
    let manifest_path = staging.join("manifest");
    if fs::metadata(&manifest_path)?.len() > MAX_MANIFEST {
        return Err(invalid("backup metadata is too large"));
    }
    let manifest: Manifest = serde_json::from_reader(File::open(manifest_path)?)
        .map_err(|_| invalid("invalid backup metadata"))?;
    if manifest.version != 1 {
        return Err(invalid("unsupported backup version"));
    }
    let mut expected = vec!["manifest".to_owned()];
    for (i, entry) in manifest.items.iter().enumerate() {
        match entry {
            Entry::Completed { id, length } => {
                if *id != format!("f{i}") || fs::metadata(staging.join(id))?.len() != *length {
                    return Err(invalid("invalid completed file"));
                }
                expected.push(id.clone());
            }
            Entry::Partial { state, ranges } => {
                if state.version != 1
                    || !state.dest.as_os_str().is_empty()
                    || Planner::resume(state.size, 1, &state.segments).is_err()
                {
                    return Err(invalid("invalid partial state"));
                }
                let required: Vec<_> = state
                    .segments
                    .iter()
                    .enumerate()
                    .filter(|(_, s)| s.start < s.cursor)
                    .map(|(j, s)| RestoreRange {
                        id: format!("p{i}r{j}"),
                        offset: s.start,
                        length: s.cursor - s.start,
                    })
                    .collect();
                if *ranges != required {
                    return Err(invalid("partial ranges do not match state"));
                }
                expected.extend(ranges.iter().map(|r| r.id.clone()));
            }
        }
    }
    let mut actual = ids;
    actual.sort();
    expected.sort();
    if actual != expected {
        return Err(invalid("backup entries do not match metadata"));
    }
    let mut restored = Vec::with_capacity(manifest.items.len());
    for (i, entry) in manifest.items.into_iter().enumerate() {
        let dest = root.join(format!("item-{i}"));
        match entry {
            Entry::Completed { id, .. } => {
                // root was created by this call and contains no caller-owned files.
                fs::rename(staging.join(id), &dest)?;
                restored.push(RestoredItem {
                    path: dest,
                    partial: false,
                    unhashed_bytes: 0,
                });
            }
            Entry::Partial { mut state, ranges } => {
                backup_archive::assemble_ranges(
                    &staging,
                    &naming::part_path(&dest),
                    state.size,
                    &ranges,
                )?;
                state.dest = dest.clone();
                let verification = state.verify_saved_blocks()?;
                if !verification.damaged_ranges.is_empty() {
                    return Err(invalid("saved data does not match its checkpoint hashes"));
                }
                let mut output = OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(state_path(&dest))?;
                serde_json::to_writer(&mut output, &state).map_err(io::Error::other)?;
                output.sync_all()?;
                restored.push(RestoredItem {
                    path: dest,
                    partial: true,
                    unhashed_bytes: verification.unhashed_bytes,
                });
            }
        }
    }
    fs::remove_dir_all(staging)?;
    Ok(RestoredBundle {
        metadata: manifest.metadata,
        items: restored,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::planner::SavedSegment;
    #[test]
    fn rejects_corrupted_partial_before_publishing_archive() {
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("partial");
        let part = naming::part_path(&dest);
        fs::write(&part, b"abcdefgh").unwrap();
        let url: url::Url = "https://example.org/file".parse().unwrap();
        let mut state = ResumeState::new(url.clone(), url, dest, 8, Default::default());
        state.segments = vec![SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        state.block_hashes =
            vec![crate::recovery::hash_saved_block(&mut File::open(&part).unwrap(), 0, 4).unwrap()];
        fs::write(&part, b"abXdxxxx").unwrap();
        let archive = dir.path().join("archive");
        assert!(
            write_bundle_file(
                &archive,
                serde_json::Value::Null,
                &[BackupItem::Partial(&state)]
            )
            .is_err()
        );
        assert!(!archive.exists());
        assert_eq!(fs::read(&part).unwrap(), b"abXdxxxx");
    }
    #[test]
    fn archive_file_is_only_published_on_success_and_never_overwrites() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        let output = dir.path().join("backup");
        fs::write(&source, b"data").unwrap();
        fs::write(&output, b"existing").unwrap();
        assert!(
            write_bundle_file(
                &output,
                serde_json::Value::Null,
                &[BackupItem::Completed(&source)]
            )
            .is_err()
        );
        assert_eq!(fs::read(&output).unwrap(), b"existing");
        let missing = dir.path().join("missing");
        let failed = dir.path().join("failed");
        assert!(
            write_bundle_file(
                &failed,
                serde_json::Value::Null,
                &[BackupItem::Completed(&missing)]
            )
            .is_err()
        );
        assert!(!failed.exists());
        let good = dir.path().join("good");
        write_bundle_file(
            &good,
            serde_json::Value::Null,
            &[BackupItem::Completed(&source)],
        )
        .unwrap();
        let restored =
            restore_bundle(&mut File::open(good).unwrap(), &dir.path().join("restore")).unwrap();
        assert_eq!(fs::read(&restored.items[0].path).unwrap(), b"data");
        assert!(fs::read_dir(dir.path()).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".auralis-backup-")
        }));
    }
    #[test]
    fn cancellation_removes_temporary_archive_and_reports_progress() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        fs::write(&source, vec![7u8; 200_000]).unwrap();
        let target = dir.path().join("backup");
        let mut last = 0;
        let result = write_bundle_file_with_progress(
            &target,
            serde_json::Value::Null,
            &[BackupItem::Completed(&source)],
            |written| {
                assert!(written >= last);
                last = written;
                if written > 65_536 {
                    Err(io::Error::new(io::ErrorKind::Interrupted, "cancelled"))
                } else {
                    Ok(())
                }
            },
        );
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::Other);
        assert!(last > 65_536);
        assert!(!target.exists());
        assert!(fs::read_dir(dir.path()).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".auralis-backup-")
        }));
        assert_eq!(fs::metadata(source).unwrap().len(), 200_000);
    }
    #[test]
    fn refuses_source_modified_during_export_even_if_size_is_unchanged() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        fs::write(&source, vec![7u8; 200_000]).unwrap();
        let target = dir.path().join("backup");
        let mut changed = false;
        let result = write_bundle_file_with_progress(
            &target,
            serde_json::Value::Null,
            &[BackupItem::Completed(&source)],
            |written| {
                if written > 65_536 && !changed {
                    fs::write(&source, vec![8u8; 200_000])?;
                    let file = OpenOptions::new().write(true).open(&source)?;
                    let old = std::time::UNIX_EPOCH + std::time::Duration::from_secs(1_000_000_000);
                    file.set_times(std::fs::FileTimes::new().set_modified(old))?;
                    changed = true;
                }
                Ok(())
            },
        );
        assert!(changed);
        assert!(result.is_err());
        assert!(!target.exists());
        assert_eq!(fs::read(source).unwrap(), vec![8u8; 200_000]);
    }
    #[test]
    fn completed_and_partial_roundtrip_without_replacing_existing_data() {
        let dir = tempfile::tempdir().unwrap();
        let complete = dir.path().join("complete");
        fs::write(&complete, b"finished download").unwrap();
        let original = dir.path().join("partial");
        fs::write(naming::part_path(&original), b"12345678").unwrap();
        let url: url::Url = "https://example.org/file".parse().unwrap();
        let mut state = ResumeState::new(url.clone(), url, original, 8, Default::default());
        state.segments = vec![SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        let mut bytes = Vec::new();
        write_bundle(
            &mut bytes,
            serde_json::json!({"title":"example"}),
            &[
                BackupItem::Completed(&complete),
                BackupItem::Partial(&state),
            ],
        )
        .unwrap();
        let root = dir.path().join("restore");
        let result = restore_bundle(&mut &bytes[..], &root).unwrap();
        assert_eq!(result.metadata["title"], "example");
        assert_eq!(
            fs::read(&result.items[0].path).unwrap(),
            b"finished download"
        );
        assert!(!result.items[0].partial);
        assert!(result.items[1].partial);
        assert_eq!(result.items[1].unhashed_bytes, 4);
        let restored = ResumeState::load(&state_path(&result.items[1].path)).unwrap();
        assert_eq!(restored.downloaded(), 4);
        assert_eq!(
            &fs::read(naming::part_path(&result.items[1].path)).unwrap()[..4],
            b"1234"
        );
        assert!(restore_bundle(&mut &bytes[..], &root).is_err());
        assert_eq!(
            fs::read(&result.items[0].path).unwrap(),
            b"finished download"
        );
    }
    #[test]
    fn corrupt_archive_removes_new_restore_without_touching_source() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        fs::write(&source, b"content").unwrap();
        let mut bytes = Vec::new();
        write_bundle(
            &mut bytes,
            serde_json::Value::Null,
            &[BackupItem::Completed(&source)],
        )
        .unwrap();
        let last = bytes.len() - 3;
        bytes[last] ^= 1;
        let root = dir.path().join("restore");
        assert!(restore_bundle(&mut &bytes[..], &root).is_err());
        assert!(!root.exists());
        assert_eq!(fs::read(source).unwrap(), b"content");
    }
}
