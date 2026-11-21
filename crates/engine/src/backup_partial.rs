//! Portable, staged backup of one stopped ordinary download's committed ranges.
//! This is an engine building block; the app must coordinate a consistent list
//! and settings snapshot, pause downloads, and choose new destination paths.
use crate::{
    backup_archive::{self, BackupRange, RestoreRange},
    naming,
    planner::Planner,
    recovery::CheckpointVerification,
    state::{ResumeState, state_path},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::Path,
};
const MAX_MANIFEST: u64 = 64 * 1024 * 1024;
fn invalid(text: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, text)
}
#[derive(Serialize, Deserialize)]
struct Manifest {
    version: u32,
    state: ResumeState,
    ranges: Vec<RestoreRange>,
}

/// Write a stopped download's saved ranges and resume metadata. The caller must
/// ensure no process is writing to it until the backup has completed.
pub fn write_partial<W: Write>(out: &mut W, state: &ResumeState) -> io::Result<()> {
    if Planner::resume(state.size, 1, &state.segments).is_err() {
        return Err(invalid("invalid saved ranges"));
    }
    let path = naming::part_path(&state.dest);
    if fs::symlink_metadata(&path)?.len() != state.size {
        return Err(invalid("partial file has the wrong size"));
    }
    let mut source = Vec::new();
    let mut ranges = Vec::new();
    for (i, s) in state.segments.iter().enumerate() {
        if s.cursor == s.start {
            continue;
        }
        let id = format!("r{i}");
        let length = s.cursor - s.start;
        source.push(BackupRange {
            id: id.clone(),
            path: path.clone(),
            offset: s.start,
            length,
        });
        ranges.push(RestoreRange {
            id,
            offset: s.start,
            length,
        });
    }
    let mut portable = state.clone();
    portable.dest = Default::default();
    let manifest = serde_json::to_vec(&Manifest {
        version: 1,
        state: portable,
        ranges,
    })
    .map_err(io::Error::other)?;
    if manifest.len() as u64 > MAX_MANIFEST {
        return Err(invalid("partial backup metadata is too large"));
    }
    backup_archive::write_ranges_with_manifest(out, Some(&manifest), &source)
}

/// Restore into a new destination. Files and saved state that already exist are
/// never overwritten. The input archive remains available if validation fails.
pub fn restore_partial<R: Read>(
    input: &mut R,
    staging: &Path,
    dest: &Path,
) -> io::Result<CheckpointVerification> {
    let ids = backup_archive::restore_archive(input, staging)?;
    let result = (|| -> io::Result<CheckpointVerification> {
        let manifest_path = staging.join("manifest");
        if fs::metadata(&manifest_path)?.len() > MAX_MANIFEST {
            return Err(invalid("partial backup metadata is too large"));
        }
        let mut manifest: Manifest = serde_json::from_reader(File::open(&manifest_path)?)
            .map_err(|_| invalid("invalid partial backup metadata"))?;
        if manifest.version != 1
            || !manifest.state.dest.as_os_str().is_empty()
            || Planner::resume(manifest.state.size, 1, &manifest.state.segments).is_err()
        {
            return Err(invalid("invalid partial backup state"));
        }
        let expected: Vec<_> = manifest
            .state
            .segments
            .iter()
            .enumerate()
            .filter(|(_, s)| s.start < s.cursor)
            .map(|(i, s)| RestoreRange {
                id: format!("r{i}"),
                offset: s.start,
                length: s.cursor - s.start,
            })
            .collect();
        if manifest.ranges != expected
            || ids.len() != expected.len() + 1
            || !ids.iter().any(|id| id == "manifest")
            || expected.iter().any(|range| !ids.contains(&range.id))
        {
            return Err(invalid("partial backup ranges do not match saved state"));
        }
        if fs::symlink_metadata(dest).is_ok() {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "destination already exists",
            ));
        }
        manifest.state.dest = dest.to_owned();
        let state_file = state_path(dest);
        let part = naming::part_path(dest);
        let mut state_out = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&state_file)?;
        let assembled =
            backup_archive::assemble_ranges(staging, &part, manifest.state.size, &manifest.ranges);
        if let Err(error) = assembled {
            drop(state_out);
            let _ = fs::remove_file(&state_file);
            return Err(error);
        }
        let written = (|| -> io::Result<CheckpointVerification> {
            let report = manifest.state.verify_saved_blocks()?;
            if !report.damaged_ranges.is_empty() {
                return Err(invalid("saved data does not match its checkpoint hashes"));
            }
            serde_json::to_writer(&mut state_out, &manifest.state).map_err(io::Error::other)?;
            state_out.sync_all()?;
            Ok(report)
        })();
        drop(state_out);
        if written.is_err() {
            let _ = fs::remove_file(&part);
            let _ = fs::remove_file(&state_file);
        }
        written
    })();
    let _ = fs::remove_dir_all(staging);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::planner::SavedSegment;
    use std::io::{Seek, SeekFrom};
    #[test]
    fn restores_old_unhashed_ranges_without_claiming_verification() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("old.bin");
        let part = naming::part_path(&source);
        fs::write(&part, b"abcdefgh").unwrap();
        let url: url::Url = "https://example.com/file".parse().unwrap();
        let mut state = ResumeState::new(url.clone(), url, source, 8, Default::default());
        state.segments = vec![SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        let mut archive = Vec::new();
        write_partial(&mut archive, &state).unwrap();
        let target = dir.path().join("new.bin");
        let report =
            restore_partial(&mut &archive[..], &dir.path().join("stage-old"), &target).unwrap();
        assert_eq!(report.checked_bytes, 0);
        assert_eq!(report.unhashed_bytes, 4);
        assert!(report.damaged_ranges.is_empty());
        assert_eq!(
            ResumeState::load(&state_path(&target))
                .unwrap()
                .downloaded(),
            4
        );
    }

    #[test]
    fn rejects_mismatched_range_manifest_without_creating_a_file() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("part");
        fs::write(&src, b"abcdefgh").unwrap();
        let url: url::Url = "https://example.com/file".parse().unwrap();
        let mut state =
            ResumeState::new(url.clone(), url, Default::default(), 8, Default::default());
        state.segments = vec![SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        let manifest = serde_json::to_vec(&Manifest {
            version: 1,
            state,
            ranges: vec![RestoreRange {
                id: "r0".into(),
                offset: 4,
                length: 4,
            }],
        })
        .unwrap();
        let mut archive = Vec::new();
        backup_archive::write_ranges_with_manifest(
            &mut archive,
            Some(&manifest),
            &[BackupRange {
                id: "r0".into(),
                path: src,
                offset: 4,
                length: 4,
            }],
        )
        .unwrap();
        let target = dir.path().join("target.bin");
        let staging = dir.path().join("stage-invalid");
        assert!(restore_partial(&mut &archive[..], &staging, &target).is_err());
        assert!(!staging.exists());
        assert!(!naming::part_path(&target).exists());
        assert!(!state_path(&target).exists());
    }

    #[test]
    fn refuses_changed_saved_data_without_creating_destination_files() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.bin");
        let mut part = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(naming::part_path(&source))
            .unwrap();
        part.write_all(b"abcdefgh").unwrap();
        let url: url::Url = "https://example.com/file".parse().unwrap();
        let mut state = ResumeState::new(url.clone(), url, source.clone(), 8, Default::default());
        state
            .save(
                &state_path(&source),
                vec![SavedSegment {
                    start: 0,
                    cursor: 4,
                    end: 8,
                }],
                &part,
            )
            .unwrap();
        part.seek(SeekFrom::Start(1)).unwrap();
        part.write_all(b"X").unwrap();
        part.sync_all().unwrap();
        drop(part);
        let mut archive = Vec::new();
        write_partial(&mut archive, &state).unwrap();
        let target = dir.path().join("target.bin");
        let staging = dir.path().join("stage-corrupt");
        assert!(restore_partial(&mut &archive[..], &staging, &target).is_err());
        assert!(!staging.exists());
        assert!(!naming::part_path(&target).exists());
        assert!(!state_path(&target).exists());
        assert!(naming::part_path(&source).exists());
    }

    #[test]
    fn restores_ranges_and_resume_state_without_overwriting() {
        let dir = tempfile::tempdir().unwrap();
        let old = dir.path().join("old.bin");
        let part = naming::part_path(&old);
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&part)
            .unwrap();
        file.set_len(20).unwrap();
        file.write_all(b"abcdef").unwrap();
        file.seek(SeekFrom::Start(12)).unwrap();
        file.write_all(b"xyz").unwrap();
        let url: url::Url = "https://example.com/file".parse().unwrap();
        let mut state = ResumeState::new(url.clone(), url, old, 20, Default::default());
        let segments = vec![
            SavedSegment {
                start: 0,
                cursor: 6,
                end: 12,
            },
            SavedSegment {
                start: 12,
                cursor: 15,
                end: 20,
            },
        ];
        state
            .save(&state_path(&state.dest.clone()), segments, &file)
            .unwrap();
        drop(file);
        let mut archive = Vec::new();
        write_partial(&mut archive, &state).unwrap();
        let dest = dir.path().join("new.bin");
        let staging = dir.path().join("stage");
        let report = restore_partial(&mut &archive[..], &staging, &dest).unwrap();
        assert_eq!(report.checked_bytes, 9);
        assert!(report.damaged_ranges.is_empty());
        let restored = ResumeState::load(&state_path(&dest)).unwrap();
        assert_eq!(restored.dest, dest);
        assert_eq!(restored.downloaded(), 9);
        assert_eq!(restored.segments, state.segments);
        let bytes = fs::read(naming::part_path(&dest)).unwrap();
        assert_eq!(&bytes[..6], b"abcdef");
        assert_eq!(&bytes[12..15], b"xyz");
        assert!(!staging.exists());
        let before = fs::read(naming::part_path(&dest)).unwrap();
        assert!(restore_partial(&mut &archive[..], &staging, &dest).is_err());
        assert_eq!(fs::read(naming::part_path(&dest)).unwrap(), before);
    }
}
