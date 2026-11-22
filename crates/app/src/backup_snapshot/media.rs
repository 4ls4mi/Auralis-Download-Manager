//! Files owned by video, gallery, and account-based downloads.
use crate::model::{Item, Status};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs,
    io::ErrorKind,
    path::{Component, Path, PathBuf},
};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(super) enum MediaKind {
    SideVideo,
    VideoPart,
    FolderFile,
    Sidecar,
    PartialVideo,
}

pub(super) struct MediaFile {
    pub source: PathBuf,
    pub relative: PathBuf,
    pub kind: MediaKind,
}

pub(super) fn is_folder(item: &Item) -> bool {
    item.gallery.is_some() || (item.remote.is_some() && item.dest.is_dir())
}

pub(super) fn validate_kind(item: &Item, kind: MediaKind, media_folder: bool) -> bool {
    match kind {
        MediaKind::FolderFile => {
            media_folder
                && (item.gallery.is_some()
                    || (item.remote.is_some() && item.status == Status::Complete))
        }
        MediaKind::SideVideo | MediaKind::VideoPart => !media_folder && item.video.is_some(),
        MediaKind::Sidecar | MediaKind::PartialVideo => {
            !media_folder && item.video.is_some() && item.status != Status::Complete
        }
    }
}

fn is_link(stat: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        stat.file_attributes() & 0x400 != 0 // FILE_ATTRIBUTE_REPARSE_POINT
    }
    #[cfg(not(windows))]
    stat.file_type().is_symlink()
}

fn available(path: &Path) -> Result<Option<fs::Metadata>, String> {
    match fs::symlink_metadata(path) {
        Ok(stat) if is_link(&stat) => {
            Err(format!("A saved media path is a link: {}", path.display()))
        }
        Ok(stat) => Ok(Some(stat)),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Could not read {}: {error}", path.display())),
    }
}

fn regular(path: &Path) -> Result<(), String> {
    if available(path)?.is_some_and(|stat| stat.is_file()) {
        Ok(())
    } else {
        Err(format!(
            "A saved media file is unavailable: {}",
            path.display()
        ))
    }
}

fn relative(base: &Path, path: &Path) -> Result<PathBuf, String> {
    let relative = path
        .strip_prefix(base)
        .map_err(|_| "A saved media path is outside its download folder.")?;
    if relative.as_os_str().is_empty()
        || relative.components().any(|component| {
            !matches!(component, Component::Normal(name) if name.to_str().is_some_and(super::safe_file_name))
        })
    {
        return Err("A saved media file has a nonportable path.".into());
    }
    // Do not follow links or a directory junction that redirects the saved file outside its owner.
    let mut ancestor = base.to_path_buf();
    for part in relative
        .components()
        .take(relative.components().count() - 1)
    {
        ancestor.push(part);
        if !available(&ancestor)?.is_some_and(|stat| stat.is_dir()) {
            return Err(format!(
                "A saved media folder is unavailable: {}",
                ancestor.display()
            ));
        }
    }
    Ok(relative.to_path_buf())
}

fn record(
    files: &mut Vec<MediaFile>,
    seen: &mut HashSet<PathBuf>,
    base: &Path,
    source: PathBuf,
    kind: MediaKind,
) -> Result<(), String> {
    let relative = relative(base, &source)?;
    if seen.insert(relative.clone()) {
        files.push(MediaFile {
            source,
            relative,
            kind,
        });
    }
    Ok(())
}

fn directory(path: &Path) -> Result<Option<fs::ReadDir>, String> {
    match fs::read_dir(path) {
        Ok(entries) => Ok(Some(entries)),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Could not read {}: {error}", path.display())),
    }
}

fn gallery_or_remote(item: &Item) -> Result<Vec<MediaFile>, String> {
    if item.remote.is_some() && item.status != Status::Complete {
        return Err(format!(
            "Finish the account-based download before backing up {}.",
            item.file_name
        ));
    }
    if !is_folder(item) {
        return Ok(Vec::new());
    }
    let folder = &item.dest;
    let entries = directory(folder)?;
    let Some(tracked) = item.written_files.as_ref() else {
        let has_entries = entries.is_some_and(|mut entries| entries.next().is_some());
        if has_entries || item.downloaded > 0 || item.status == Status::Complete {
            return Err(format!(
                "The saved files for {} have no file list. Resume it once before backing up.",
                item.file_name
            ));
        }
        return Ok(Vec::new());
    };
    // Older versions retain at most 100,000 reported gallery files.
    if item.gallery.is_some() && tracked.len() >= 100_000 {
        return Err(format!(
            "The saved file list for {} may be incomplete.",
            item.file_name
        ));
    }
    if available(folder)?.is_some_and(|stat| !stat.is_dir()) {
        return Err(format!(
            "A media download folder is unavailable: {}",
            folder.display()
        ));
    }
    let mut files = Vec::with_capacity(tracked.len());
    let mut seen = HashSet::new();
    for source in tracked {
        regular(source)?;
        record(
            &mut files,
            &mut seen,
            folder,
            source.clone(),
            MediaKind::FolderFile,
        )?;
    }
    // Older gallery-dl downloads may leave a partial media file before a path was reported.
    // Its ownership is unknown, so don't archive another tool's file or silently drop a partial.
    if item.status != Status::Complete {
        for entry in entries.into_iter().flatten() {
            let entry =
                entry.map_err(|error| format!("Could not read {}: {error}", folder.display()))?;
            let name = entry.file_name();
            if Path::new(&name)
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("part"))
                && !seen.contains(Path::new(&name))
            {
                return Err(format!(
                    "A partial gallery file is not tracked. Finish downloading {} before backing up.",
                    item.file_name
                ));
            }
        }
    }
    let saved = files.iter().try_fold(0u64, |size, file| {
        let length = fs::metadata(&file.source)
            .map_err(|error| error.to_string())?
            .len();
        size.checked_add(length)
            .ok_or_else(|| "Saved media are too large.".to_owned())
    })?;
    if saved < item.downloaded {
        return Err(format!(
            "The saved file list for {} does not contain all its saved bytes.",
            item.file_name
        ));
    }
    Ok(files)
}

fn stable_piece_name(name: &str) -> bool {
    let name = name.strip_suffix(".sha256").unwrap_or(name);
    let name = name.strip_suffix(".mdm.part").unwrap_or(name);
    let index = match name.split_once(".changed-") {
        Some((index, serial))
            if !serial.is_empty() && serial.bytes().all(|c| c.is_ascii_digit()) =>
        {
            index
        }
        Some(_) => return false,
        None => name,
    };
    index.len() >= 6 && index.bytes().all(|c| c.is_ascii_digit())
}

fn record_video_work(
    files: &mut Vec<MediaFile>,
    seen: &mut HashSet<PathBuf>,
    base: &Path,
    source: PathBuf,
    kind: MediaKind,
) -> Result<(), String> {
    regular(&source)?;
    let name = source
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or("Invalid video stream name.")?;
    if let Some(destination) = name
        .strip_suffix(".mdm.json")
        .or_else(|| name.strip_suffix(".mdm.part"))
    {
        let destination = source.with_file_name(destination);
        regular(&mdm_engine::state::state_path(&destination))?;
        regular(&mdm_engine::naming::part_path(&destination))?;
        record(files, seen, base, destination, MediaKind::PartialVideo)
    } else {
        record(files, seen, base, source, kind)
    }
}

fn record_subtitle(
    files: &mut Vec<MediaFile>,
    seen: &mut HashSet<PathBuf>,
    video: &Path,
    path: &Path,
) -> Result<(), String> {
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or("Invalid subtitle name.")?;
    let source = if available(path)?.is_some() {
        path.to_path_buf()
    } else {
        // Older history retained the old path even after a deferred rename moved the subtitle.
        let mut components = name.rsplitn(3, '.');
        let (Some(ext), Some(lang), Some(_)) =
            (components.next(), components.next(), components.next())
        else {
            return Err(format!(
                "A saved subtitle is unavailable: {}",
                path.display()
            ));
        };
        let stem = video
            .file_stem()
            .and_then(|stem| stem.to_str())
            .ok_or("Invalid video name.")?;
        let renamed = format!("{stem}.{lang}.{ext}");
        if mdm_tools::video::saved_subtitle_language(video, &renamed).is_none() {
            return Err(format!(
                "A saved subtitle is unavailable: {}",
                path.display()
            ));
        }
        video.with_file_name(renamed)
    };
    regular(&source)?;
    if source == video {
        return Err("A saved subtitle is also its video's final destination.".into());
    }
    let name = source
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| super::safe_file_name(name))
        .ok_or("A saved subtitle has a nonportable name.")?;
    let relative = PathBuf::from(name);
    if !seen.insert(relative.clone()) {
        if files.iter().any(|file| {
            file.relative == relative && file.source == source && file.kind == MediaKind::SideVideo
        }) {
            return Ok(());
        }
        return Err(format!("Two media files have the restored name {name}."));
    }
    files.push(MediaFile {
        source,
        relative,
        kind: MediaKind::SideVideo,
    });
    Ok(())
}

fn video(item: &Item) -> Result<Vec<MediaFile>, String> {
    let Some(spec) = &item.video else {
        return Ok(Vec::new());
    };
    let base = item
        .dest
        .parent()
        .ok_or("A video file has no download folder.")?;
    let name = item
        .dest
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or("Invalid video file name.")?;
    let stem = item
        .dest
        .file_stem()
        .and_then(|name| name.to_str())
        .ok_or("Invalid video file name.")?;
    let mut files = Vec::new();
    let mut seen = HashSet::new();
    for path in &item.side_files {
        record_subtitle(&mut files, &mut seen, &item.dest, path)?;
    }
    for source in &spec.parts {
        if source == &item.dest {
            return Err("A saved video side file is also its final destination.".into());
        }
        record_video_work(
            &mut files,
            &mut seen,
            base,
            source.clone(),
            MediaKind::VideoPart,
        )?;
    }
    for entry in directory(base)?.into_iter().flatten() {
        let entry = entry.map_err(|error| format!("Could not read {}: {error}", base.display()))?;
        let source = entry.path();
        let Some(file_name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if file_name == name {
            continue;
        }
        if mdm_tools::video::saved_subtitle_language(&item.dest, &file_name).is_some_and(|lang| {
            spec.subs.langs.iter().any(|wanted| {
                wanted == mdm_tools::video::ALL_UPLOADERS || wanted.eq_ignore_ascii_case(lang)
            })
        }) {
            record_subtitle(&mut files, &mut seen, &item.dest, &source)?;
        } else if item.status != Status::Complete
            && let Some(output) = file_name.strip_suffix(".mdm.pieces")
            && (output == name || mdm_tools::video::is_unfinished_output(stem, output))
        {
            if !available(&source)?.is_some_and(|stat| stat.is_dir()) {
                return Err(format!(
                    "A saved video segment folder is unavailable: {}",
                    source.display()
                ));
            }
            for piece in directory(&source)?.into_iter().flatten() {
                let piece = piece
                    .map_err(|error| format!("Could not read {}: {error}", source.display()))?;
                if !piece.file_name().to_str().is_some_and(stable_piece_name) {
                    return Err(format!(
                        "Unrecognized data in {}. Check the saved video pieces before backing up.",
                        source.display()
                    ));
                }
                regular(&piece.path())?;
                record(
                    &mut files,
                    &mut seen,
                    base,
                    piece.path(),
                    MediaKind::Sidecar,
                )?;
            }
        } else if item.status != Status::Complete
            && mdm_tools::video::is_unfinished_output(stem, &file_name)
        {
            record_video_work(&mut files, &mut seen, base, source, MediaKind::Sidecar)?;
        }
    }
    if item.status != Status::Complete
        && item.downloaded > 0
        && !files.iter().any(|file| file.kind != MediaKind::SideVideo)
    {
        return Err(format!(
            "Saved progress for {} has no supported video checkpoint.",
            item.file_name
        ));
    }
    files.sort_unstable_by(|a, b| a.relative.cmp(&b.relative));
    Ok(files)
}

pub(super) fn gather(item: &Item) -> Result<Vec<MediaFile>, String> {
    if item.video.is_none() && !item.side_files.is_empty() {
        return Err("A download has subtitle files without a video.".into());
    }
    if item.gallery.is_some() || item.remote.is_some() {
        gallery_or_remote(item)
    } else {
        video(item)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Category, GallerySpec, VideoSpec};

    fn media(dest: &Path) -> Item {
        Item::new(
            1,
            "https://example.org/media".parse().unwrap(),
            dest.to_path_buf(),
            Category::General,
        )
    }

    #[test]
    fn gathers_subtitles_after_restart_and_finished_stream_artifacts_for_resume() {
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("Film.mp4");
        let mut item = media(&dest);
        item.video = Some(VideoSpec {
            selector: "137+140".into(),
            subs: mdm_tools::video::Subs {
                langs: vec!["en".into()],
                ..Default::default()
            },
            parts: vec![],
            named: false,
        });
        item.status = Status::Stopped;
        item.downloaded = 8;
        for name in [
            "Film.en.srt",
            "Film.personal.srt",
            "Film.f137.mp4",
            "Film.f140.m4a.mdm.json",
            "Film.f140.m4a.mdm.part",
            "Film.pdf",
        ] {
            fs::write(dir.path().join(name), b"clip").unwrap();
        }
        let stream = dir.path().join("Film.fhls-720p.mp4.mdm.pieces");
        fs::create_dir(&stream).unwrap();
        fs::write(stream.join("000001"), b"piece").unwrap();
        fs::write(stream.join("000001.sha256"), b"hash").unwrap();
        let files = gather(&item).unwrap();
        let refs: Vec<_> = files
            .iter()
            .map(|file| (file.relative.clone(), file.kind))
            .collect();
        assert_eq!(
            refs,
            vec![
                (PathBuf::from("Film.en.srt"), MediaKind::SideVideo),
                (PathBuf::from("Film.f137.mp4"), MediaKind::Sidecar),
                (PathBuf::from("Film.f140.m4a"), MediaKind::PartialVideo),
                (
                    PathBuf::from("Film.fhls-720p.mp4.mdm.pieces").join("000001"),
                    MediaKind::Sidecar
                ),
                (
                    PathBuf::from("Film.fhls-720p.mp4.mdm.pieces").join("000001.sha256"),
                    MediaKind::Sidecar
                ),
            ]
        );
        fs::remove_file(dir.path().join("Film.f140.m4a.mdm.json")).unwrap();
        assert!(
            gather(&item).is_err(),
            "the stream data requires its saved state"
        );
    }

    #[test]
    fn keeps_tracked_subtitles_when_moved_or_renamed_from_the_original_directory() {
        let dir = tempfile::tempdir().unwrap();
        let old = dir.path().join("Old");
        let new = dir.path().join("New");
        fs::create_dir(&old).unwrap();
        fs::create_dir(&new).unwrap();
        let dest = new.join("Renamed.mp4");
        let mut item = media(&dest);
        item.status = Status::Complete;
        item.video = Some(VideoSpec {
            selector: "137".into(),
            subs: Default::default(),
            parts: vec![],
            named: false,
        });
        let kept = old.join("Film.en.srt");
        let renamed = new.join("Renamed.fr.vtt");
        fs::write(&kept, b"Moved main video").unwrap();
        fs::write(&renamed, b"Renamed subtitle").unwrap();
        item.side_files = vec![kept.clone(), old.join("Film.fr.vtt")];
        let restored_item: Item =
            serde_json::from_value(serde_json::to_value(item).unwrap()).unwrap();
        let files = gather(&restored_item).unwrap();
        assert_eq!(files.len(), 2);
        assert_eq!(files[0].source, kept);
        assert_eq!(files[0].relative, Path::new("Film.en.srt"));
        assert_eq!(files[1].source, renamed);
        assert_eq!(files[1].relative, Path::new("Renamed.fr.vtt"));
    }

    #[test]
    fn gathers_tracked_gallery_files_and_rejects_missing_records() {
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("Album");
        let nested = dest.join("Images");
        fs::create_dir_all(&nested).unwrap();
        let photo = nested.join("cat.jpg");
        fs::write(&photo, b"picture").unwrap();
        fs::write(dest.join("unrelated.txt"), b"not a download").unwrap();
        let mut item = media(&dest);
        item.gallery = Some(GallerySpec::default());
        item.status = Status::Stopped;
        item.downloaded = 7;
        assert!(gather(&item).is_err());
        item.written_files = Some(vec![photo.clone()]);
        let files = gather(&item).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].relative, PathBuf::from("Images").join("cat.jpg"));
        fs::remove_file(photo).unwrap();
        assert!(gather(&item).is_err());
    }
}
