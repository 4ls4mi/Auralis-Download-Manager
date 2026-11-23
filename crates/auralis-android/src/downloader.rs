use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use mdm_engine::download::State;
use mdm_engine::limiter::Limiter;
use mdm_engine::naming::part_path;
use mdm_engine::safe_move::open_download_file;
use mdm_engine::state::{ResumeState, state_path};
use mdm_engine::{Destination, Download, Error, Options, Request};
use serde::Serialize;
use tokio::runtime::{Builder, Runtime};
use tokio_util::sync::CancellationToken;
use url::Url;

const MAX_CONNECTIONS: u32 = 16;
const MAX_RETRIES: u32 = 5;
const MAX_CHECKPOINT_SIZE: u64 = 32 * 1024 * 1024;
const SAMPLE_INTERVAL: Duration = Duration::from_millis(250);

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
enum Status {
    Downloading,
    Paused,
    Completed,
    Error,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct Progress {
    state: Status,
    downloaded: u64,
    total: Option<u64>,
    rate: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl Progress {
    fn new(state: Status) -> Self {
        Self {
            state,
            downloaded: 0,
            total: None,
            rate: 0,
            error: None,
        }
    }
}

struct Transfer {
    progress: Mutex<Progress>,
    cancel: CancellationToken,
}

pub(crate) struct Downloader {
    runtime: Runtime,
    files: PathBuf,
    transfers: Mutex<HashMap<String, Arc<Transfer>>>,
    rate_limit: Arc<Limiter>,
}

impl Downloader {
    pub(crate) fn new(files: &Path) -> Result<Self, String> {
        let files = fs::canonicalize(files)
            .ok()
            .filter(|path| path.is_dir())
            .ok_or_else(|| "Android app storage is unavailable.".to_owned())?;
        let runtime = Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("auralis-download")
            .enable_all()
            .build()
            .map_err(|e| format!("Could not start the download engine: {e}"))?;
        Ok(Self {
            runtime,
            files,
            transfers: Mutex::new(HashMap::new()),
            rate_limit: Arc::new(Limiter::new(None)),
        })
    }

    pub(crate) fn start(
        &self,
        id: String,
        url: &str,
        target: &Path,
        connections: i32,
        automatic_retries: i32,
    ) -> Result<(), String> {
        let target = self.destination(&id, target)?;
        let mut url = Url::parse(url.trim()).map_err(|_| "Enter a valid HTTP or HTTPS link.")?;
        if !http_url(&url) {
            return Err("Enter an HTTP or HTTPS link without embedded credentials.".into());
        }
        url.set_fragment(None);
        let options = self.options(connections, automatic_retries)?;

        let mut transfers = lock(&self.transfers);
        if transfers
            .get(&id)
            .is_some_and(|job| lock(&job.progress).state == Status::Downloading)
        {
            return Err("This download is still running or pausing.".into());
        }
        let job = Arc::new(Transfer {
            progress: Mutex::new(Progress::new(Status::Downloading)),
            cancel: CancellationToken::new(),
        });
        transfers.insert(id, Arc::clone(&job));
        self.runtime.spawn(run(job, url, target, options));
        Ok(())
    }

    fn options(&self, connections: i32, automatic_retries: i32) -> Result<Options, String> {
        let max_connections = match u32::try_from(connections) {
            Ok(count @ 1..=MAX_CONNECTIONS) => count,
            _ => return Err(format!("Use 1 to {MAX_CONNECTIONS} connections.")),
        };
        let max_retries = match u32::try_from(automatic_retries) {
            Ok(count @ 0..=MAX_RETRIES) => count,
            _ => return Err(format!("Use 0 to {MAX_RETRIES} automatic retries.")),
        };
        Ok(Options {
            max_connections,
            max_retries,
            global: Some(Arc::clone(&self.rate_limit)),
            ..Options::default()
        })
    }

    pub(crate) fn set_rate_limit(&self, bytes_per_second: i64) -> Result<(), String> {
        let rate =
            u64::try_from(bytes_per_second).map_err(|_| "Speed limit cannot be negative.")?;
        self.rate_limit.set((rate != 0).then_some(rate));
        Ok(())
    }

    fn destination(&self, id: &str, target: &Path) -> Result<PathBuf, String> {
        if id.is_empty()
            || id.len() > 64
            || !id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
        {
            return Err("Invalid download identifier.".into());
        }
        let parent = target
            .parent()
            .filter(|_| target.is_absolute() && target.file_name() == Some("transfer".as_ref()))
            .and_then(|path| fs::canonicalize(path).ok())
            .filter(|path| *path == self.files.join("staging").join(id) && path.is_dir())
            .ok_or_else(|| {
                "The download folder is outside app storage or unavailable.".to_owned()
            })?;
        let target = parent.join("transfer");
        ensure_not_completed(&target)?;
        Ok(target)
    }

    pub(crate) fn snapshot(&self, id: &str) -> Option<Progress> {
        let job = lock(&self.transfers).get(id).cloned()?;
        let progress = lock(&job.progress).clone();
        Some(progress)
    }

    pub(crate) fn pause(&self, id: &str) -> Result<(), String> {
        let transfers = lock(&self.transfers);
        let job = transfers.get(id).ok_or("Download not found.")?;
        job.cancel.cancel();
        Ok(())
    }

    pub(crate) fn forget(&self, id: &str) {
        let mut transfers = lock(&self.transfers);
        if transfers
            .get(id)
            .is_some_and(|job| lock(&job.progress).state != Status::Downloading)
        {
            transfers.remove(id);
        }
    }
}

fn http_url(url: &Url) -> bool {
    matches!(url.scheme(), "http" | "https")
        && url.host_str().is_some()
        && url.username().is_empty()
        && url.password().is_none()
}

fn ensure_not_completed(target: &Path) -> Result<(), String> {
    match fs::symlink_metadata(target) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Ok(_) => Err("A file already exists at the download destination.".into()),
        Err(error) => Err(format!(
            "Could not inspect the download destination: {error}"
        )),
    }
}

fn checkpoint(target: &Path, url: &Url) -> Result<Option<ResumeState>, String> {
    let path = state_path(target);
    let metadata = match fs::symlink_metadata(&path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(format!(
                "Could not inspect saved download progress: {error}"
            ));
        }
        Ok(metadata) => metadata,
    };
    if !metadata.is_file() || metadata.len() > MAX_CHECKPOINT_SIZE {
        return Err("The saved download progress is invalid.".into());
    }
    let saved = ResumeState::load(&path).map_err(|_| "The saved download progress is invalid.")?;
    // A restart must never switch to another file or use an unrelated checkpoint.
    if saved.dest != target || saved.url != *url || !http_url(&saved.final_url) {
        return Err("The saved download progress does not match this transfer.".into());
    }
    let part = open_download_file(&part_path(target), false)
        .map_err(|_| "The saved partial download is missing or unavailable.")?;
    if part.metadata().map(|metadata| metadata.len()).ok() != Some(saved.size) {
        return Err("The saved partial download has an unexpected size.".into());
    }
    Ok(Some(saved))
}

fn saved_bytes(saved: &ResumeState) -> u64 {
    saved.segments.iter().fold(0u64, |bytes, segment| {
        bytes
            .saturating_add(segment.cursor.saturating_sub(segment.start))
            .min(saved.size)
    })
}

async fn read_checkpoint(target: &Path, url: &Url) -> Result<Option<ResumeState>, String> {
    let target = target.to_owned();
    let url = url.clone();
    tokio::task::spawn_blocking(move || checkpoint(&target, &url))
        .await
        .map_err(|_| "Could not read the saved download progress.")?
}

async fn run(job: Arc<Transfer>, url: Url, target: PathBuf, options: Options) {
    let result = run_download(&job, &url, &target, options).await;
    let terminal = match result {
        Ok(progress) => progress,
        Err(error) => {
            let saved = read_checkpoint(&target, &url).await.ok().flatten();
            let mut progress = lock(&job.progress).clone();
            progress.state = Status::Error;
            progress.rate = 0;
            if let Some(saved) = saved {
                progress.downloaded = saved_bytes(&saved);
                progress.total = Some(saved.size);
            }
            progress.error = Some(error);
            progress
        }
    };
    *lock(&job.progress) = terminal;
}

async fn run_download(
    job: &Transfer,
    url: &Url,
    target: &Path,
    options: Options,
) -> Result<Progress, String> {
    let saved = read_checkpoint(target, url).await?;
    if job.cancel.is_cancelled() {
        return Ok(paused(saved.as_ref(), None));
    }
    ensure_not_completed(target)?;
    let download = if let Some(saved) = saved {
        {
            let mut progress = lock(&job.progress);
            progress.downloaded = saved_bytes(&saved);
            progress.total = Some(saved.size);
        }
        Download::resume(state_path(target), Default::default(), options)
            .map_err(|error| error.to_string())?
    } else {
        Download::start(
            Request {
                url: url.clone(),
                headers: Default::default(),
                dest: Destination::File(target.to_owned()),
            },
            options,
        )
    };

    let mut samples = tokio::time::interval(SAMPLE_INTERVAL);
    samples.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            () = job.cancel.cancelled() => {
                download.cancel();
                break;
            }
            _ = samples.tick() => {
                if download.is_finished() {
                    break;
                }
                let sample = download.snapshot();
                let mut progress = lock(&job.progress);
                // The first probe of a resumed download does not yet have its ranges.
                if sample.state != State::Probing || sample.size.is_some() {
                    progress.total = sample.size;
                    progress.downloaded = sample.downloaded;
                }
                progress.rate = sample.connections.iter().map(|connection| connection.speed)
                    .fold(0u64, u64::saturating_add);
            }
        }
    }

    // A waiter task contains an engine panic after its own write task has finished.
    // Do not report a terminal state while a checkpoint or rename is still in flight.
    let result = tokio::spawn(download.wait())
        .await
        .map_err(|_| "The download engine stopped unexpectedly.")?;
    match result {
        Ok(outcome) if outcome.path == target => Ok(Progress {
            state: Status::Completed,
            downloaded: outcome.size,
            total: Some(outcome.size),
            rate: 0,
            error: None,
        }),
        Ok(_) => Err("A different file appeared at the download destination.".into()),
        Err(Error::Cancelled) => {
            let total = lock(&job.progress).total;
            let saved = read_checkpoint(target, url).await?;
            Ok(paused(saved.as_ref(), total))
        }
        Err(error) => Err(error.to_string()),
    }
}

fn paused(saved: Option<&ResumeState>, total: Option<u64>) -> Progress {
    let mut progress = Progress::new(Status::Paused);
    progress.total = total;
    if let Some(saved) = saved {
        progress.downloaded = saved_bytes(saved);
        progress.total = Some(saved.size);
    }
    progress
}

#[cfg(test)]
mod tests {
    use super::*;
    use mdm_engine::state::Validators;

    #[test]
    fn only_uses_the_transfer_directory_and_never_reuses_a_completed_file() {
        let files = tempfile::tempdir().unwrap();
        let engine = Downloader::new(files.path()).unwrap();
        let folder = files.path().join("staging/first");
        fs::create_dir_all(&folder).unwrap();
        let target = folder.join("transfer");

        assert_eq!(
            engine.destination("first", &target).unwrap(),
            folder.canonicalize().unwrap().join("transfer")
        );
        assert!(engine.destination("second", &target).is_err());
        assert!(engine.destination("../first", &target).is_err());
        assert!(engine.destination("first", &folder.join("other")).is_err());

        fs::write(&target, b"completed").unwrap();
        assert!(
            engine
                .start("first".into(), "https://example.com/file", &target, 8, 5)
                .is_err()
        );
        assert_eq!(fs::read(&target).unwrap(), b"completed");
        assert!(engine.snapshot("first").is_none());
    }

    #[test]
    fn resumes_only_a_checkpoint_with_the_same_identity_and_real_partial() {
        let files = tempfile::tempdir().unwrap();
        let target = files.path().join("transfer");
        let url = Url::parse("https://example.com/file").unwrap();
        let other = Url::parse("https://example.com/other").unwrap();
        let part = part_path(&target);
        let state = state_path(&target);

        fs::write(&part, [0u8; 32]).unwrap();
        assert!(checkpoint(&target, &url).unwrap().is_none());
        let saved = ResumeState::new(
            url.clone(),
            url.clone(),
            target.clone(),
            32,
            Validators::default(),
        );
        saved.write(&state).unwrap();
        assert_eq!(checkpoint(&target, &url).unwrap(), Some(saved));
        assert!(checkpoint(&target, &other).is_err());
        fs::write(&part, [0u8; 16]).unwrap();
        assert!(checkpoint(&target, &url).is_err());
    }

    #[test]
    fn pause_requests_cancellation_without_releasing_the_running_worker() {
        let files = tempfile::tempdir().unwrap();
        let engine = Downloader::new(files.path()).unwrap();
        let job = Arc::new(Transfer {
            progress: Mutex::new(Progress::new(Status::Downloading)),
            cancel: CancellationToken::new(),
        });
        lock(&engine.transfers).insert("first".into(), Arc::clone(&job));

        engine.pause("first").unwrap();
        assert!(job.cancel.is_cancelled());
        engine.forget("first");
        assert_eq!(engine.snapshot("first").unwrap().state, Status::Downloading);

        lock(&job.progress).state = Status::Paused;
        engine.forget("first");
        assert!(engine.snapshot("first").is_none());
    }

    #[test]
    fn valid_transfer_options_share_a_live_rate_limit() {
        let files = tempfile::tempdir().unwrap();
        let engine = Downloader::new(files.path()).unwrap();
        let first = engine.options(1, 0).unwrap();
        let second = engine.options(16, 5).unwrap();
        assert_eq!((first.connections(), first.max_retries), (1, 0));
        assert_eq!((second.connections(), second.max_retries), (16, 5));
        assert!(engine.options(0, 5).is_err());
        assert!(engine.options(17, 5).is_err());
        assert!(engine.options(8, -1).is_err());
        assert!(engine.options(8, 6).is_err());

        let first = first.global.unwrap();
        let second = second.global.unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(first.get(), None);
        engine.set_rate_limit(128 * 1024).unwrap();
        assert!(engine.set_rate_limit(-1).is_err());
        assert_eq!(first.get(), Some(128 * 1024));
        assert_eq!(second.get(), Some(128 * 1024));
        engine.set_rate_limit(0).unwrap();
        assert_eq!(first.get(), None);
        assert_eq!(second.get(), None);
    }
}
