//! Conservative repair of damaged checkpoints from the same HTTP source.
//! Local hashes detect changes since checkpointing; they do not authenticate
//! bytes originally received from the server.
use crate::{
    download::{self, Options},
    naming,
    state::{ResumeState, state_path},
};
use reqwest::{
    StatusCode,
    header::{self, HeaderMap, HeaderValue},
};
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};
use url::Url;

#[derive(Debug, thiserror::Error)]
pub enum RepairError {
    #[error("{0}")]
    Refused(&'static str),
    #[error("download is already in use")]
    InUse,
    #[error("cannot read saved state: {0}")]
    State(String),
    #[error("could not check the saved data: {0}")]
    Disk(#[from] io::Error),
    #[error("could not check the source: {0}")]
    Network(#[from] download::Error),
    #[error("could not check the source: {0}")]
    Request(#[from] reqwest::Error),
}
#[derive(Debug)]
pub struct RepairPrepared {
    pub damaged_ranges: Vec<(u64, u64)>,
    pub unhashed_bytes: u64,
    pub retained_bytes: u64,
    pub state_backup: PathBuf,
}
fn same_origin(a: &Url, b: &Url) -> bool {
    a.scheme() == b.scheme()
        && a.host_str() == b.host_str()
        && a.port_or_known_default() == b.port_or_known_default()
}
fn backup_state(path: &Path, bytes: &[u8]) -> io::Result<PathBuf> {
    for index in 0..1000 {
        let mut name = path.as_os_str().to_owned();
        name.push(format!(".before-repair-{index}"));
        let target = PathBuf::from(name);
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&target) {
            Ok(mut file) => {
                let result = file.write_all(bytes).and_then(|()| file.sync_all());
                drop(file);
                if let Err(error) = result {
                    let _ = fs::remove_file(&target);
                    return Err(error);
                }
                return Ok(target);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not reserve a state backup",
    ))
}

/// Verify saved blocks and the original HTTP source before marking only damaged
/// ranges as missing. It never modifies the partial file. No redirect, POST,
/// browser-only connection or unlocked source is accepted by this conservative
/// first implementation. Callers must keep the download stopped throughout.
pub async fn prepare_http_repair(
    path: &Path,
    mut headers: HeaderMap,
    opts: &Options,
) -> Result<RepairPrepared, RepairError> {
    let original = fs::read(path)?;
    let saved = ResumeState::load(path).map_err(RepairError::State)?;
    if state_path(&saved.dest) != path {
        return Err(RepairError::Refused(
            "The state file does not belong to this download.",
        ));
    }
    let _reservation = naming::reserve(&saved.dest).ok_or(RepairError::InUse)?;
    if !matches!(saved.final_url.scheme(), "http" | "https")
        || saved.url != saved.final_url
        || saved.browser_like
        || opts.post.is_some()
        || opts.unlocker.is_some()
        || saved.size == 0
    {
        return Err(RepairError::Refused(
            "This download needs a different recovery method.",
        ));
    }
    let host = saved.final_url.host_str();
    let etag = saved
        .validators
        .etag
        .as_deref()
        .filter(|value| value.len() >= 2 && value.starts_with('"') && value.ends_with('"'))
        .filter(|_| saved.validators.etag_host.as_deref() == host);
    let (validator, field) = if let Some(etag) = etag {
        (etag, header::ETAG)
    } else if !opts.ignore_mtime {
        (
            saved
                .validators
                .last_modified
                .as_deref()
                .ok_or(RepairError::Refused(
                    "The server did not provide a usable file validator.",
                ))?,
            header::LAST_MODIFIED,
        )
    } else {
        return Err(RepairError::Refused(
            "The server did not provide a usable file validator.",
        ));
    };
    let validator = HeaderValue::from_str(validator)
        .map_err(|_| RepairError::Refused("The saved file validator is invalid."))?;
    let inspect = saved.clone();
    let (plan, report) = tokio::task::spawn_blocking(move || inspect.proposed_repair())
        .await
        .map_err(|_| RepairError::Refused("The saved-data check could not finish."))??;
    if report.damaged_ranges.is_empty() {
        return Err(RepairError::Refused(
            "No damaged checkpoint ranges were found.",
        ));
    }
    headers.remove(header::RANGE);
    headers.remove(header::IF_RANGE);
    let client = download::hop_client(opts, &saved.final_url)?;
    let response = client
        .get(saved.final_url.clone())
        .headers(headers)
        .header(header::RANGE, "bytes=0-0")
        .header(header::IF_RANGE, validator.clone())
        .send()
        .await?;
    if response.status() != StatusCode::PARTIAL_CONTENT
        || !same_origin(response.url(), &saved.final_url)
        || response.headers().get(field) != Some(&validator)
        || response
            .headers()
            .get(header::CONTENT_RANGE)
            .and_then(|v| v.to_str().ok())
            != Some(format!("bytes 0-0/{}", saved.size).as_str())
    {
        return Err(RepairError::Refused(
            "The source did not confirm the same file and byte-range support.",
        ));
    }
    drop(response);
    if fs::read(path)? != original {
        return Err(RepairError::Refused(
            "Saved state changed during the check. Try again.",
        ));
    }
    let inspect = saved.clone();
    let (mut current_plan, current_report) =
        tokio::task::spawn_blocking(move || inspect.proposed_repair())
            .await
            .map_err(|_| RepairError::Refused("The saved-data check could not finish."))??;
    if plan != current_plan || report != current_report || fs::read(path)? != original {
        return Err(RepairError::Refused(
            "Saved data changed during the check. Try again.",
        ));
    }
    let backup = backup_state(path, &original)?;
    current_plan.repair_strict = true;
    current_plan.write(path)?;
    Ok(RepairPrepared {
        damaged_ranges: report.damaged_ranges,
        unhashed_bytes: report.unhashed_bytes,
        retained_bytes: current_plan.downloaded(),
        state_backup: backup,
    })
}
