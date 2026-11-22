use super::*;
use std::collections::{HashMap, HashSet};

#[derive(serde::Serialize, serde::Deserialize)]
pub(super) struct TorrentRecord {
    pub metadata: usize,
    // The row may represent the containing folder or one file (mixed recovery).
    pub destination: Vec<String>,
    pub files: Vec<TorrentFile>,
    pub renamed_file: Option<Vec<String>>,
}
#[derive(serde::Serialize, serde::Deserialize)]
pub(super) struct TorrentFile {
    pub number: usize,
    pub reference: FileReference,
}

pub(crate) struct RestoredTorrent {
    pub hash: String,
    pub bytes: Vec<u8>,
    pub renamed_file: Option<PathBuf>,
}

fn metadata(bytes: &[u8], hash: &str) -> Result<mdm_torrent::Meta, String> {
    let data = mdm_torrent::metadata_for_backup(bytes).map_err(|e| e.to_string())?;
    if data.info_hash != hash {
        return Err("Saved torrent metadata does not match the download.".into());
    }
    Ok(data)
}

fn layout(
    torrent: &crate::torrents::TorrentSpec,
    meta: &mdm_torrent::Meta,
    rename: Option<&[String]>,
) -> Result<(Vec<Vec<String>>, HashSet<usize>), String> {
    let effective = meta.files.iter().filter(|file| !file.padding).count();
    if rename.is_some() && effective != 1 {
        return Err("Only a single-file torrent can have a renamed file.".into());
    }
    let paths: Vec<_> = meta
        .files
        .iter()
        .map(|file| {
            if !file.padding
                && let Some(rename) = rename
            {
                checked_components(rename)?;
                return Ok(rename.to_vec());
            }
            relative_components(&file.path)
        })
        .collect::<Result<_, _>>()?;
    let mut unique = HashSet::new();
    if paths.iter().any(|path| !unique.insert(path_key(path))) {
        return Err("The torrent has file names that conflict on the restore filesystem.".into());
    }
    let mut wanted = HashSet::new();
    if let Some(files) = &torrent.files {
        if files.iter().any(|&index| {
            meta.files.get(index).is_none_or(|file| file.padding) || !wanted.insert(index)
        }) {
            return Err("The torrent file selection is invalid.".into());
        }
    } else {
        wanted.extend(
            meta.files
                .iter()
                .enumerate()
                .filter(|(_, f)| !f.padding)
                .map(|(i, _)| i),
        );
    }
    if wanted.is_empty() {
        return Err("The torrent has no selected files.".into());
    }
    Ok((paths, wanted))
}

pub(super) fn gather(
    item: &Item,
    contents: &mut Vec<Content>,
    metadata_path: &Path,
) -> Result<TorrentRecord, String> {
    let torrent = item.torrent.as_ref().ok_or("Missing torrent settings.")?;
    if file_length(metadata_path)?.is_none() {
        return Err("The torrent metadata file is missing.".into());
    }
    let bytes = mdm_torrent::read_file(metadata_path).map_err(|e| e.to_string())?;
    let meta = metadata(&bytes, &torrent.hash)?;
    let destination = beneath(&torrent.folder, &item.dest, true)?;
    let original = mdm_torrent::rename_plugin::original_single_file_path(&bytes);
    let rename = original
        .as_ref()
        .filter(|original| !destination.is_empty() && torrent.folder.join(original) != item.dest)
        .map(|_| destination.clone());
    let (paths, wanted) = layout(torrent, &meta, rename.as_deref())?;
    if !destination.is_empty() && !wanted.iter().any(|&i| paths[i] == destination) {
        return Err("The torrent destination does not match a selected file.".into());
    }
    let metadata = push_content(contents, Content::Completed(metadata_path.to_owned()));
    let mut files = Vec::new();
    let mut selected_bytes = 0u64;
    for (number, relative) in paths.into_iter().enumerate() {
        let entry = &meta.files[number];
        if entry.padding {
            continue;
        }
        let source = source_path(&torrent.folder, &relative)?;
        let Some(length) = file_length(&source)? else {
            if item.status == Status::Complete && wanted.contains(&number) {
                return Err(format!(
                    "A completed torrent file is unavailable: {}",
                    source.display()
                ));
            }
            continue;
        };
        if length > entry.size
            || item.status == Status::Complete && wanted.contains(&number) && length != entry.size
        {
            return Err(format!(
                "A torrent file has an unexpected size: {}",
                source.display()
            ));
        }
        if wanted.contains(&number) {
            selected_bytes = selected_bytes
                .checked_add(length)
                .ok_or("Torrent downloaded data is too large.")?;
        }
        // An unselected neighboring file may contain bytes of a selected piece.
        let reference = FileReference {
            relative,
            index: push_content(contents, Content::Completed(source)),
        };
        files.push(TorrentFile { number, reference });
    }
    if item.downloaded > selected_bytes {
        return Err("Saved torrent data is missing.".into());
    }
    Ok(TorrentRecord {
        metadata,
        destination,
        files,
        renamed_file: rename,
    })
}

pub(super) fn validate(
    item: &Item,
    record: &TorrentRecord,
    bundle: &backup_bundle::RestoredBundle,
    seen: &mut HashSet<usize>,
) -> Result<RestoredTorrent, String> {
    let torrent = item.torrent.as_ref().ok_or("Missing torrent settings.")?;
    if !torrent.folder.as_os_str().is_empty() {
        return Err("Unsafe torrent folder in backup.".into());
    }
    let archive = use_content(bundle, seen, record.metadata, false)?;
    let bytes = mdm_torrent::read_file(&archive.path).map_err(|e| e.to_string())?;
    let meta = metadata(&bytes, &torrent.hash)?;
    let (paths, wanted) = layout(torrent, &meta, record.renamed_file.as_deref())?;
    if !record.destination.is_empty() && !wanted.iter().any(|&i| paths[i] == record.destination) {
        return Err("The torrent destination does not match a selected file.".into());
    }
    let mut present = HashMap::new();
    let mut selected_bytes = 0u64;
    for file in &record.files {
        let entry = meta
            .files
            .get(file.number)
            .ok_or("Invalid torrent file index.")?;
        if entry.padding || file.reference.relative != paths[file.number] {
            return Err("Torrent file path does not match its metadata.".into());
        }
        let content = use_content(bundle, seen, file.reference.index, false)?;
        let size = std::fs::metadata(&content.path)
            .map_err(|e| e.to_string())?
            .len();
        if present.insert(file.number, size).is_some() || size > entry.size {
            return Err("Invalid torrent file size or duplicate file.".into());
        }
        if wanted.contains(&file.number) {
            selected_bytes = selected_bytes
                .checked_add(size)
                .ok_or("Torrent downloaded data is too large.")?;
        }
    }
    if item.downloaded > selected_bytes
        || item.status == Status::Complete
            && wanted
                .iter()
                .any(|&i| present.get(&i) != Some(&meta.files[i].size))
    {
        return Err("Saved torrent data is missing.".into());
    }
    Ok(RestoredTorrent {
        hash: torrent.hash.clone(),
        bytes,
        renamed_file: record
            .renamed_file
            .as_ref()
            .map(|name| join_components(Path::new(""), name)),
    })
}
