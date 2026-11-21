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
    for item in items {
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
        records.push(json!({"item": record, "content": index}));
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
        let items: Vec<_> = self
            .contents
            .iter()
            .map(|item| match item {
                Content::Completed(path) => BackupItem::Completed(path),
                Content::Partial(state) => BackupItem::Partial(state),
            })
            .collect();
        backup_bundle::write_bundle_file(destination, self.metadata.clone(), &items)
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
        let queued = item(&dir.path().join("queued.bin"));
        let snapshot = prepare(&[download, queued], &[], &Settings::default()).unwrap();
        assert_eq!(snapshot.contents.len(), 1);
        assert_eq!(snapshot.metadata["downloads"][1]["content"], Value::Null);
    }
}
