use std::fs::{self, Metadata};
use std::io::{self, Read};
use std::path::{Component, Path, PathBuf};

const MIGRATED: &str = ".legacy-helpers-checked";
const MAX_METADATA: u64 = 64 * 1024;
const MAX_VERSION_BYTES: u64 = 384 * 1024 * 1024;
const MAX_VERSION_ENTRIES: usize = 10_000;
const MAX_VERSION_DEPTH: usize = 24;

pub(crate) fn configure(profile: &Path) {
    let Some(destination) = default_helper_dir(dirs::data_dir().as_deref(), profile) else {
        return;
    };
    if let Err(error) = migrate(profile, &destination) {
        tracing::warn!("Could not migrate Auralis helper settings: {error}");
    }
    mdm_tools::set_tools_dir(destination);
}

fn default_helper_dir(base: Option<&Path>, profile: &Path) -> Option<PathBuf> {
    let base = base?;
    // A portable profile lives next to its executable and keeps its own tools.
    (profile == base.join("misterdownloadmanager")).then(|| base.join("Auralis").join("tools"))
}

fn read_metadata(path: &Path) -> io::Result<Option<Vec<u8>>> {
    let metadata = match std::fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    if linked(&metadata) || !metadata.is_file() || metadata.len() > MAX_METADATA {
        return Ok(None);
    }
    let mut bytes = Vec::new();
    std::fs::File::open(path)?
        .take(MAX_METADATA + 1)
        .read_to_end(&mut bytes)?;
    Ok((bytes.len() as u64 <= MAX_METADATA).then_some(bytes))
}

fn was_used_by_auralis(profile: &Path) -> io::Result<bool> {
    let version = read_metadata(&profile.join("auralis-interface-version"))?;
    let version = version
        .as_deref()
        .and_then(|bytes| std::str::from_utf8(bytes).ok())
        .unwrap_or("")
        .trim();
    Ok(!version.is_empty()
        && version.len() <= 32
        && version
            .bytes()
            .all(|byte| byte.is_ascii_digit() || byte == b'.' || byte == b'-'))
}

fn migrate(profile: &Path, destination: &Path) -> io::Result<()> {
    let marker = destination.join(MIGRATED);
    if marker.is_file() {
        return Ok(());
    }
    mdm_ipc::private_dir(destination)?;
    if was_used_by_auralis(profile)? {
        let legacy = profile.join("tools");
        let chosen = destination.join("programs.json");
        if !chosen.exists()
            && let Some(metadata) = read_metadata(&legacy.join("programs.json"))?
        {
            craft_atomic::atomic_write(&chosen, &metadata)?;
        }
        for helper in ["yt-dlp", "ffmpeg", "gallery-dl"] {
            retain_installed(&legacy.join(helper), &destination.join(helper))?;
        }
    }
    craft_atomic::atomic_write(&marker, b"\n")
}

fn retain_installed(legacy: &Path, destination: &Path) -> io::Result<()> {
    let current = destination.join("current.json");
    if current.exists() {
        return Ok(());
    }
    let Some(metadata) = read_metadata(&legacy.join("current.json"))? else {
        return Ok(());
    };
    let Ok(mut installed) = serde_json::from_slice::<mdm_tools::Installed>(&metadata) else {
        return Ok(());
    };
    let Ok(relative) = installed.exe.strip_prefix(legacy) else {
        return Ok(());
    };
    if !installed.exe.is_file()
        || !relative
            .components()
            .all(|part| matches!(part, Component::Normal(_)))
    {
        return Ok(());
    }
    let Ok(resolved_legacy) = legacy.canonicalize() else {
        return Ok(());
    };
    if !installed
        .exe
        .canonicalize()
        .is_ok_and(|path| path.starts_with(resolved_legacy))
    {
        return Ok(());
    }
    fs::create_dir_all(destination)?;
    if !plain_directory(destination) {
        return Ok(());
    }
    let migrated = match copy_managed_version(legacy, destination, relative, &installed.version) {
        Ok(Some(exe)) => {
            installed.exe = exe;
            serde_json::to_vec_pretty(&installed).map_err(io::Error::other)?
        }
        Ok(None) => metadata,
        Err(error) => {
            tracing::warn!(
                "Keeping a working legacy helper after migration could not copy it: {error}"
            );
            metadata
        }
    };
    craft_atomic::atomic_write(&current, &migrated)
}

fn linked(metadata: &Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        // FILE_ATTRIBUTE_REPARSE_POINT includes junctions as well as symlinks.
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    metadata.file_type().is_symlink()
}

fn plain_directory(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|meta| meta.is_dir() && !linked(&meta))
}

fn version_folder<'a>(relative: &'a Path, version: &str) -> Option<&'a Path> {
    let parent = relative.parent()?;
    let folder = parent.to_str()?;
    // The folder build may have a numeric suffix when another copy of that
    // version was already installed.
    let matches_version = folder == version
        || folder
            .strip_prefix(version)
            .and_then(|suffix| suffix.strip_prefix('-'))
            .is_some_and(|index| index.parse::<u32>().is_ok());
    (!version.is_empty()
        && !version.starts_with('.')
        && version
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._+-".contains(&byte))
        && matches_version)
        .then_some(parent)
}

fn copy_managed_version(
    legacy: &Path,
    destination: &Path,
    relative: &Path,
    version: &str,
) -> io::Result<Option<PathBuf>> {
    let Some(folder) = version_folder(relative, version) else {
        return Ok(None);
    };
    // The helper and profile folders must refer to real directories along
    // the legacy path. Do not import content behind a link or a junction.
    if !legacy.ancestors().take(3).all(plain_directory) {
        return Ok(None);
    }
    let target = destination.join(folder);
    match fs::symlink_metadata(&target) {
        Ok(_) => return Ok(None),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    let staging = destination.join(format!(".auralis-import-{}", std::process::id()));
    fs::create_dir(&staging)?;
    let staged_version = staging.join(folder);
    let result = CopyBudget {
        bytes: MAX_VERSION_BYTES,
        entries: MAX_VERSION_ENTRIES,
    }
    .copy_tree(&legacy.join(folder), &staged_version, 0)
    .and_then(|()| {
        if !staging.join(relative).is_file() {
            return Err(io::Error::other(
                "helper executable was missing from the copied version",
            ));
        }
        fs::rename(&staged_version, &target)
    });
    let _ = fs::remove_dir_all(staging);
    result.map(|()| Some(destination.join(relative)))
}

struct CopyBudget {
    bytes: u64,
    entries: usize,
}

impl CopyBudget {
    fn copy_tree(&mut self, source: &Path, destination: &Path, depth: usize) -> io::Result<()> {
        let limit = || io::Error::other("helper version directory exceeds migration limits");
        self.entries = self.entries.checked_sub(1).ok_or_else(limit)?;
        if depth > MAX_VERSION_DEPTH {
            return Err(limit());
        }
        let metadata = fs::symlink_metadata(source)?;
        if linked(&metadata) || !(metadata.is_file() || metadata.is_dir()) {
            return Err(io::Error::other(
                "helper version directory contains a link or special file",
            ));
        }
        if metadata.is_dir() {
            fs::create_dir(destination)?;
            for entry in fs::read_dir(source)? {
                let entry = entry?;
                self.copy_tree(
                    &entry.path(),
                    &destination.join(entry.file_name()),
                    depth + 1,
                )?;
            }
        } else {
            self.bytes = self.bytes.checked_sub(metadata.len()).ok_or_else(limit)?;
            if fs::copy(source, destination)? != metadata.len() {
                return Err(io::Error::other("helper file changed during migration"));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_current(root: &Path, exe: &Path) -> Vec<u8> {
        std::fs::create_dir_all(root).unwrap();
        let bytes = serde_json::to_vec(&mdm_tools::Installed {
            version: "1.2.3".to_owned(),
            exe: exe.to_owned(),
        })
        .unwrap();
        std::fs::write(root.join("current.json"), &bytes).unwrap();
        bytes
    }

    #[test]
    fn only_the_default_profile_gets_the_auralis_tools_folder() {
        let root = tempfile::tempdir().unwrap();
        let base = root.path();
        assert_eq!(
            default_helper_dir(Some(base), &base.join("misterdownloadmanager")),
            Some(base.join("Auralis/tools"))
        );
        assert_eq!(
            default_helper_dir(Some(base), &base.join("portable/data")),
            None
        );
        assert_eq!(default_helper_dir(None, &base.join("custom")), None);
    }

    #[test]
    fn an_existing_auralis_profile_retains_working_tools_and_choices() {
        let root = tempfile::tempdir().unwrap();
        let profile = root.path().join("misterdownloadmanager");
        let destination = root.path().join("Auralis/tools");
        let legacy = profile.join("tools");
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(profile.join("auralis-interface-version"), "0.3.71").unwrap();
        let custom = root.path().join("custom-yt-dlp");
        std::fs::write(&custom, b"custom program").unwrap();
        let chosen = serde_json::to_vec(&serde_json::json!({
            "yt-dlp": {"version": "2026.10.26", "exe": custom}
        }))
        .unwrap();
        std::fs::write(legacy.join("programs.json"), &chosen).unwrap();
        let helpers = ["yt-dlp", "ffmpeg", "gallery-dl"];
        let fixtures = helpers.map(|helper| {
            let dir = legacy.join(helper);
            let version = if helper == "yt-dlp" {
                "1.2.3-2"
            } else {
                "1.2.3"
            };
            let exe = dir.join(version).join("program");
            let sibling = exe.with_file_name("support").join("library");
            std::fs::create_dir_all(exe.parent().unwrap()).unwrap();
            std::fs::write(&exe, b"program").unwrap();
            std::fs::create_dir_all(sibling.parent().unwrap()).unwrap();
            std::fs::write(&sibling, b"support library").unwrap();
            let metadata = write_current(&dir, &exe);
            (helper, dir, exe, sibling, metadata)
        });
        migrate(&profile, &destination).unwrap();
        for (helper, dir, exe, sibling, metadata) in fixtures {
            let installed: mdm_tools::Installed = serde_json::from_slice(
                &std::fs::read(destination.join(helper).join("current.json")).unwrap(),
            )
            .unwrap();
            assert_eq!(installed.version, "1.2.3");
            assert_eq!(
                installed.exe,
                destination.join(exe.strip_prefix(&legacy).unwrap())
            );
            assert_eq!(std::fs::read(installed.exe).unwrap(), b"program");
            assert_eq!(
                std::fs::read(destination.join(sibling.strip_prefix(&legacy).unwrap())).unwrap(),
                b"support library"
            );
            assert_eq!(std::fs::read(dir.join("current.json")).unwrap(), metadata);
            assert_eq!(std::fs::read(exe).unwrap(), b"program");
            assert_eq!(std::fs::read(sibling).unwrap(), b"support library");
        }
        assert_eq!(
            std::fs::read(destination.join("programs.json")).unwrap(),
            chosen
        );
    }

    #[test]
    fn a_new_auralis_profile_does_not_adopt_a_standalone_installation() {
        let root = tempfile::tempdir().unwrap();
        let profile = root.path().join("misterdownloadmanager");
        let destination = root.path().join("Auralis/tools");
        let legacy = profile.join("tools");
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(legacy.join("programs.json"), "{}").unwrap();
        migrate(&profile, &destination).unwrap();
        std::fs::write(profile.join("auralis-interface-version"), "0.3.71").unwrap();
        migrate(&profile, &destination).unwrap();
        assert!(!destination.join("programs.json").exists());
        assert_eq!(std::fs::read(legacy.join("programs.json")).unwrap(), b"{}");
    }

    #[test]
    fn invalid_legacy_targets_and_existing_auralis_metadata_are_left_alone() {
        let root = tempfile::tempdir().unwrap();
        let profile = root.path().join("misterdownloadmanager");
        let destination = root.path().join("Auralis/tools");
        let legacy = profile.join("tools");
        let unrelated = root.path().join("external-program");
        std::fs::write(&unrelated, b"unrelated").unwrap();
        write_current(&legacy.join("gallery-dl"), &unrelated);
        write_current(&legacy.join("ffmpeg"), &legacy.join("ffmpeg/absent"));
        let old_ytdlp = legacy.join("yt-dlp/old-program");
        write_current(&legacy.join("yt-dlp"), &old_ytdlp);
        std::fs::write(old_ytdlp, b"old program").unwrap();
        std::fs::create_dir_all(destination.join("yt-dlp")).unwrap();
        let current = destination.join("yt-dlp/current.json");
        std::fs::write(&current, b"newer entry").unwrap();
        std::fs::write(profile.join("auralis-interface-version"), "0.3.71").unwrap();
        migrate(&profile, &destination).unwrap();
        assert!(!destination.join("gallery-dl/current.json").exists());
        assert!(!destination.join("ffmpeg/current.json").exists());
        assert_eq!(std::fs::read(&current).unwrap(), b"newer entry");
    }

    #[test]
    fn unrecognized_layouts_keep_the_usable_legacy_pointer() {
        let root = tempfile::tempdir().unwrap();
        let legacy = root.path().join("tools/ffmpeg");
        let destination = root.path().join("Auralis/tools/ffmpeg");
        let exe = legacy.join("old-layout/ffmpeg.exe");
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&exe, b"legacy program").unwrap();
        let original = write_current(&legacy, &exe);
        retain_installed(&legacy, &destination).unwrap();
        assert_eq!(
            fs::read(destination.join("current.json")).unwrap(),
            original
        );
        assert!(!destination.join("old-layout").exists());
        assert_eq!(fs::read(exe).unwrap(), b"legacy program");
    }

    #[cfg(unix)]
    #[test]
    fn linked_version_content_falls_back_without_publishing_a_partial_copy() {
        let root = tempfile::tempdir().unwrap();
        let legacy = root.path().join("misterdownloadmanager/tools/yt-dlp");
        let destination = root.path().join("Auralis/tools/yt-dlp");
        let exe = legacy.join("1.2.3/yt-dlp");
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&exe, b"legacy program").unwrap();
        std::os::unix::fs::symlink(&exe, exe.with_file_name("linked-file")).unwrap();
        let original = write_current(&legacy, &exe);
        retain_installed(&legacy, &destination).unwrap();
        assert_eq!(
            fs::read(destination.join("current.json")).unwrap(),
            original
        );
        assert_eq!(fs::read_dir(&destination).unwrap().count(), 1);
        assert_eq!(fs::read(exe).unwrap(), b"legacy program");
    }

    #[cfg(unix)]
    #[test]
    fn a_linked_executable_outside_the_legacy_helper_is_not_adopted() {
        let root = tempfile::tempdir().unwrap();
        let legacy = root.path().join("misterdownloadmanager/tools/yt-dlp");
        let destination = root.path().join("Auralis/tools/yt-dlp");
        let exe = legacy.join("1.2.3/yt-dlp");
        let unrelated = root.path().join("external-program");
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&unrelated, b"unrelated").unwrap();
        std::os::unix::fs::symlink(&unrelated, &exe).unwrap();
        write_current(&legacy, &exe);
        retain_installed(&legacy, &destination).unwrap();
        assert!(!destination.exists());
    }

    #[test]
    fn copying_stops_at_the_byte_budget() {
        let root = tempfile::tempdir().unwrap();
        let file = root.path().join("original");
        let dest = root.path().join("copy");
        fs::write(&file, b"too large").unwrap();
        let mut budget = CopyBudget {
            bytes: 1,
            entries: 10,
        };
        assert!(budget.copy_tree(&file, &dest, 0).is_err());
        assert!(!dest.exists());
    }
}
