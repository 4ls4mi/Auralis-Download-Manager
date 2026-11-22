use super::*;
use crate::backup_snapshot::{self, RestorePlan, StartupPreference};
use std::collections::VecDeque;
use std::io::{BufReader, Read};
use std::path::Path;
use std::sync::mpsc::{self, Receiver, TryRecvError};

enum FinishedWork {
    Exported(PathBuf),
    Imported {
        archive: PathBuf,
        root: PathBuf,
        plan: Box<RestorePlan>,
    },
}

type JobResult = Result<FinishedWork, String>;

#[derive(Default)]
pub(in crate::app) struct FullBackup {
    next_id: u64,
    active: Option<(u64, Receiver<JobResult>)>,
    finished: VecDeque<(u64, Value)>,
    pub(in crate::app) deferred: VecDeque<ipc::Command>,
}

impl FullBackup {
    pub(in crate::app) fn busy(&self) -> bool {
        self.active.is_some()
    }

    fn status(&self, id: Option<u64>) -> Value {
        match id {
            None => json!({"pending": self.busy()}),
            Some(id)
                if self
                    .active
                    .as_ref()
                    .is_some_and(|(current, _)| *current == id) =>
            {
                json!({"pending": true})
            }
            Some(id) => self
                .finished
                .iter()
                .find(|(current, _)| *current == id)
                .map(|(_, reply)| reply.clone())
                .unwrap_or_else(
                    || json!({"error": "The backup operation is no longer available."}),
                ),
        }
    }
}

#[derive(serde::Deserialize)]
struct AppearanceManifest {
    appearance: Value,
    startup: StartupPreference,
}

fn read_appearance_manifest(path: &Path) -> Result<AppearanceManifest, String> {
    let folder = mdm_ipc::data_dir()
        .ok_or("No application data folder is available.")?
        .join("backup-ui");
    if path.parent() != Some(folder.as_path()) {
        return Err("Invalid backup preferences file.".into());
    }
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|error| error.to_string())?
        .take(4 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| error.to_string())?;
    if bytes.len() > 4 * 1024 * 1024 {
        return Err("Backup preferences are too large.".into());
    }
    serde_json::from_slice(&bytes).map_err(|error| format!("Invalid backup preferences: {error}"))
}

impl App {
    pub(in crate::app) fn glass_backup_answer(&mut self, cmd: &ipc::Command) -> Option<String> {
        if cmd.query.as_deref() == Some("glass-full-backup-status") {
            return Some(
                self.full_backup
                    .status(cmd.ids.first().copied())
                    .to_string(),
            );
        }
        let restore = match cmd.action.as_deref() {
            Some("glass-export-full-backup") => false,
            Some("glass-import-full-backup") => true,
            _ => return None,
        };
        let result = self.begin_full_backup(cmd, restore);
        Some(
            match result {
                Ok(id) => json!({"id": id}),
                Err(error) => json!({"error": error}),
            }
            .to_string(),
        )
    }

    fn check_backup_idle(&self) -> Result<(), String> {
        if self.full_backup.busy() {
            return Err("Another backup or restore is already running.".into());
        }
        if self.queues.iter().any(|queue| queue.running)
            || self
                .items
                .iter()
                .any(|item| item.live.is_some() || item.status == Status::Downloading)
        {
            return Err("Stop all downloads and queues before backing up or restoring.".into());
        }
        if !self.moving.is_empty()
            || !self.renaming.is_empty()
            || !self.deferred_torrent_queue.is_empty()
            || self.items.iter().any(|item| {
                self.extracts.extracting(item.id)
                    || self.recovery_check_running(item.id)
                    || self.repair_check_running(item.id)
                    || item.torrent_check.is_some()
                    || item
                        .torrent
                        .as_ref()
                        .is_some_and(|torrent| self.torrent_host.busy(&torrent.hash))
            })
        {
            return Err("Wait for file moves, checks, recovery, and extraction to finish.".into());
        }
        Ok(())
    }

    fn begin_full_backup(&mut self, cmd: &ipc::Command, restore: bool) -> Result<u64, String> {
        self.check_backup_idle()?;
        let archive = cmd
            .dir
            .as_deref()
            .map(PathBuf::from)
            .ok_or("Choose a backup archive.")?;
        let parameter = cmd
            .queue
            .as_deref()
            .map(PathBuf::from)
            .ok_or("Missing backup parameters.")?;
        let export = if restore {
            None
        } else {
            if self.items.iter().any(|item| item.context.private) {
                return Err("Close private downloads before creating a backup.".into());
            }
            // Transfer persisted row data without live jobs, private browser
            // context, or cookies. The filesystem work runs on the worker.
            let rows = serde_json::to_vec(&self.items).map_err(|error| error.to_string())?;
            let preferences = read_appearance_manifest(&parameter)?;
            Some((
                rows,
                self.queues.clone(),
                self.settings.clone(),
                preferences,
            ))
        };
        let (send, receive) = mpsc::channel();
        let wake = self.ui_ctx.clone();
        std::thread::Builder::new()
            .name("auralis-backup".into())
            .spawn(move || {
                let result = (|| -> JobResult {
                    if let Some((rows, queues, settings, preferences)) = export {
                        let items: Vec<Item> =
                            serde_json::from_slice(&rows).map_err(|error| error.to_string())?;
                        let mut snapshot = backup_snapshot::prepare(&items, &queues, &settings)?;
                        snapshot
                            .attach_ui_preferences(&preferences.appearance, preferences.startup)?;
                        snapshot
                            .write(&archive)
                            .map_err(|error| format!("Could not write the backup: {error}"))?;
                        Ok(FinishedWork::Exported(archive))
                    } else {
                        let file = std::fs::File::open(&archive)
                            .map_err(|error| format!("Could not open the backup: {error}"))?;
                        let plan = backup_snapshot::restore_to_directory(
                            &mut BufReader::new(file),
                            &parameter,
                        )?;
                        Ok(FinishedWork::Imported {
                            archive,
                            root: parameter,
                            plan: Box::new(plan),
                        })
                    }
                })();
                let _ = send.send(result);
                wake.request_repaint();
            })
            .map_err(|error| format!("Could not start the backup worker: {error}"))?;
        self.full_backup.next_id = self.full_backup.next_id.wrapping_add(1).max(1);
        let id = self.full_backup.next_id;
        self.full_backup.active = Some((id, receive));
        Ok(id)
    }

    pub(in crate::app) fn poll_glass_full_backup(&mut self) {
        let Some((id, receiver)) = self.full_backup.active.as_ref() else {
            return;
        };
        let id = *id;
        let result = match receiver.try_recv() {
            Ok(result) => result,
            Err(TryRecvError::Empty) => return,
            Err(TryRecvError::Disconnected) => {
                Err("The backup worker stopped unexpectedly.".into())
            }
        };
        self.full_backup.active = None;
        let reply = match result {
            Ok(FinishedWork::Exported(archive)) => Ok(json!({"path": archive})),
            Ok(FinishedWork::Imported {
                archive,
                root,
                plan,
            }) => self
                .commit_full_restore(*plan, &archive, &root)
                .map_err(|error| format!("{error} Restored files are at {}.", root.display())),
            Err(error) => Err(error),
        };
        self.full_backup.finished.push_back((
            id,
            match reply {
                Ok(result) => result,
                Err(error) => json!({"error": error}),
            },
        ));
        while self.full_backup.finished.len() > 4 {
            self.full_backup.finished.pop_front();
        }
    }

    fn commit_full_restore(
        &mut self,
        mut plan: RestorePlan,
        archive: &Path,
        root: &Path,
    ) -> Result<Value, String> {
        if store::path().is_none() {
            return Err("No download history folder is available.".into());
        }
        let existing_hashes = self.torrent_hashes();
        // Reconcile filesystem-backed torrent jobs before publishing their rows.
        for torrent in &plan.torrent_metadata {
            if existing_hashes.contains(&torrent.hash)
                || self
                    .torrent_host
                    .get()
                    .is_some_and(|session| session.has(&torrent.hash))
            {
                return Err(format!(
                    "Torrent {} is already in this download list.",
                    torrent.hash
                ));
            }
        }
        let mut mapped = HashMap::new();
        let mut next_id = self.next_id;
        for item in &plan.items {
            mapped.insert(item.id, next_id);
            next_id = next_id
                .checked_add(1)
                .ok_or("The download history has no free IDs.")?;
        }
        for item in &mut plan.items {
            item.id = mapped[&item.id];
            item.group = item.group.and_then(|id| mapped.get(&id).copied());
        }
        remap_packages(&mut plan.items, &self.items)?;

        let mut queues = self.queues.clone();
        for mut queue in plan.queues {
            queue.items = queue.items.iter().map(|id| mapped[id]).collect();
            queue.running = false;
            if let Some(empty) = queues
                .iter_mut()
                .find(|q| q.name == queue.name && q.items.is_empty() && q.sync == queue.sync)
            {
                *empty = queue;
            } else {
                let base = queue.name.clone();
                let mut suffix = 1;
                while queues.iter().any(|q| q.name == queue.name) {
                    queue.name = if suffix == 1 {
                        format!("{base} (restored)")
                    } else {
                        format!("{base} (restored {suffix})")
                    };
                    suffix += 1;
                }
                queues.push(queue);
            }
        }
        let mut settings = plan.settings;
        settings.proxy_pass = self.settings.proxy_pass.clone();
        settings.site_logins = self.settings.site_logins.clone();
        settings.debrid_accounts = self.settings.debrid_accounts.clone();
        settings.launch_on_startup = self.settings.launch_on_startup;
        settings.remote_on = false;
        settings.automation_api = true;

        for torrent in &plan.torrent_metadata {
            crate::torrents::save_recovery_torrent(&torrent.hash, &torrent.bytes)
                .map_err(|error| format!("Could not save restored torrent metadata: {error}"))?;
        }

        let names: Vec<_> = plan
            .torrent_metadata
            .iter()
            .map(|torrent| (torrent.hash.clone(), torrent.renamed_file.clone()))
            .collect();
        let session = crate::torrents::state_dir()
            .ok_or("No torrent state folder is available.")?
            .join("session");
        let previous_names = mdm_torrent::rename_plugin::restore_renamed_files(&session, &names)
            .map_err(|error| format!("Could not save restored torrent names: {error}"))?;
        self.saver.flush();
        let original_count = self.items.len();
        self.items.append(&mut plan.items);
        if let Err(error) = store::save(
            next_id,
            &self.items,
            &self.list.layout(),
            &settings,
            &queues,
        ) {
            self.items.truncate(original_count);
            let rollback =
                mdm_torrent::rename_plugin::restore_renamed_files(&session, &previous_names);
            return Err(match rollback {
                Ok(_) => format!("Could not save the restored download list: {error}."),
                Err(rollback) => format!(
                    "Could not save the restored download list: {error}. Torrent name rollback also failed: {rollback}."
                ),
            });
        }
        self.next_id = next_id;
        self.queues = queues;
        self.apply_options(settings);
        self.last_save = Instant::now();

        Ok(json!({
            "path": archive,
            "restored_to": root,
            "downloads": self.items.len() - original_count,
            "ui_complete": plan.appearance.is_some(),
            "ui": plan.appearance,
            "startup": plan.startup,
        }))
    }
}

fn remap_packages(restored: &mut [Item], existing: &[Item]) -> Result<(), String> {
    let mut next = existing
        .iter()
        .filter_map(|item| item.package.as_ref().map(|p| p.id))
        .max()
        .unwrap_or(0);
    let mut packages = HashMap::new();
    for item in restored {
        if let Some(package) = &mut item.package {
            if let Some(id) = packages.get(&package.id) {
                package.id = *id;
            } else {
                next = next
                    .checked_add(1)
                    .ok_or("The package history has no free IDs.")?;
                packages.insert(package.id, next);
                package.id = next;
            }
        }
    }
    Ok(())
}
