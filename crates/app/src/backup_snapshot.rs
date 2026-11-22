//! Prepare stopped downloads for a portable backup.
//! The caller must prevent file changes for the lifetime of the returned plan.
use crate::{
    model::{Item, Status},
    queue::Queue,
    settings::Settings,
};
use mdm_engine::{
    backup_bundle::{self, BackupItem},
    state::{self, ResumeState},
};
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    path::{Component, Path, PathBuf},
};

mod media;
mod torrent;

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
pub(crate) struct StartupPreference {
    pub enabled: bool,
    pub mode: String,
}

fn validate_ui_preferences(
    value: &Value,
) -> Result<std::collections::BTreeMap<String, String>, String> {
    let source = value.as_object().ok_or("Invalid appearance preferences")?;
    let mut total = 0usize;
    let mut result = std::collections::BTreeMap::new();
    for (key, value) in source {
        if !(key.starts_with("mh-glass-")
            || [
                "auralis-update-presentation",
                "auralis-download-columns",
                "auralis-setup-auto-close",
            ]
            .contains(&key.as_str()))
        {
            continue;
        }
        let value = value.as_str().ok_or("Invalid appearance preference")?;
        if key.len() > 128 || value.len() > 2 * 1024 * 1024 {
            return Err("Appearance preference is too large".into());
        }
        total = total
            .checked_add(key.len() + value.len())
            .ok_or("Appearance preferences are too large")?;
        if total > 3 * 1024 * 1024 {
            return Err("Appearance preferences are too large".into());
        }
        result.insert(key.clone(), value.to_owned());
    }
    Ok(result)
}

pub(crate) enum Content {
    Completed(PathBuf),
    Partial(ResumeState),
}
pub(crate) struct Snapshot {
    pub metadata: Value,
    pub contents: Vec<Content>,
}

fn credential_url(url: &url::Url) -> bool {
    !url.username().is_empty() || url.password().is_some()
}
fn credential_text(value: &str) -> bool {
    url::Url::parse(value)
        .ok()
        .is_some_and(|url| credential_url(&url))
}
#[derive(Default, serde::Serialize, serde::Deserialize)]
#[serde(default)]
struct ExtraFiles {
    torrent: Option<torrent::TorrentRecord>,
    original: Option<FileReference>,
    media_folder: bool,
    media: Vec<MediaReference>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct FileReference {
    relative: Vec<String>,
    index: usize,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct MediaReference {
    file: FileReference,
    kind: media::MediaKind,
}

fn checked_components(components: &[String]) -> Result<(), String> {
    if components.is_empty()
        || components.len() > 64
        || components.iter().any(|name| !safe_file_name(name))
    {
        return Err("A backup file has an invalid relative path.".into());
    }
    Ok(())
}

fn relative_components(path: &Path) -> Result<Vec<String>, String> {
    let components = path
        .components()
        .map(|part| match part {
            Component::Normal(name) => name
                .to_str()
                .map(str::to_owned)
                .ok_or("Invalid backup file name."),
            _ => Err("A backup path points outside its download folder."),
        })
        .collect::<Result<Vec<_>, _>>()?;
    checked_components(&components)?;
    Ok(components)
}

fn beneath(base: &Path, path: &Path, allow_root: bool) -> Result<Vec<String>, String> {
    let relative = path
        .strip_prefix(base)
        .map_err(|_| "A saved file points outside its download folder.")?;
    if allow_root && relative.as_os_str().is_empty() {
        return Ok(Vec::new());
    }
    relative_components(relative)
}

fn path_key(relative: &[String]) -> String {
    relative.join("/").to_lowercase()
}

fn join_components(base: &Path, relative: &[String]) -> PathBuf {
    relative
        .iter()
        .fold(base.to_owned(), |path, name| path.join(name))
}

fn is_reparse_point(metadata: &std::fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x400 != 0 // FILE_ATTRIBUTE_REPARSE_POINT
    }
    #[cfg(not(windows))]
    metadata.file_type().is_symlink()
}

fn file_length(path: &Path) -> Result<Option<u64>, String> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_file() && !is_reparse_point(&metadata) => {
            Ok(Some(metadata.len()))
        }
        Ok(_) => Err(format!(
            "A saved path is not a regular file: {}",
            path.display()
        )),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

fn source_path(base: &Path, relative: &[String]) -> Result<PathBuf, String> {
    checked_components(relative)?;
    let mut path = base.to_owned();
    for part in std::iter::once(None).chain(relative[..relative.len() - 1].iter().map(Some)) {
        if let Some(name) = part {
            path.push(name);
        }
        match std::fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.file_type().is_dir() && !is_reparse_point(&metadata) => {}
            Ok(_) => {
                return Err(format!(
                    "A backup folder is not a regular directory: {}",
                    path.display()
                ));
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => break,
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(join_components(base, relative))
}

fn push_content(contents: &mut Vec<Content>, content: Content) -> usize {
    let index = contents.len();
    contents.push(content);
    index
}

fn saved_state(dest: &Path) -> Result<ResumeState, String> {
    let checkpoint = state::state_path(dest);
    if file_length(&checkpoint)?.is_none()
        || file_length(&mdm_engine::naming::part_path(dest))?.is_none()
    {
        return Err("A saved download is missing its checkpoint or partial file.".into());
    }
    let saved = ResumeState::load(&checkpoint)?;
    if saved.dest != dest {
        return Err("Saved download state does not match its destination.".into());
    }
    if credential_url(&saved.url) || credential_url(&saved.final_url) {
        return Err("A saved download address contains a username or password.".into());
    }
    Ok(saved)
}

fn gather_extras(
    item: &Item,
    contents: &mut Vec<Content>,
    torrent_path: &impl Fn(&str) -> Option<PathBuf>,
) -> Result<ExtraFiles, String> {
    if item.torrent.is_some()
        && (item.video.is_some()
            || item.gallery.is_some()
            || item.remote.is_some()
            || !item.side_files.is_empty()
            || item.written_files.is_some())
    {
        return Err("A torrent has incompatible saved download data.".into());
    }
    let mut extras = ExtraFiles::default();
    if let Some(spec) = &item.torrent {
        if spec.hash.len() != 40 || !spec.hash.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err("The saved torrent has an invalid identifier.".into());
        }
        let path = torrent_path(&spec.hash).ok_or("No torrent metadata folder is available.")?;
        extras.torrent = Some(torrent::gather(item, contents, &path)?);
    }
    if let Some(origin) = &item.direct_recovery {
        if item.torrent.is_none() {
            return Err("Missing torrent recovery metadata.".into());
        }
        let name = origin
            .dest
            .file_name()
            .and_then(|n| n.to_str())
            .filter(|n| safe_file_name(n))
            .ok_or("Invalid name for the original recovery file.")?;
        let saved = saved_state(&origin.dest)?;
        if saved.downloaded() != origin.downloaded {
            return Err("The original saved download changed after torrent recovery.".into());
        }
        extras.original = Some(FileReference {
            relative: vec![name.to_owned()],
            index: push_content(contents, Content::Partial(saved)),
        });
    }
    extras.media_folder = media::is_folder(item);
    let mut paths = HashSet::new();
    for file in media::gather(item)? {
        let relative = relative_components(&file.relative)?;
        let base = if extras.media_folder {
            &item.dest
        } else {
            item.dest
                .parent()
                .ok_or("Media destination has no folder.")?
        };
        let source = if file.kind == media::MediaKind::SideVideo && relative.len() == 1 {
            // Move file may leave the tracked subtitle beside the old video path.
            file.source.clone()
        } else {
            source_path(base, &relative)?
        };
        if source != file.source || !paths.insert(path_key(&relative)) {
            return Err("Conflicting paths in a multi-file download.".into());
        }
        let content = if file.kind == media::MediaKind::PartialVideo {
            Content::Partial(saved_state(&source)?)
        } else {
            if file_length(&source)?.is_none() {
                return Err(format!(
                    "A saved media file is unavailable: {}",
                    source.display()
                ));
            }
            Content::Completed(source)
        };
        extras.media.push(MediaReference {
            file: FileReference {
                relative,
                index: push_content(contents, content),
            },
            kind: file.kind,
        });
    }
    Ok(extras)
}
/// Fail rather than silently exclude active, missing, or unsupported saved data.
pub(crate) fn prepare(
    items: &[Item],
    queues: &[Queue],
    settings: &Settings,
) -> Result<Snapshot, String> {
    prepare_with_torrent_files(items, queues, settings, crate::torrents::torrent_file)
}

fn prepare_with_torrent_files(
    items: &[Item],
    queues: &[Queue],
    settings: &Settings,
    torrent_path: impl Fn(&str) -> Option<PathBuf>,
) -> Result<Snapshot, String> {
    if queues.iter().any(|q| q.running) {
        return Err("Stop all queues before backing up.".into());
    }
    let mut records = Vec::with_capacity(items.len());
    let mut contents = Vec::new();
    let mut ids = HashSet::new();
    let mut torrent_hashes = HashSet::new();
    for item in items {
        if item.context.private {
            return Err(
                "Close private downloads before creating a backup; private activity is not saved."
                    .into(),
            );
        }
        if !safe_file_name(&item.file_name) || !ids.insert(item.id) {
            return Err("A download has an invalid file name or duplicate ID.".into());
        }
        if item
            .torrent
            .as_ref()
            .is_some_and(|torrent| !torrent_hashes.insert(&torrent.hash))
        {
            return Err("The download history lists the same torrent more than once.".into());
        }
        if item.live.is_some() || item.status == Status::Downloading || item.torrent_check.is_some()
        {
            return Err("Stop all downloads and torrent checks before backing up.".into());
        }
        if credential_url(&item.url)
            || item.file_url.as_ref().is_some_and(credential_url)
            || item.referer.as_deref().is_some_and(credential_text)
            || item.page.as_deref().is_some_and(credential_text)
        {
            return Err("A download address contains a username or password. Remove it before exporting a backup.".into());
        }
        if item.moved_away {
            return Err(format!("A saved file is unavailable: {}", item.file_name));
        }
        if item.video.is_some()
            && item.status != Status::Complete
            && file_length(&item.dest)?.is_some()
        {
            return Err(format!(
                "An unfinished video already has an output file: {}",
                item.file_name
            ));
        }
        let extras = gather_extras(item, &mut contents, &torrent_path)?;
        let has_owned_media = !extras.media.is_empty();
        let content = if extras.torrent.is_some() || extras.media_folder {
            None
        } else if item.status == Status::Complete {
            let size = file_length(&item.dest)?
                .ok_or_else(|| format!("A completed file is unavailable: {}", item.file_name))?;
            if item.size.is_some_and(|expected| expected != size) {
                return Err(format!("Completed file size changed: {}", item.file_name));
            }
            Some(Content::Completed(item.dest.clone()))
        } else if state::state_path(&item.dest).exists() {
            Some(Content::Partial(saved_state(&item.dest)?))
        } else if file_length(&mdm_engine::naming::part_path(&item.dest))?.is_some()
            || item.downloaded > 0 && !has_owned_media
        {
            return Err(format!(
                "Saved data for {} is missing its resume state.",
                item.file_name
            ));
        } else {
            None
        };
        let index = content.map(|c| push_content(&mut contents, c));
        let mut record = serde_json::to_value(item).map_err(|e| e.to_string())?;
        let obj = record.as_object_mut().ok_or("Invalid download record")?;
        obj.insert("dest".into(), json!(""));
        if let Some(Content::Partial(saved)) = index.and_then(|n| contents.get(n)) {
            obj.insert("downloaded".into(), json!(saved.downloaded()));
            obj.insert("size".into(), json!(saved.size));
        }
        obj.remove("written_files");
        obj.remove("side_files");
        if item.video.is_some() {
            obj.get_mut("video")
                .and_then(Value::as_object_mut)
                .unwrap()
                .remove("parts");
        }
        if item.torrent.is_some() {
            obj.get_mut("torrent")
                .and_then(Value::as_object_mut)
                .unwrap()
                .insert("folder".into(), json!(""));
        }
        if item.remote.is_some() {
            let remote = obj
                .get_mut("remote")
                .and_then(Value::as_object_mut)
                .unwrap();
            remote.insert("folder".into(), json!(""));
            remote.insert("account".into(), json!(0));
            remote.remove("transfer");
        }
        if item.direct_recovery.is_some() {
            obj.get_mut("direct_recovery")
                .and_then(Value::as_object_mut)
                .unwrap()
                .insert("dest".into(), json!(""));
        }
        records.push(json!({"item": record, "content": index, "extras":extras}));
    }
    if queues
        .iter()
        .any(|queue| queue.items.iter().any(|id| !ids.contains(id)))
    {
        return Err("A queue refers to a download that is missing from the list.".into());
    }
    let mut safe = settings.clone();
    safe.proxy_pass.clear();
    safe.site_logins.clear();
    safe.debrid_accounts.clear();
    let preferences = serde_json::to_value(&safe).map_err(|e| e.to_string())?;
    Ok(Snapshot {
        metadata: json!({"format":"auralis-download-snapshot", "version":2, "downloads":records, "queues":queues, "settings":preferences}),
        contents,
    })
}
impl Snapshot {
    /// Add frontend settings after the app's stopped-download snapshot is made.
    /// Wallpaper paths remain paths; this does not claim to archive those files.
    pub(crate) fn attach_ui_preferences(
        &mut self,
        ui: &Value,
        startup: StartupPreference,
    ) -> Result<(), String> {
        if startup.mode != "minimized" && startup.mode != "window" {
            return Err("Invalid startup preference".into());
        }
        let appearance = validate_ui_preferences(ui)?;
        self.metadata["appearance"] =
            serde_json::to_value(appearance).map_err(|e| e.to_string())?;
        self.metadata["startup"] = serde_json::to_value(startup).map_err(|e| e.to_string())?;
        Ok(())
    }
    pub(crate) fn write(&self, destination: &Path) -> std::io::Result<()> {
        self.write_with_progress(destination, |_| Ok(()))
    }

    pub(crate) fn write_with_progress<F: FnMut(u64) -> std::io::Result<()>>(
        &self,
        destination: &Path,
        progress: F,
    ) -> std::io::Result<()> {
        // Hold the downloader's destination reservations until the archive is
        // finished. This prevents a new engine writer from starting midway
        // through the snapshot. The app must still guard its own moves, deletes,
        // queue actions, and non-engine writers for the same duration.
        let mut reservations = Vec::with_capacity(self.contents.len());
        let mut reserved_paths = HashSet::new();
        for content in &self.contents {
            let path = match content {
                Content::Completed(path) => path,
                Content::Partial(state) => &state.dest,
            };
            if !reserved_paths.insert(path) {
                continue;
            }
            reservations.push(mdm_engine::naming::reserve(path).ok_or_else(|| {
                std::io::Error::new(std::io::ErrorKind::WouldBlock, "A download file is in use")
            })?);
        }
        let items: Vec<_> = self
            .contents
            .iter()
            .map(|item| match item {
                Content::Completed(path) => BackupItem::Completed(path),
                Content::Partial(state) => BackupItem::Partial(state),
            })
            .collect();
        backup_bundle::write_bundle_file_with_progress(
            destination,
            self.metadata.clone(),
            &items,
            progress,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Category;
    use mdm_engine::planner::SavedSegment;
    use std::fs;

    fn item(path: &Path) -> Item {
        Item::new(
            1,
            "https://example.org/file".parse().unwrap(),
            path.to_owned(),
            Category::General,
        )
    }
    #[test]
    fn snapshots_history_and_completed_file_without_secrets_or_original_path() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.bin");
        fs::write(&path, b"completed").unwrap();
        let mut download = item(&path);
        download.status = Status::Complete;
        download.downloaded = 9;
        let mut settings = Settings::default();
        settings.proxy_pass = "secret".into();
        settings
            .site_logins
            .push(("example.org".into(), "user".into(), "secret".into()));
        let snapshot = prepare(&[download], &[], &settings).unwrap();
        let json = snapshot.metadata.to_string();
        assert!(!json.contains("secret"));
        assert!(!json.contains(&path.to_string_lossy().to_string()));
        assert_eq!(snapshot.metadata["downloads"][0]["content"], 0);
        let archive = dir.path().join("backup");
        let reservation = mdm_engine::naming::reserve(&path).unwrap();
        assert_eq!(
            snapshot.write(&archive).unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
        assert!(!archive.exists());
        drop(reservation);
        let mut reserved_during_write = false;
        snapshot
            .write_with_progress(&archive, |_| {
                reserved_during_write = mdm_engine::naming::reserve(&path).is_none();
                Ok(())
            })
            .unwrap();
        assert!(
            reserved_during_write,
            "the source must stay reserved while writing"
        );
        assert!(
            mdm_engine::naming::reserve(&path).is_some(),
            "completed backup must release its reservation"
        );
        let restored = backup_bundle::restore_bundle(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("restore"),
        )
        .unwrap();
        assert_eq!(fs::read(&restored.items[0].path).unwrap(), b"completed");
    }
    #[test]
    fn refuses_unsupported_or_missing_data_instead_of_skipping_it() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("missing.bin");
        let mut private = item(&path);
        private.context.private = true;
        assert!(
            prepare(&[private], &[], &Settings::default())
                .err()
                .unwrap()
                .contains("private")
        );
        let mut download = item(&path);
        download.downloaded = 10;
        assert!(prepare(&[download], &[], &Settings::default()).is_err());
        let mut download = item(&path);
        download.status = Status::Downloading;
        assert!(prepare(&[download], &[], &Settings::default()).is_err());
        let mut queued_torrent = item(&path);
        queued_torrent.torrent = Some(serde_json::from_value(json!({"hash":"0123456789abcdef0123456789abcdef01234567","folder":"unbacked-folder"})).unwrap());
        assert!(prepare(&[queued_torrent], &[], &Settings::default()).is_err());
        let mut queue = Queue::new("main", false);
        queue.running = true;
        assert!(prepare(&[], &[queue], &Settings::default()).is_err());
        fs::write(&path, b"short").unwrap();
        let mut complete = item(&path);
        complete.status = Status::Complete;
        complete.size = Some(100);
        assert!(prepare(&[complete], &[], &Settings::default()).is_err());
    }
    #[test]
    fn completed_video_roundtrips_with_subtitles_and_refuses_missing_partial_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("video.mp4");
        let mut download = item(&path);
        download.video = Some(crate::model::VideoSpec {
            selector: "best".into(),
            subs: mdm_tools::video::Subs {
                langs: vec!["en".into()],
                ..Default::default()
            },
            parts: vec![],
            named: true,
        });
        assert!(prepare(std::slice::from_ref(&download), &[], &Settings::default()).is_ok());
        download.status = Status::Stopped;
        download.downloaded = 4;
        assert!(prepare(std::slice::from_ref(&download), &[], &Settings::default()).is_err());
        fs::write(&path, b"finished video").unwrap();
        fs::write(dir.path().join("video.en.srt"), b"English subtitles").unwrap();
        download.status = Status::Complete;
        download.downloaded = 14;
        download.size = Some(14);
        let snapshot = prepare(&[download], &[], &Settings::default()).unwrap();
        let archive = dir.path().join("archive");
        snapshot.write(&archive).unwrap();
        let plan = restore_to_directory(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("restored"),
        )
        .unwrap();
        assert_eq!(fs::read(&plan.items[0].dest).unwrap(), b"finished video");
        assert_eq!(plan.items[0].video.as_ref().unwrap().selector, "best");
        assert_eq!(
            fs::read(&plan.items[0].side_files[0]).unwrap(),
            b"English subtitles"
        );
    }

    #[test]
    fn stopped_torrent_roundtrips_selected_files_boundary_bytes_and_direct_checkpoint() {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("Pack");
        fs::create_dir_all(folder.join("sub")).unwrap();
        let dest = folder.join("a.bin");
        fs::write(&dest, b"ab").unwrap();
        fs::write(folder.join("sub/b.bin"), b"b").unwrap();
        let torrent_path = dir.path().join("data.torrent");
        let mut bytes = b"d4:infod5:filesld6:lengthi4e4:pathl5:a.bineed6:lengthi4e4:pathl3:sub5:b.bineee4:name4:Pack12:piece lengthi4e6:pieces40:".to_vec();
        bytes.extend([95; 40]);
        bytes.extend(b"ee");
        fs::write(&torrent_path, &bytes).unwrap();
        let hash = mdm_torrent::metadata_from_bytes(&bytes).unwrap().info_hash;
        let mut download = item(&dest);
        download.status = Status::Stopped;
        download.downloaded = 2;
        download.size = Some(4);
        download.torrent = Some(
            serde_json::from_value(json!({
                "hash": hash, "files": [0], "folder":folder
            }))
            .unwrap(),
        );

        let origin = dir.path().join("original.bin");
        let mut resume = ResumeState::new(
            download.url.clone(),
            download.url.clone(),
            origin.clone(),
            4,
            Default::default(),
        );
        resume.segments = vec![SavedSegment {
            start: 0,
            cursor: 3,
            end: 4,
        }];
        fs::write(
            state::state_path(&origin),
            serde_json::to_vec(&resume).unwrap(),
        )
        .unwrap();
        fs::write(mdm_engine::naming::part_path(&origin), b"abcd").unwrap();
        download.direct_recovery = Some(crate::model::DirectRecoveryOrigin {
            dest: origin,
            downloaded: 3,
            damaged: false,
            verified_bytes: Some(3),
            direct_error: Some("Source expired".into()),
        });

        let backup = prepare_with_torrent_files(&[download], &[], &Settings::default(), |_| {
            Some(torrent_path.clone())
        })
        .unwrap();
        assert!(
            !backup
                .metadata
                .to_string()
                .contains(&*dir.path().to_string_lossy())
        );
        let archive = dir.path().join("archive");
        backup.write(&archive).unwrap();
        let plan = restore_to_directory(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("restored"),
        )
        .unwrap();
        let restored = &plan.items[0];
        assert_eq!(plan.torrent_metadata[0].bytes, bytes);
        assert_eq!(restored.status, Status::Stopped);
        assert_eq!(restored.torrent.as_ref().unwrap().files, Some(vec![0]));
        assert_eq!(fs::read(&restored.dest).unwrap(), b"ab");
        assert_eq!(
            fs::read(restored.torrent.as_ref().unwrap().folder.join("sub/b.bin")).unwrap(),
            b"b"
        );
        let restored_origin = &restored.direct_recovery.as_ref().unwrap().dest;
        let state = ResumeState::load(&state::state_path(restored_origin)).unwrap();
        assert_eq!(state.dest, *restored_origin);
        assert_eq!(state.downloaded(), 3);
        assert_eq!(
            &fs::read(mdm_engine::naming::part_path(restored_origin)).unwrap()[..3],
            b"abc"
        );
    }

    #[test]
    fn gallery_roundtrips_tracked_nested_files_without_untracked_neighbors() {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("gallery");
        fs::create_dir_all(folder.join("nested")).unwrap();
        let tracked = folder.join("nested/image.jpg");
        fs::write(&tracked, b"image").unwrap();
        fs::write(folder.join("other.txt"), b"other").unwrap();
        let mut download = item(&folder);
        download.gallery = Some(Default::default());
        download.written_files = Some(vec![tracked]);
        download.status = Status::Stopped;
        download.downloaded = 5;
        let snapshot = prepare(&[download], &[], &Settings::default()).unwrap();
        let archive = dir.path().join("archive");
        snapshot.write(&archive).unwrap();
        let plan = restore_to_directory(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("restored"),
        )
        .unwrap();
        let restored = &plan.items[0];
        assert_eq!(
            restored.written_files.as_ref().unwrap(),
            &[restored.dest.join("nested/image.jpg")]
        );
        assert_eq!(
            fs::read(restored.dest.join("nested/image.jpg")).unwrap(),
            b"image"
        );
        assert!(!restored.dest.join("other.txt").exists());
    }
    #[test]
    fn rejects_invalid_ui_backup_values_before_writing() {
        let mut snapshot = prepare(&[], &[], &Settings::default()).unwrap();
        let startup = StartupPreference {
            enabled: false,
            mode: "window".into(),
        };
        assert!(
            snapshot
                .attach_ui_preferences(&json!({"mh-glass-theme": 123}), startup.clone())
                .is_err()
        );
        assert!(
            snapshot
                .attach_ui_preferences(
                    &json!({"mh-glass-theme": "x".repeat(2 * 1024 * 1024 + 1)}),
                    startup.clone()
                )
                .is_err()
        );
        assert!(
            snapshot
                .attach_ui_preferences(
                    &json!({}),
                    StartupPreference {
                        enabled: true,
                        mode: "bad".into()
                    }
                )
                .is_err()
        );
        assert!(snapshot.metadata.get("appearance").is_none());
        snapshot
            .attach_ui_preferences(&json!({"mh-glass-theme": "ocean"}), startup)
            .unwrap();
        assert_eq!(snapshot.metadata["appearance"]["mh-glass-theme"], "ocean");
    }
    #[test]
    fn snapshots_saved_range_state_and_queued_items() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("partial.bin");
        fs::write(mdm_engine::naming::part_path(&path), b"abcdefgh").unwrap();
        let mut download = item(&path);
        download.status = Status::Stopped;
        download.downloaded = 4;
        let mut saved = ResumeState::new(
            download.url.clone(),
            download.url.clone(),
            path.clone(),
            8,
            Default::default(),
        );
        saved.segments = vec![SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        fs::write(
            state::state_path(&path),
            serde_json::to_vec(&saved).unwrap(),
        )
        .unwrap();
        let mut queued = item(&dir.path().join("queued.bin"));
        queued.id = 2;
        let snapshot = prepare(&[download, queued], &[], &Settings::default()).unwrap();
        assert_eq!(snapshot.contents.len(), 1);
        assert_eq!(snapshot.metadata["downloads"][1]["content"], Value::Null);
        let archive = dir.path().join("partial-backup");
        snapshot.write(&archive).unwrap();
        let bundle = backup_bundle::restore_bundle(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("partial-restore"),
        )
        .unwrap();
        let plan = validate_restore(&bundle).unwrap();
        assert_eq!(plan.items[0].downloaded, 4);
        assert_eq!(plan.items[0].size, Some(8));
        let plan = restore_to_directory(
            &mut fs::File::open(dir.path().join("partial-backup")).unwrap(),
            &dir.path().join("named-restore"),
        )
        .unwrap();
        assert_eq!(plan.items[0].dest.file_name().unwrap(), "partial.bin");
        let state = ResumeState::load(&state::state_path(&plan.items[0].dest)).unwrap();
        assert_eq!(state.dest, plan.items[0].dest);
        assert_eq!(state.downloaded(), 4);
        assert_eq!(
            &fs::read(mdm_engine::naming::part_path(&state.dest)).unwrap()[..4],
            b"abcd"
        );
    }
}

/// Validated records. A caller must explicitly add these to the live list.
pub(crate) struct RestorePlan {
    pub items: Vec<Item>,
    pub queues: Vec<Queue>,
    pub settings: Settings,
    pub content_for_item: Vec<Option<usize>>,
    extras: Vec<ExtraFiles>,
    pub torrent_metadata: Vec<torrent::RestoredTorrent>,
    pub appearance: Option<std::collections::BTreeMap<String, String>>,
    pub startup: Option<StartupPreference>,
}

fn safe_file_name(name: &str) -> bool {
    if name.is_empty()
        || name.len() > 240
        || name == "."
        || name == ".."
        || name.ends_with([' ', '.'])
        || name
            .chars()
            .any(|c| c.is_control() || "<>:\"/\\|?*".contains(c))
    {
        return false;
    }
    let stem = name.split('.').next().unwrap_or("").to_ascii_uppercase();
    if matches!(
        stem.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
    ) {
        return false;
    }
    if let Some(number) = stem
        .strip_prefix("COM")
        .or_else(|| stem.strip_prefix("LPT"))
    {
        if matches!(
            number,
            "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
        ) {
            return false;
        }
    }
    true
}

fn use_content<'a>(
    bundle: &'a backup_bundle::RestoredBundle,
    seen: &mut HashSet<usize>,
    index: usize,
    partial: bool,
) -> Result<&'a backup_bundle::RestoredItem, String> {
    let content = bundle.items.get(index).ok_or("Missing download content.")?;
    if !seen.insert(index) || content.partial != partial {
        return Err("Download content does not match its record.".into());
    }
    Ok(content)
}

fn validate_extras(
    item: &Item,
    extras: &ExtraFiles,
    bundle: &backup_bundle::RestoredBundle,
    seen: &mut HashSet<usize>,
) -> Result<Option<torrent::RestoredTorrent>, String> {
    if item.torrent.is_some() != extras.torrent.is_some()
        || item.direct_recovery.is_some() != extras.original.is_some()
        || item.gallery.is_some() && !extras.media_folder
        || extras.media_folder && item.gallery.is_none() && item.remote.is_none()
        || item.remote.as_ref().is_some_and(|spec| {
            item.status != Status::Complete
                || !spec.folder.as_os_str().is_empty()
                || spec.account != 0
                || spec.transfer.is_some()
        })
        || item
            .video
            .as_ref()
            .is_some_and(|spec| !spec.parts.is_empty())
        || item.written_files.is_some()
        || !item.side_files.is_empty()
    {
        return Err("Invalid multi-file download record.".into());
    }
    let torrent = if let Some(record) = &extras.torrent {
        if item.video.is_some()
            || item.gallery.is_some()
            || item.remote.is_some()
            || !extras.media.is_empty()
        {
            return Err("A torrent cannot contain unrelated media data.".into());
        }
        Some(torrent::validate(item, record, bundle, seen)?)
    } else {
        None
    };
    if let Some(original) = &extras.original {
        let origin = item
            .direct_recovery
            .as_ref()
            .expect("matched recovery record");
        checked_components(&original.relative)?;
        if original.relative.len() != 1 || torrent.is_none() || !origin.dest.as_os_str().is_empty()
        {
            return Err("Invalid direct recovery record.".into());
        }
        let state = saved_state(&use_content(bundle, seen, original.index, true)?.path)?;
        if state.downloaded() != origin.downloaded {
            return Err("Saved original data does not match the recovery record.".into());
        }
    }
    let mut seen_paths = HashSet::new();
    if !extras.media_folder {
        seen_paths.insert(path_key(std::slice::from_ref(&item.file_name)));
    }
    for media_file in &extras.media {
        checked_components(&media_file.file.relative)?;
        if !seen_paths.insert(path_key(&media_file.file.relative))
            || media_file.kind == media::MediaKind::SideVideo && media_file.file.relative.len() != 1
            || !media::validate_kind(item, media_file.kind, extras.media_folder)
        {
            return Err("Invalid media file or conflicting path.".into());
        }
        let partial = media_file.kind == media::MediaKind::PartialVideo;
        let content = use_content(bundle, seen, media_file.file.index, partial)?;
        if partial {
            saved_state(&content.path)?;
        }
    }
    if extras.media_folder && item.downloaded > 0 && extras.media.is_empty() {
        return Err("Saved files for a folder download are missing.".into());
    }
    Ok(torrent)
}

/// Validate all records and their one-to-one references before changing the app.
pub(crate) fn validate_restore(
    bundle: &backup_bundle::RestoredBundle,
) -> Result<RestorePlan, String> {
    let metadata = &bundle.metadata;
    let version = metadata["version"].as_u64();
    if metadata["format"] != "auralis-download-snapshot" || !matches!(version, Some(1 | 2)) {
        return Err("Unsupported download snapshot.".into());
    }
    let records = metadata["downloads"]
        .as_array()
        .ok_or("Missing download records")?;
    let mut items = Vec::with_capacity(records.len());
    let mut mapping = Vec::with_capacity(records.len());
    let mut all_extras = Vec::with_capacity(records.len());
    let mut torrents = Vec::new();
    let mut torrent_hashes = HashSet::new();
    let mut seen_ids = std::collections::HashSet::new();
    let mut seen_content = std::collections::HashSet::new();
    for record in records {
        let item: Item = serde_json::from_value(record["item"].clone())
            .map_err(|_| "Invalid download record")?;
        if !safe_file_name(&item.file_name)
            || !item.dest.as_os_str().is_empty()
            || item.status == Status::Downloading
            || !seen_ids.insert(item.id)
            || credential_url(&item.url)
            || item.file_url.as_ref().is_some_and(credential_url)
            || item.referer.as_deref().is_some_and(credential_text)
            || item.page.as_deref().is_some_and(credential_text)
            || item.moved_away
        {
            return Err("Unsafe or invalid download record.".into());
        }
        let extras = if version == Some(2) {
            serde_json::from_value::<ExtraFiles>(record["extras"].clone())
                .map_err(|_| "Invalid saved file references.")?
        } else {
            ExtraFiles::default()
        };
        if let Some(torrent) = validate_extras(&item, &extras, bundle, &mut seen_content)? {
            if !torrent_hashes.insert(torrent.hash.clone()) {
                return Err("Duplicate torrent in backup.".into());
            }
            torrents.push(torrent);
        }
        let folder_download = extras.torrent.is_some() || extras.media_folder;
        let index = if record["content"].is_null() {
            None
        } else {
            let n = record["content"]
                .as_u64()
                .and_then(|n| usize::try_from(n).ok())
                .ok_or("Invalid download content index")?;
            if folder_download {
                return Err("Unexpected main file for a folder or torrent download.".into());
            }
            let content = use_content(
                bundle,
                &mut seen_content,
                n,
                item.status != Status::Complete,
            )?;
            if content.partial {
                let saved = saved_state(&content.path)?;
                if saved.downloaded() != item.downloaded || item.size != Some(saved.size) {
                    return Err("Saved download state does not match its record.".into());
                }
            } else {
                let length = std::fs::metadata(&content.path)
                    .map_err(|e| e.to_string())?
                    .len();
                if item.size.is_some_and(|size| size != length) {
                    return Err("Completed file size does not match its record.".into());
                }
            }
            Some(n)
        };
        if index.is_none()
            && !folder_download
            && (item.status == Status::Complete || item.downloaded > 0 && extras.media.is_empty())
        {
            return Err("Download data is missing from the snapshot.".into());
        }
        all_extras.push(extras);
        mapping.push(index);
        items.push(item);
    }
    if seen_content.len() != bundle.items.len() {
        return Err("Unreferenced download data in snapshot.".into());
    }
    let queues: Vec<Queue> =
        serde_json::from_value(metadata["queues"].clone()).map_err(|_| "Invalid queues")?;
    if queues
        .iter()
        .any(|q| q.items.iter().any(|id| !seen_ids.contains(id)))
    {
        return Err("Queue refers to a missing download.".into());
    }
    let settings: Settings =
        serde_json::from_value(metadata["settings"].clone()).map_err(|_| "Invalid settings")?;
    if !settings.proxy_pass.is_empty()
        || !settings.site_logins.is_empty()
        || !settings.debrid_accounts.is_empty()
    {
        return Err("Backup contains credentials.".into());
    }
    let appearance = metadata
        .get("appearance")
        .map(validate_ui_preferences)
        .transpose()?;
    let startup: Option<StartupPreference> = metadata
        .get("startup")
        .map(|value| {
            serde_json::from_value(value.clone())
                .map_err(|_| "Invalid startup preference".to_owned())
        })
        .transpose()?;
    if startup
        .as_ref()
        .is_some_and(|s| s.mode != "minimized" && s.mode != "window")
    {
        return Err("Invalid startup preference".into());
    }
    Ok(RestorePlan {
        items,
        queues,
        settings,
        content_for_item: mapping,
        extras: all_extras,
        torrent_metadata: torrents,
        appearance,
        startup,
    })
}

fn materialize(content: &backup_bundle::RestoredItem, dest: &Path) -> Result<(), String> {
    if !content.partial {
        return mdm_engine::safe_move::rename_no_replace(&content.path, dest)
            .map_err(|e| e.to_string());
    }
    let mut saved = saved_state(&content.path)?;
    mdm_engine::safe_move::rename_no_replace(
        &mdm_engine::naming::part_path(&content.path),
        &mdm_engine::naming::part_path(dest),
    )
    .map_err(|e| e.to_string())?;
    saved.dest = dest.to_owned();
    let mut output = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(state::state_path(dest))
        .map_err(|e| e.to_string())?;
    serde_json::to_writer(&mut output, &saved).map_err(|e| e.to_string())?;
    output.sync_all().map_err(|e| e.to_string())?;
    std::fs::remove_file(state::state_path(&content.path)).map_err(|e| e.to_string())
}

fn materialize_reference(
    bundle: &backup_bundle::RestoredBundle,
    folder: &Path,
    file: &FileReference,
) -> Result<PathBuf, String> {
    let (name, parents) = file
        .relative
        .split_last()
        .ok_or("Missing backup file name.")?;
    let mut current = folder.to_owned();
    for part in parents {
        current.push(part);
        match std::fs::create_dir(&current) {
            Ok(()) => {}
            Err(e)
                if e.kind() == std::io::ErrorKind::AlreadyExists
                    && std::fs::symlink_metadata(&current).is_ok_and(|entry| {
                        entry.file_type().is_dir() && !is_reparse_point(&entry)
                    }) => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    let dest = current.join(name);
    materialize(&bundle.items[file.index], &dest)?;
    Ok(dest)
}

/// Extract into a new directory and give each download its original safe name.
/// The caller must not expose the directory to another process until this
/// returns, and must still reconcile IDs and settings with the live app.
pub(crate) fn restore_to_directory<R: std::io::Read>(
    input: &mut R,
    root: &Path,
) -> Result<RestorePlan, String> {
    if root.exists() {
        return Err("Choose a new, unused restore folder.".into());
    }
    let bundle = backup_bundle::restore_bundle(input, root).map_err(|error| {
        if root.exists() {
            format!("{error}. Restore files may remain at {}.", root.display())
        } else {
            error.to_string()
        }
    })?;
    let result = (|| -> Result<RestorePlan, String> {
        let mut plan = validate_restore(&bundle)?;
        for ((item, index), extras) in plan
            .items
            .iter_mut()
            .zip(&plan.content_for_item)
            .zip(&plan.extras)
        {
            let folder = root.join(format!("download-{}", item.id));
            std::fs::create_dir(&folder).map_err(|e| e.to_string())?;
            let mut dest = folder.join(&item.file_name);
            if let Some(torrent) = &extras.torrent {
                let torrent_folder = folder.join(if torrent.destination.is_empty() {
                    item.file_name.as_str()
                } else {
                    "torrent"
                });
                std::fs::create_dir(&torrent_folder).map_err(|e| e.to_string())?;
                for file in &torrent.files {
                    materialize_reference(&bundle, &torrent_folder, &file.reference)?;
                }
                let archived = &bundle.items[torrent.metadata];
                std::fs::remove_file(&archived.path).map_err(|e| e.to_string())?;
                dest = join_components(&torrent_folder, &torrent.destination);
                item.torrent.as_mut().expect("validated torrent").folder = torrent_folder;
            } else if extras.media_folder {
                std::fs::create_dir(&dest).map_err(|e| e.to_string())?;
            } else if let Some(index) = index {
                materialize(&bundle.items[*index], &dest)?;
            }
            if let Some(original) = &extras.original {
                let source_folder = folder.join("original");
                std::fs::create_dir(&source_folder).map_err(|e| e.to_string())?;
                let original_dest = materialize_reference(&bundle, &source_folder, original)?;
                item.direct_recovery
                    .as_mut()
                    .expect("validated recovery")
                    .dest = original_dest;
            }
            let media_root = if extras.media_folder { &dest } else { &folder };
            for media_file in &extras.media {
                let path = materialize_reference(&bundle, media_root, &media_file.file)?;
                match media_file.kind {
                    media::MediaKind::SideVideo => item.side_files.push(path),
                    media::MediaKind::VideoPart => item
                        .video
                        .as_mut()
                        .expect("validated video")
                        .parts
                        .push(path),
                    media::MediaKind::FolderFile => {
                        item.written_files.get_or_insert_with(Vec::new).push(path)
                    }
                    media::MediaKind::PartialVideo => {
                        let parts = &mut item.video.as_mut().expect("validated video").parts;
                        parts.push(state::state_path(&path));
                        parts.push(mdm_engine::naming::part_path(&path));
                    }
                    media::MediaKind::Sidecar => {}
                }
            }
            if let Some(remote) = &mut item.remote {
                remote.folder = media_root.to_owned();
            }
            if extras.media_folder {
                item.written_files.get_or_insert_with(Vec::new);
            }
            item.preexisting_folder = false;
            item.dest = dest;
        }
        Ok(plan)
    })();
    match result {
        Ok(plan) => Ok(plan),
        Err(error) => {
            // Never recursively remove a directory that may now contain files
            // created by another process or partially restored user data.
            let _ = std::fs::remove_dir(root);
            if root.exists() {
                Err(format!(
                    "{error}. Incomplete restore files were kept at {}.",
                    root.display()
                ))
            } else {
                Err(error)
            }
        }
    }
}

#[cfg(test)]
mod restore_tests {
    use super::*;
    use crate::model::Category;
    use std::fs;

    #[test]
    fn invalid_snapshot_does_not_delete_unrelated_restore_files() {
        struct Inject<R> {
            inner: R,
            path: PathBuf,
            done: bool,
        }
        impl<R: std::io::Read> std::io::Read for Inject<R> {
            fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
                if !self.done {
                    self.done = true;
                    fs::write(&self.path, b"keep")?;
                }
                self.inner.read(out)
            }
        }
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("file.bin");
        fs::write(&path, b"data").unwrap();
        let mut download = Item::new(
            1,
            "https://example.org/file".parse().unwrap(),
            path,
            Category::General,
        );
        download.status = Status::Complete;
        download.size = Some(4);
        download.downloaded = 4;
        let mut snapshot = prepare(&[download], &[], &Settings::default()).unwrap();
        snapshot.metadata["downloads"][0]["item"]["file_name"] = json!("../invalid");
        let archive = dir.path().join("backup");
        snapshot.write(&archive).unwrap();
        let root = dir.path().join("restored");
        let foreign = root.join("unrelated");
        let mut input = Inject {
            inner: fs::File::open(archive).unwrap(),
            path: foreign.clone(),
            done: false,
        };
        let error = restore_to_directory(&mut input, &root).err().unwrap();
        assert!(error.contains("Incomplete restore files were kept"));
        assert_eq!(fs::read(foreign).unwrap(), b"keep");
    }

    #[test]
    fn validates_history_before_applying_and_rejects_unsafe_paths_and_duplicates() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("song.mp3");
        fs::write(&path, b"music").unwrap();
        let mut item = Item::new(
            7,
            "https://example.org/song".parse().unwrap(),
            path,
            Category::Music,
        );
        item.status = Status::Complete;
        item.downloaded = 5;
        let mut plan = prepare(&[item], &[], &Settings::default()).unwrap();
        plan.attach_ui_preferences(
            &json!({"mh-glass-theme":"ocean", "not-an-app-setting":"ignored"}),
            StartupPreference {
                enabled: true,
                mode: "minimized".into(),
            },
        )
        .unwrap();
        let archive = dir.path().join("archive");
        plan.write(&archive).unwrap();
        let mut bundle = backup_bundle::restore_bundle(
            &mut fs::File::open(archive).unwrap(),
            &dir.path().join("restore"),
        )
        .unwrap();
        let result = validate_restore(&bundle).unwrap();
        assert_eq!(result.items[0].file_name, "song.mp3");
        assert_eq!(result.content_for_item, vec![Some(0)]);
        assert!(result.queues.is_empty());
        assert!(result.settings.proxy_pass.is_empty());
        assert_eq!(
            result
                .appearance
                .as_ref()
                .unwrap()
                .get("mh-glass-theme")
                .map(String::as_str),
            Some("ocean")
        );
        assert!(
            !result
                .appearance
                .as_ref()
                .unwrap()
                .contains_key("not-an-app-setting")
        );
        assert_eq!(result.startup.as_ref().unwrap().mode, "minimized");
        let restored = restore_to_directory(
            &mut fs::File::open(dir.path().join("archive")).unwrap(),
            &dir.path().join("named-restore"),
        )
        .unwrap();
        assert_eq!(restored.items[0].dest.file_name().unwrap(), "song.mp3");
        assert_eq!(fs::read(&restored.items[0].dest).unwrap(), b"music");
        let existing = dir.path().join("existing");
        fs::create_dir(&existing).unwrap();
        fs::write(existing.join("keep"), b"original").unwrap();
        assert!(
            restore_to_directory(
                &mut fs::File::open(dir.path().join("archive")).unwrap(),
                &existing,
            )
            .is_err()
        );
        assert_eq!(fs::read(existing.join("keep")).unwrap(), b"original");
        bundle.metadata["downloads"][0]["item"]["file_name"] = json!("../evil");
        assert!(validate_restore(&bundle).is_err());
        bundle.metadata["downloads"][0]["item"]["file_name"] = json!("CON.txt");
        assert!(validate_restore(&bundle).is_err());
        bundle.metadata["downloads"][0]["item"]["file_name"] = json!("COM¹.txt");
        assert!(validate_restore(&bundle).is_err());
        bundle.metadata["downloads"][0]["item"]["file_name"] = json!("song.mp3");
        let duplicate = bundle.metadata["downloads"][0].clone();
        bundle.metadata["downloads"]
            .as_array_mut()
            .unwrap()
            .push(duplicate);
        assert!(validate_restore(&bundle).is_err());
    }
}
