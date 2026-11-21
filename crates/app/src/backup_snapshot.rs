//! Prepare a stopped, ordinary-download snapshot for the full-backup worker.
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
use std::path::{Path, PathBuf};

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
/// Fail rather than silently exclude active, missing, or unsupported saved data.
pub(crate) fn prepare(
    items: &[Item],
    queues: &[Queue],
    settings: &Settings,
) -> Result<Snapshot, String> {
    if queues.iter().any(|q| q.running) {
        return Err("Stop all queues before backing up.".into());
    }
    let mut records = Vec::with_capacity(items.len());
    let mut contents = Vec::new();
    let mut ids = std::collections::HashSet::new();
    for item in items {
        if !safe_file_name(&item.file_name) || !ids.insert(item.id) {
            return Err("A download has an invalid file name or duplicate ID.".into());
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
        let state_path = state::state_path(&item.dest);
        let has_state = state_path.exists();
        let has_data = item.status == Status::Complete || item.downloaded > 0 || has_state;
        if has_data
            && (item.video.is_some()
                || item.torrent.is_some()
                || item.gallery.is_some()
                || item.remote.is_some()
                || !item.side_files.is_empty()
                || item
                    .written_files
                    .as_ref()
                    .is_some_and(|files| !files.is_empty()))
        {
            return Err("This backup does not yet support video, torrent, gallery, remote, or multi-file downloads. No data was skipped.".into());
        }
        let content = if item.status == Status::Complete {
            if item.moved_away || !item.dest.is_file() {
                return Err(format!(
                    "A completed file is unavailable: {}",
                    item.file_name
                ));
            }
            let size = std::fs::metadata(&item.dest)
                .map_err(|e| e.to_string())?
                .len();
            if item.size.is_some_and(|expected| expected != size) {
                return Err(format!("Completed file size changed: {}", item.file_name));
            }
            Some(Content::Completed(item.dest.clone()))
        } else if has_state {
            let saved = ResumeState::load(&state_path)?;
            if saved.dest != item.dest {
                return Err(format!("Saved state does not match {}.", item.file_name));
            }
            if credential_url(&saved.url) || credential_url(&saved.final_url) {
                return Err("A saved download address contains a username or password.".into());
            }
            Some(Content::Partial(saved))
        } else if item.downloaded > 0 {
            return Err(format!(
                "Saved data for {} is missing its resume state.",
                item.file_name
            ));
        } else {
            None
        };
        let index = content.map(|c| {
            let index = contents.len();
            contents.push(c);
            index
        });
        let mut record = serde_json::to_value(item).map_err(|e| e.to_string())?;
        let obj = record.as_object_mut().ok_or("Invalid download record")?;
        obj.insert("dest".into(), json!(""));
        if let Some(Content::Partial(saved)) = index.and_then(|n| contents.get(n)) {
            obj.insert("downloaded".into(), json!(saved.downloaded()));
            obj.insert("size".into(), json!(saved.size));
        }
        records.push(json!({"item": record, "content": index}));
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
        metadata: json!({"format":"auralis-download-snapshot", "version":1, "downloads":records, "queues":queues, "settings":preferences}),
        contents,
    })
}
impl Snapshot {
    pub(crate) fn write(&self, destination: &Path) -> std::io::Result<()> {
        self.write_with_progress(destination, |_| Ok(()))
    }

    pub(crate) fn write_with_progress<F: FnMut(u64) -> std::io::Result<()>>(
        &self,
        destination: &Path,
        progress: F,
    ) -> std::io::Result<()> {
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
        snapshot.write(&archive).unwrap();
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
        let mut download = item(&path);
        download.downloaded = 10;
        assert!(prepare(&[download], &[], &Settings::default()).is_err());
        let mut download = item(&path);
        download.status = Status::Downloading;
        assert!(prepare(&[download], &[], &Settings::default()).is_err());
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
    if matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL") {
        return false;
    }
    if let Some(number) = stem
        .strip_prefix("COM")
        .or_else(|| stem.strip_prefix("LPT"))
    {
        if matches!(number, "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9") {
            return false;
        }
    }
    true
}

/// Validate all records and their one-to-one references before changing the app.
pub(crate) fn validate_restore(
    bundle: &backup_bundle::RestoredBundle,
) -> Result<RestorePlan, String> {
    let metadata = &bundle.metadata;
    if metadata["format"] != "auralis-download-snapshot" || metadata["version"] != 1 {
        return Err("Unsupported download snapshot.".into());
    }
    let records = metadata["downloads"]
        .as_array()
        .ok_or("Missing download records")?;
    let mut items = Vec::with_capacity(records.len());
    let mut mapping = Vec::with_capacity(records.len());
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
            || item
                .written_files
                .as_ref()
                .is_some_and(|files| !files.is_empty())
        {
            return Err("Unsafe or invalid download record.".into());
        }
        let index = if record["content"].is_null() {
            None
        } else {
            let n = record["content"]
                .as_u64()
                .and_then(|n| usize::try_from(n).ok())
                .ok_or("Invalid download content index")?;
            let content = bundle.items.get(n).ok_or("Missing download content")?;
            if !seen_content.insert(n)
                || content.partial == (item.status == Status::Complete)
                || item.video.is_some()
                || item.torrent.is_some()
                || item.gallery.is_some()
                || item.remote.is_some()
            {
                return Err("Download content does not match its record.".into());
            }
            if content.partial {
                let saved = ResumeState::load(&state::state_path(&content.path))?;
                if saved.dest != content.path
                    || saved.downloaded() != item.downloaded
                    || item.size != Some(saved.size)
                    || credential_url(&saved.url)
                    || credential_url(&saved.final_url)
                {
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
        if index.is_none() && (item.status == Status::Complete || item.downloaded > 0) {
            return Err("Download data is missing from the snapshot.".into());
        }
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
    Ok(RestorePlan {
        items,
        queues,
        settings,
        content_for_item: mapping,
    })
}

/// Extract into a new directory and give each download its original safe name.
/// The caller must not expose the directory to another process until this
/// returns, and must still reconcile IDs and settings with the live app.
pub(crate) fn restore_to_directory<R: std::io::Read>(
    input: &mut R,
    root: &Path,
) -> Result<RestorePlan, String> {
    let bundle = backup_bundle::restore_bundle(input, root).map_err(|e| e.to_string())?;
    let result = (|| -> Result<RestorePlan, String> {
        let mut plan = validate_restore(&bundle)?;
        for (item, index) in plan.items.iter_mut().zip(&plan.content_for_item) {
            let folder = root.join(format!("download-{}", item.id));
            std::fs::create_dir(&folder).map_err(|e| e.to_string())?;
            let dest = folder.join(&item.file_name);
            if let Some(index) = index {
                let content = &bundle.items[*index];
                if content.partial {
                    let mut saved = ResumeState::load(&state::state_path(&content.path))?;
                    std::fs::rename(
                        mdm_engine::naming::part_path(&content.path),
                        mdm_engine::naming::part_path(&dest),
                    )
                    .map_err(|e| e.to_string())?;
                    saved.dest = dest.clone();
                    let mut output = std::fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(state::state_path(&dest))
                        .map_err(|e| e.to_string())?;
                    serde_json::to_writer(&mut output, &saved).map_err(|e| e.to_string())?;
                    output.sync_all().map_err(|e| e.to_string())?;
                    std::fs::remove_file(state::state_path(&content.path))
                        .map_err(|e| e.to_string())?;
                } else {
                    std::fs::rename(&content.path, &dest).map_err(|e| e.to_string())?;
                }
            }
            item.dest = dest;
        }
        Ok(plan)
    })();
    if result.is_err() {
        let _ = std::fs::remove_dir_all(root);
    }
    result
}

#[cfg(test)]
mod restore_tests {
    use super::*;
    use crate::model::Category;
    use std::fs;

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
        let plan = prepare(&[item], &[], &Settings::default()).unwrap();
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
        bundle.metadata["downloads"][0]["item"]["file_name"] = json!("song.mp3");
        let duplicate = bundle.metadata["downloads"][0].clone();
        bundle.metadata["downloads"]
            .as_array_mut()
            .unwrap()
            .push(duplicate);
        assert!(validate_restore(&bundle).is_err());
    }
}
