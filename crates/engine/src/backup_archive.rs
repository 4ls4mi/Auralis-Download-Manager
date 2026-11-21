//! Streaming backup container. Restores only to a newly created staging directory.
//! Application-specific metadata, paths and final placement are handled by its caller.
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

const MAGIC: &[u8; 8] = b"AURBK001";
const BUFFER: usize = 64 * 1024;
const MAX_ENTRIES: usize = 1_000_000;
const MAX_MANIFEST: u64 = 64 * 1024 * 1024;
fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
}

/// A portion of a source file to preserve. A manifest owned by the caller must
/// record each range's original file and offset; archive IDs are not paths.
#[derive(Clone, Debug)]
pub struct BackupRange {
    pub id: String,
    pub path: PathBuf,
    pub offset: u64,
    pub length: u64,
}

/// Create a stream from whole, uniquely named regular files.
pub fn write_archive<W: Write>(out: &mut W, entries: &[(String, PathBuf)]) -> io::Result<()> {
    let mut ranges = Vec::with_capacity(entries.len());
    for (id, path) in entries {
        let metadata = fs::symlink_metadata(path)?;
        if !metadata.file_type().is_file() {
            return Err(invalid("backup source is not a regular file"));
        }
        ranges.push(BackupRange {
            id: id.clone(),
            path: path.clone(),
            offset: 0,
            length: metadata.len(),
        });
    }
    write_ranges(out, &ranges)
}

/// Stream selected file ranges. This lets callers save only the downloaded
/// portions of a sparse partial file. The caller must pause writes and record a
/// manifest mapping the IDs back to offsets before invoking this function.
pub fn write_ranges<W: Write>(out: &mut W, entries: &[BackupRange]) -> io::Result<()> {
    write_ranges_with_manifest(out, None, entries)
}

pub(crate) fn write_ranges_with_manifest<W: Write>(
    out: &mut W,
    manifest: Option<&[u8]>,
    entries: &[BackupRange],
) -> io::Result<()> {
    if entries.len() + usize::from(manifest.is_some()) > MAX_ENTRIES {
        return Err(invalid("too many backup entries"));
    }
    if manifest.is_some_and(|data| data.len() as u64 > MAX_MANIFEST) {
        return Err(invalid("backup metadata is too large"));
    }
    let mut names = std::collections::HashSet::new();
    if manifest.is_some() {
        names.insert("manifest");
    }
    for entry in entries {
        if !valid_id(&entry.id) || !names.insert(entry.id.as_str()) {
            return Err(invalid("invalid or duplicate backup identifier"));
        }
        let metadata = fs::symlink_metadata(&entry.path)?;
        if !metadata.file_type().is_file() {
            return Err(invalid("backup source is not a regular file"));
        }
        if entry
            .offset
            .checked_add(entry.length)
            .is_none_or(|end| end > metadata.len())
        {
            return Err(invalid("backup range exceeds source file"));
        }
    }
    out.write_all(MAGIC)?;
    if let Some(data) = manifest {
        out.write_all(&(8u16).to_le_bytes())?;
        out.write_all(b"manifest")?;
        out.write_all(&(data.len() as u64).to_le_bytes())?;
        out.write_all(data)?;
        out.write_all(&Sha256::digest(data))?;
    }
    let mut buffer = [0u8; BUFFER];
    for entry in entries {
        let mut source = File::open(&entry.path)?;
        // A best-effort additional check; callers must still prevent writes,
        // since a filesystem may not expose a precise modification timestamp.
        let original_metadata = source.metadata()?;
        let original_size = original_metadata.len();
        let original_modified = original_metadata.modified().ok();
        if entry
            .offset
            .checked_add(entry.length)
            .is_none_or(|end| end > original_size)
        {
            return Err(invalid("backup source changed size"));
        }
        source.seek(SeekFrom::Start(entry.offset))?;
        out.write_all(&(entry.id.len() as u16).to_le_bytes())?;
        out.write_all(entry.id.as_bytes())?;
        out.write_all(&entry.length.to_le_bytes())?;
        let mut left = entry.length;
        let mut hash = Sha256::new();
        while left > 0 {
            let n = left.min(BUFFER as u64) as usize;
            source.read_exact(&mut buffer[..n])?;
            out.write_all(&buffer[..n])?;
            hash.update(&buffer[..n]);
            left -= n as u64;
        }
        let after = source.metadata()?;
        if after.len() != original_size
            || original_modified
                .zip(after.modified().ok())
                .is_some_and(|(before, after)| before != after)
        {
            return Err(invalid("backup source changed while it was being copied"));
        }
        out.write_all(&hash.finalize())?;
    }
    out.write_all(&0u16.to_le_bytes())?;
    Ok(())
}

/// A verified archive entry and the position it occupied in a partial file.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct RestoreRange {
    pub id: String,
    pub offset: u64,
    pub length: u64,
}

/// Assemble verified range entries into a newly created partial file. Unwritten
/// gaps remain absent from the saved range map; callers must restore that map
/// separately and must not treat the zero-filled holes as downloaded data.
pub fn assemble_ranges(
    staging: &Path,
    output: &Path,
    size: u64,
    ranges: &[RestoreRange],
) -> io::Result<()> {
    let mut ordered: Vec<&RestoreRange> = ranges.iter().collect();
    ordered.sort_unstable_by_key(|range| range.offset);
    let mut previous_end = 0;
    let mut ids = std::collections::HashSet::new();
    for range in &ordered {
        let end = range
            .offset
            .checked_add(range.length)
            .ok_or_else(|| invalid("restored range overflow"))?;
        if !valid_id(&range.id)
            || !ids.insert(&range.id)
            || range.length == 0
            || range.offset < previous_end
            || end > size
        {
            return Err(invalid("invalid or overlapping restored range"));
        }
        let metadata = fs::symlink_metadata(staging.join(&range.id))?;
        if !metadata.file_type().is_file() || metadata.len() != range.length {
            return Err(invalid("restored range has the wrong size"));
        }
        previous_end = end;
    }
    let mut target = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(output)?;
    let result = (|| -> io::Result<()> {
        // Avoid allocating empty holes on filesystems that support sparse files.
        crate::sparse::set(&target, true);
        target.set_len(size)?;
        for range in ordered {
            let source = File::open(staging.join(&range.id))?;
            target.seek(SeekFrom::Start(range.offset))?;
            let copied = io::copy(&mut source.take(range.length), &mut target)?;
            if copied != range.length {
                return Err(invalid("restored range is truncated"));
            }
        }
        target.sync_all()?;
        Ok(())
    })();
    drop(target);
    if result.is_err() {
        let _ = fs::remove_file(output);
    }
    result
}

/// Verify and extract to a new staging directory. Existing directories are never
/// reused. On failure, remove only files created inside this staging directory.
pub fn restore_archive<R: Read>(input: &mut R, staging: &Path) -> io::Result<Vec<String>> {
    fs::create_dir(staging)?;
    let result = restore_inner(input, staging);
    if result.is_err() {
        let _ = fs::remove_dir_all(staging);
    }
    result
}
fn restore_inner<R: Read>(input: &mut R, staging: &Path) -> io::Result<Vec<String>> {
    let mut magic = [0u8; 8];
    input.read_exact(&mut magic)?;
    if &magic != MAGIC {
        return Err(invalid("not an Auralis backup"));
    }
    let mut ids = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut buffer = [0u8; BUFFER];
    loop {
        let mut n = [0u8; 2];
        input.read_exact(&mut n)?;
        let n = u16::from_le_bytes(n) as usize;
        if n == 0 {
            let mut extra = [0u8; 1];
            if input.read(&mut extra)? != 0 {
                return Err(invalid("unexpected trailing backup data"));
            }
            return Ok(ids);
        }
        if n > 128 || ids.len() >= MAX_ENTRIES {
            return Err(invalid("invalid backup entry"));
        }
        let mut name = vec![0u8; n];
        input.read_exact(&mut name)?;
        let id = std::str::from_utf8(&name).map_err(|_| invalid("invalid backup identifier"))?;
        if !valid_id(id) || !seen.insert(id.to_owned()) {
            return Err(invalid("invalid or duplicate backup identifier"));
        }
        let mut len = [0u8; 8];
        input.read_exact(&mut len)?;
        let mut left = u64::from_le_bytes(len);
        if id == "manifest" && left > MAX_MANIFEST {
            return Err(invalid("backup metadata is too large"));
        }
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(staging.join(id))?;
        let mut hash = Sha256::new();
        while left > 0 {
            let n = left.min(BUFFER as u64) as usize;
            input.read_exact(&mut buffer[..n])?;
            file.write_all(&buffer[..n])?;
            hash.update(&buffer[..n]);
            left -= n as u64;
        }
        let mut expected = [0u8; 32];
        input.read_exact(&mut expected)?;
        if hash.finalize().as_slice() != expected {
            return Err(invalid("backup entry checksum mismatch"));
        }
        file.sync_all()?;
        ids.push(id.to_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_oversized_manifest_before_extracting_it() {
        let root = tempfile::tempdir().unwrap();
        let mut archive = Vec::new();
        archive.extend_from_slice(MAGIC);
        archive.extend_from_slice(&8u16.to_le_bytes());
        archive.extend_from_slice(b"manifest");
        archive.extend_from_slice(&(MAX_MANIFEST + 1).to_le_bytes());
        let staging = root.path().join("stage");
        let error = restore_archive(&mut &archive[..], &staging).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(!staging.exists());
    }
    #[test]
    fn streams_roundtrip_and_rejects_corruption_without_touching_existing_files() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source");
        let data = vec![42u8; BUFFER * 3 + 13];
        fs::write(&source, &data).unwrap();
        let mut archive = Vec::new();
        write_archive(&mut archive, &[("item-1".into(), source.clone())]).unwrap();
        let staging = root.path().join("restore");
        assert_eq!(
            restore_archive(&mut &archive[..], &staging).unwrap(),
            vec!["item-1"]
        );
        assert_eq!(fs::read(staging.join("item-1")).unwrap(), data);
        assert!(restore_archive(&mut &archive[..], &staging).is_err());
        let mut corrupt = archive.clone();
        corrupt[40] ^= 1;
        let failed = root.path().join("failed");
        assert!(restore_archive(&mut &corrupt[..], &failed).is_err());
        assert!(!failed.exists());
        assert_eq!(fs::read(&source).unwrap(), data);
    }
    #[test]
    fn stores_only_selected_partial_ranges_and_rejects_out_of_bounds() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("sparse");
        let mut f = File::create(&source).unwrap();
        f.set_len(32 * 1024 * 1024).unwrap();
        f.seek(SeekFrom::Start(5)).unwrap();
        f.write_all(b"abc").unwrap();
        f.seek(SeekFrom::Start(24 * 1024 * 1024)).unwrap();
        f.write_all(b"xyz").unwrap();
        drop(f);
        let entries = vec![
            BackupRange {
                id: "one".into(),
                path: source.clone(),
                offset: 5,
                length: 3,
            },
            BackupRange {
                id: "two".into(),
                path: source.clone(),
                offset: 24 * 1024 * 1024,
                length: 3,
            },
        ];
        let mut archive = Vec::new();
        write_ranges(&mut archive, &entries).unwrap();
        assert!(archive.len() < 256, "sparse gaps must not be copied");
        let staging = root.path().join("ranges");
        restore_archive(&mut &archive[..], &staging).unwrap();
        assert_eq!(fs::read(staging.join("one")).unwrap(), b"abc");
        assert_eq!(fs::read(staging.join("two")).unwrap(), b"xyz");
        let assembled = root.path().join("reconstructed");
        let restored = [
            RestoreRange {
                id: "one".into(),
                offset: 5,
                length: 3,
            },
            RestoreRange {
                id: "two".into(),
                offset: 24 * 1024 * 1024,
                length: 3,
            },
        ];
        assemble_ranges(&staging, &assembled, 32 * 1024 * 1024, &restored).unwrap();
        let mut rebuilt = File::open(&assembled).unwrap();
        let mut buf = [0u8; 3];
        rebuilt.seek(SeekFrom::Start(5)).unwrap();
        rebuilt.read_exact(&mut buf).unwrap();
        assert_eq!(&buf, b"abc");
        rebuilt.seek(SeekFrom::Start(24 * 1024 * 1024)).unwrap();
        rebuilt.read_exact(&mut buf).unwrap();
        assert_eq!(&buf, b"xyz");
        assert!(
            assemble_ranges(&staging, &assembled, 32 * 1024 * 1024, &restored).is_err(),
            "must not replace existing files"
        );
        let overlap = [
            RestoreRange {
                id: "one".into(),
                offset: 5,
                length: 3,
            },
            RestoreRange {
                id: "two".into(),
                offset: 6,
                length: 3,
            },
        ];
        assert!(assemble_ranges(&staging, &root.path().join("bad"), 100, &overlap).is_err());

        let bad = BackupRange {
            id: "bad".into(),
            path: source,
            offset: u64::MAX,
            length: 2,
        };
        assert!(write_ranges(&mut Vec::new(), &[bad]).is_err());
    }

    #[test]
    fn refuses_path_traversal_and_duplicate_ids() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("source");
        fs::write(&file, b"data").unwrap();
        assert!(write_archive(&mut Vec::new(), &[("../bad".into(), file.clone())]).is_err());
        assert!(
            write_archive(
                &mut Vec::new(),
                &[("same".into(), file.clone()), ("same".into(), file)]
            )
            .is_err()
        );
    }
}
