//! The rules every entry passes, whatever the format (#37):
//! - a path is relative, has no `..`, no drive or device prefix and no `:` (an NTFS stream name
//!   would let `a.txt:Zone.Identifier` overwrite the file's mark), and each part is made a safe
//!   file name; it can't leave the staging folder;
//! - links, devices and pipes are left out, and nothing is written through a link;
//! - limits on the bytes read (a bomb; the entries left out are counted too, since decompressing
//!   them costs just as much), the number of entries and the depth;
//! - written into an empty staging folder, then moved into place without overwriting anything.

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use mdm_engine::safe_move::{is_link_or_reparse, rename_no_replace};

use crate::{Error, Report, Subfolder};

/// What an extraction may write.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    /// Bytes in all.
    pub total: u64,
    pub entries: u64,
    /// Folders inside folders.
    pub depth: usize,
}

impl Limits {
    /// For an archive of `size` bytes: at most 200 times its size or 20 GiB, whichever is more
    /// (real archives compress well, bombs a thousandfold), 100 000 entries, 64 levels.
    pub fn for_archive(size: u64) -> Limits {
        Limits {
            total: size.saturating_mul(200).max(20 << 30),
            entries: 100_000,
            depth: 64,
        }
    }
}

impl Default for Limits {
    fn default() -> Self {
        Limits::for_archive(0)
    }
}

/// An entry's name inside an archive as a safe path under the extraction folder, or why it
/// can't be one. Both `/` and `\` separate (Windows tools write `\`).
pub fn rel_path(name: &str, depth: usize) -> Result<PathBuf, &'static str> {
    if name.starts_with('/') || name.starts_with('\\') {
        return Err("absolute path");
    }
    let mut out = PathBuf::new();
    let mut parts = 0;
    for part in name.split(['/', '\\']) {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            return Err("goes outside the folder");
        }
        // A drive (`C:`), a device or a stream name: never part of a file name here.
        if part.contains(':') {
            return Err("drive or stream name");
        }
        let safe = mdm_engine::naming::sanitize(part);
        if safe.is_empty() {
            continue;
        }
        out.push(safe);
        parts += 1;
        if parts > depth {
            return Err("folders too deep");
        }
    }
    if parts == 0 {
        return Err("empty name");
    }
    // Belt and braces: nothing but plain names went in.
    if !out.components().all(|c| matches!(c, Component::Normal(_))) {
        return Err("not a plain path");
    }
    Ok(out)
}

/// Whether a folder on the way from `root` to `path` (or `path` itself) is a link: nothing is
/// written through one (a junction or symlink made by an archive, or by anyone).
fn through_link(root: &Path, path: &Path) -> io::Result<bool> {
    let Ok(rel) = path.strip_prefix(root) else {
        return Ok(true);
    };
    require_directory(root)?;
    let mut at = root.to_path_buf();
    for c in rel.components() {
        at.push(c);
        match fs::symlink_metadata(&at) {
            Ok(m) if is_link_or_reparse(&m) => return Ok(true),
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => break,
            Err(e) => return Err(e),
        }
    }
    Ok(false)
}

pub fn require_directory(path: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.is_dir() && !is_link_or_reparse(&metadata) {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "extraction output must be a plain directory",
        ))
    }
}

/// Writes entries into the staging folder, counting what it reads against the limits (an entry
/// left out is decompressed all the same).
pub struct Writer<'a> {
    root: PathBuf,
    limits: Limits,
    cancel: Option<&'a AtomicBool>,
    /// Bytes put in the staging folder, and bytes read from the decoders (written or not): one
    /// budget covers both, so an entry left out can't be a bomb.
    written: u64,
    read: u64,
    entries: u64,
    skipped: Vec<(String, &'static str)>,
}

impl<'a> Writer<'a> {
    pub fn new(root: &Path, limits: Limits, cancel: Option<&'a AtomicBool>) -> Self {
        Writer {
            root: root.to_path_buf(),
            limits,
            cancel,
            written: 0,
            read: 0,
            entries: 0,
            skipped: Vec::new(),
        }
    }

    pub fn bytes(&self) -> u64 {
        self.written
    }

    pub fn take_skipped(&mut self) -> Vec<(String, &'static str)> {
        std::mem::take(&mut self.skipped)
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn cancelled(&self) -> bool {
        self.cancel.is_some_and(|c| c.load(Ordering::Relaxed))
    }

    /// Left out, with why (kept for the download's log).
    pub fn skip(&mut self, name: &str, why: &'static str) {
        tracing::info!("extract: skipped {name}: {why}");
        self.skipped.push((name.to_owned(), why));
    }

    fn count(&mut self) -> Result<(), Error> {
        self.entries += 1;
        if self.entries > self.limits.entries {
            return Err(Error::TooMany);
        }
        if self.cancelled() {
            return Err(Error::Cancelled);
        }
        Ok(())
    }

    /// Count `n` more bytes pulled from a decoder against the budget, written or not: a bomb
    /// behind a name that isn't safe costs just as much to decompress as any other entry.
    fn charge(&mut self, n: u64) -> Result<(), Error> {
        self.read += n;
        if self.read > self.limits.total {
            return Err(Error::TooBig {
                would: self.read,
                limit: self.limits.total,
            });
        }
        Ok(())
    }

    /// Read an entry that isn't written (its name isn't safe, or it would go through a link) past
    /// its end, so a stream format's next entry follows: under the same limits as one that is
    /// written — its size when the archive says it, the budget and a cancel at every read.
    fn drain(&mut self, name: &str, size: Option<u64>, data: &mut dyn Read) -> Result<(), Error> {
        let entry_cap = size.map(|s| s.saturating_add(1 << 20));
        let mut buf = vec![0u8; 64 * 1024];
        let mut this = 0u64;
        loop {
            let n = read_some(data, &mut buf)?;
            if n == 0 {
                return Ok(());
            }
            this += n as u64;
            if entry_cap.is_some_and(|c| this > c) {
                return Err(Error::Damaged(format!("{name} is bigger than it says")));
            }
            self.charge(n as u64)?;
            if self.cancelled() {
                return Err(Error::Cancelled);
            }
        }
    }

    /// A folder entry.
    pub fn dir(&mut self, name: &str) -> Result<(), Error> {
        self.count()?;
        let rel = match rel_path(name, self.limits.depth) {
            Ok(r) => r,
            Err(why) => {
                self.skip(name, why);
                return Ok(());
            }
        };
        let path = self.root.join(rel);
        if through_link(&self.root, &path)? {
            self.skip(name, "through a link");
            return Ok(());
        }
        fs::create_dir_all(&path)?;
        Ok(())
    }

    /// A file entry: its bytes read from `data` (at most `size` and a little more when the
    /// archive says how big it is).
    pub fn file(
        &mut self,
        name: &str,
        size: Option<u64>,
        data: &mut dyn Read,
        mode: Option<u32>,
    ) -> Result<(), Error> {
        self.count()?;
        let rel = match rel_path(name, self.limits.depth) {
            Ok(r) => r,
            Err(why) => {
                self.skip(name, why);
                // Read past it: a stream format's next entry follows.
                return self.drain(name, size, data);
            }
        };
        let path = self.root.join(&rel);
        if let Some(parent) = path.parent() {
            if through_link(&self.root, parent)? {
                self.skip(name, "through a link");
                return self.drain(name, size, data);
            }
            fs::create_dir_all(parent)?;
        }
        // Two entries of one name (an archive can hold that): the second is numbered.
        let (_, mut out) = reserve_numbered(&path, |candidate| {
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(candidate)
        })?;
        let entry_cap = size.map(|s| s.saturating_add(1 << 20));
        let mut buf = vec![0u8; 256 * 1024];
        let mut this = 0u64;
        loop {
            let n = read_some(data, &mut buf)?;
            if n == 0 {
                break;
            }
            this += n as u64;
            self.written += n as u64;
            if entry_cap.is_some_and(|c| this > c) {
                return Err(Error::Damaged(format!("{name} is bigger than it says")));
            }
            self.charge(n as u64)?;
            out.write_all(&buf[..n])?;
            if self.cancelled() {
                return Err(Error::Cancelled);
            }
        }
        out.flush()?;
        set_mode(&out, mode);
        Ok(())
    }
}

/// One read from a decoder: `Ok(0)` at its end, an interrupted read tried again, anything else
/// put as [`read_error`] has it.
fn read_some(data: &mut dyn Read, buf: &mut [u8]) -> Result<usize, Error> {
    loop {
        match data.read(buf) {
            Ok(n) => return Ok(n),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(read_error(e)),
        }
    }
}

/// A decoder's read error: a wrong password often shows only as data that doesn't check out.
fn read_error(e: io::Error) -> Error {
    if e.kind() == io::ErrorKind::InvalidData {
        Error::Damaged(e.to_string())
    } else {
        Error::Io(e)
    }
}

/// Unix: only the execute bits are kept (never setuid, setgid or sticky). Elsewhere nothing.
#[cfg(unix)]
fn set_mode(file: &fs::File, mode: Option<u32>) {
    use std::os::unix::fs::PermissionsExt;
    if let Some(m) = mode {
        let keep = if m & 0o111 != 0 { 0o755 } else { 0o644 };
        let _ = file.set_permissions(fs::Permissions::from_mode(keep));
    }
}

/// Windows has no permission bits for an archive to carry.
#[cfg(not(unix))]
fn set_mode(_file: &fs::File, _mode: Option<u32>) {}

/// Create or move into `path`, trying `name (1).ext` and so on when a name is taken.
/// The supplied operation must refuse to replace existing entries atomically.
pub fn reserve_numbered<T>(
    path: &Path,
    mut reserve: impl FnMut(&Path) -> io::Result<T>,
) -> io::Result<(PathBuf, T)> {
    let parent = path.parent().unwrap_or(Path::new(""));
    let file = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let (stem, ext) = match file.rfind('.') {
        Some(i) if i > 0 => (&file[..i], &file[i..]),
        _ => (file.as_str(), ""),
    };
    for candidate in std::iter::once(path.to_owned())
        .chain((1..).map(|n| parent.join(format!("{stem} ({n}){ext}"))))
    {
        match reserve(&candidate) {
            Ok(value) => return Ok((candidate, value)),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            // Windows can report access denied for an existing directory.
            Err(e)
                if cfg!(windows)
                    && e.kind() == io::ErrorKind::PermissionDenied
                    && fs::symlink_metadata(&candidate).is_ok() =>
            {
                continue;
            }
            Err(e) => return Err(e),
        }
    }
    unreachable!("there is always another candidate")
}

/// An empty folder beside the destination that the archive is extracted into; removed with
/// whatever is left in it when dropped (after a failure, everything).
pub struct Staging {
    dest: PathBuf,
    container: PathBuf,
    path: PathBuf,
}

static NEXT: AtomicU64 = AtomicU64::new(0);

impl Staging {
    pub fn new(dest: &Path) -> Result<Staging, Error> {
        fs::create_dir_all(dest)?;
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        let container = loop {
            let n = NEXT.fetch_add(1, Ordering::Relaxed);
            let candidate = dest.join(format!(".mdm-extract-{}-{n}", std::process::id()));
            match builder.create(&candidate) {
                Ok(()) => break candidate,
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e.into()),
            }
        };
        let staging = Staging {
            dest: dest.to_path_buf(),
            path: container.join("contents"),
            container,
        };
        fs::create_dir(&staging.path)?;
        Ok(staging)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Move what was extracted into place, as `subfolder` says; every file put there is told
    /// to `on_file`. Returns the report's folder and renamed count, and the files placed.
    pub fn place(
        self,
        base: &str,
        subfolder: Subfolder,
        on_file: &mut dyn FnMut(&Path),
    ) -> Result<(Report, u64), Error> {
        require_directory(&self.path)?;
        let tops = fs::read_dir(&self.path)?
            .map(|entry| entry.map(|e| e.path()))
            .collect::<io::Result<Vec<_>>>()?;
        let together = match subfolder {
            Subfolder::Always => true,
            Subfolder::Never => false,
            Subfolder::Smart => tops.len() > 1,
        };
        let mut report = Report::default();
        let mut placed = 0;
        if together {
            let name = mdm_engine::naming::sanitize(base);
            let name = if name.is_empty() {
                "extracted".to_owned()
            } else {
                name
            };
            let target = self.dest.join(name);
            let (folder, ()) = reserve_numbered(&target, |candidate| {
                rename_no_replace(&self.path, candidate)
            })?;
            report.renamed += u64::from(folder != target);
            placed += mark_all(&folder, on_file)?;
            report.folder = folder;
        } else {
            for top in tops {
                let Some(name) = top.file_name() else {
                    continue;
                };
                let target = self.dest.join(name);
                let (to, ()) =
                    reserve_numbered(&target, |candidate| rename_no_replace(&top, candidate))?;
                report.renamed += u64::from(to != target);
                placed += if fs::symlink_metadata(&to)?.is_dir() {
                    mark_all(&to, on_file)?
                } else {
                    on_file(&to);
                    1
                };
            }
            report.folder = self.dest.clone();
        }
        Ok((report, placed))
    }
}

impl Drop for Staging {
    fn drop(&mut self) {
        if require_directory(&self.container).is_ok() {
            let _ = fs::remove_dir_all(&self.container);
        }
    }
}

/// Every file under `dir`, told to `on_file`; links are never followed. Iterative (no recursion
/// limit to hit on a deep tree).
fn mark_all(dir: &Path, on_file: &mut dyn FnMut(&Path)) -> io::Result<u64> {
    let mut n = 0;
    let mut todo = vec![dir.to_path_buf()];
    while let Some(d) = todo.pop() {
        require_directory(&d)?;
        for e in fs::read_dir(&d)? {
            let e = e?;
            let metadata = fs::symlink_metadata(e.path())?;
            if is_link_or_reparse(&metadata) {
                continue;
            }
            if metadata.is_dir() {
                todo.push(e.path());
            } else if metadata.is_file() {
                on_file(&e.path());
                n += 1;
            }
        }
    }
    Ok(n)
}

/// An external tool's output in the staging folder, checked as our own entries are: anything
/// that is a link, or not a plain file or folder, is removed before anything is moved into
/// place, and so is a name that isn't safe. Returns what was left out.
pub fn check_tree(root: &Path, depth: usize) -> io::Result<Vec<(String, &'static str)>> {
    let bad = scan(root, depth)?;
    for (path, _, _) in &bad {
        let metadata = fs::symlink_metadata(path)?;
        if is_link_or_reparse(&metadata) {
            remove_alias(path, &metadata)?;
        } else if metadata.is_dir() {
            fs::remove_dir_all(path)?;
        } else {
            fs::remove_file(path)?;
        }
    }
    Ok(bad.into_iter().map(|(_, rel, why)| (rel, why)).collect())
}

#[cfg(windows)]
fn remove_alias(path: &Path, metadata: &fs::Metadata) -> io::Result<()> {
    use std::os::windows::fs::MetadataExt;
    const DIRECTORY: u32 = 0x10;
    if metadata.file_attributes() & DIRECTORY != 0 {
        fs::remove_dir(path)
    } else {
        fs::remove_file(path)
    }
}

#[cfg(not(windows))]
fn remove_alias(path: &Path, _: &fs::Metadata) -> io::Result<()> {
    fs::remove_file(path)
}

/// What under `root` breaks the rules (a link, not a plain file or folder, a name that isn't
/// safe), with its path, its name under `root` and why; nothing is changed. A folder that breaks
/// them isn't looked into.
fn scan(root: &Path, depth: usize) -> io::Result<Vec<(PathBuf, String, &'static str)>> {
    let mut out = Vec::new();
    let mut todo = vec![root.to_path_buf()];
    while let Some(d) = todo.pop() {
        require_directory(&d)?;
        for e in fs::read_dir(&d)? {
            let e = e?;
            let path = e.path();
            let metadata = fs::symlink_metadata(&path)?;
            let t = metadata.file_type();
            let rel = path
                .strip_prefix(root)
                .map(|r| r.to_string_lossy().into_owned())
                .unwrap_or_default();
            let bad = if is_link_or_reparse(&metadata) {
                Some("link")
            } else if !t.is_dir() && !t.is_file() {
                Some("not a file")
            } else {
                match rel_path(&rel, depth) {
                    Ok(p)
                        if p.to_string_lossy()
                            == rel.replace('/', std::path::MAIN_SEPARATOR_STR) =>
                    {
                        None
                    }
                    Ok(_) => Some("unsafe name"),
                    Err(why) => Some(why),
                }
            };
            match bad {
                Some(why) => out.push((path, rel, why)),
                None if t.is_dir() => todo.push(path),
                None => {}
            }
        }
    }
    Ok(out)
}

/// What [`move_out`] did.
pub struct Moved {
    /// Where the files went, the number of them, and those numbered.
    pub report: Report,
    /// Entries that break the rules: never moved, never deleted (they stay in the folder).
    pub skipped: Vec<(String, &'static str)>,
    /// The folder, when something is still in it (the entries left out).
    pub left: Option<PathBuf>,
}

/// Put what another program extracted into `from` (HatchZip in place, a folder of its own) where
/// `subfolder` says, as our own extractions are, one entry at a time. Nothing in it is ever
/// deleted: those files are no longer in the archive. Entries that break the rules stay where
/// they are; when a move fails, what was moved stays where it went, the rest in `from`. Empty
/// folders are removed from `from` at the end, and `from` itself when nothing is left in it.
/// When `from` can't even be read, nothing was moved and everything is still in it: that is
/// said the same way ([`Error::Unplaced`]), so the user is told where the files are.
pub fn move_out(
    from: &Path,
    dest: &Path,
    base: &str,
    subfolder: Subfolder,
    depth: usize,
    on_file: &mut dyn FnMut(&Path),
) -> Result<Moved, Error> {
    let unread = |e: io::Error| {
        tracing::warn!(
            "extract: {} can't be read: {e}; nothing was moved out of it",
            from.display()
        );
        Error::Unplaced {
            to: dest.to_path_buf(),
            left: from.to_path_buf(),
            why: e.to_string(),
        }
    };
    let bad = scan(from, depth).map_err(unread)?;
    let bad_paths: Vec<PathBuf> = bad.iter().map(|(p, _, _)| p.clone()).collect();
    // By name: the same order every time.
    let mut tops: Vec<PathBuf> = fs::read_dir(from)
        .map_err(unread)?
        .map(|entry| entry.map(|e| e.path()))
        .collect::<io::Result<_>>()
        .map_err(unread)?;
    tops.retain(|path| !bad_paths.contains(path));
    tops.sort();
    let together = match subfolder {
        Subfolder::Always => true,
        Subfolder::Never => false,
        Subfolder::Smart => tops.len() > 1,
    };
    let mut m = Mover {
        bad: &bad_paths,
        report: Report::default(),
        on_file,
    };
    m.report.folder = dest.to_path_buf();
    let moved = (|| {
        let root = if together {
            let name = mdm_engine::naming::sanitize(base);
            let name = if name.is_empty() {
                "extracted".to_owned()
            } else {
                name
            };
            let target = dest.join(name);
            let (folder, ()) = reserve_numbered(&target, |candidate| fs::create_dir(candidate))?;
            m.report.renamed += u64::from(folder != target);
            m.report.folder = folder.clone();
            folder
        } else {
            dest.to_path_buf()
        };
        for top in &tops {
            if let Some(name) = top.file_name() {
                m.entry(top, root.join(name))?;
            }
        }
        io::Result::Ok(())
    })();
    if let Err(e) = moved {
        tracing::warn!(
            "extract: moving out of {} stopped: {e}; moved so far: {}",
            from.display(),
            m.report.folder.display()
        );
        return Err(Error::Unplaced {
            to: m.report.folder,
            left: from.to_path_buf(),
            why: e.to_string(),
        });
    }
    prune(from);
    let left = fs::symlink_metadata(from)
        .is_ok()
        .then(|| from.to_path_buf());
    Ok(Moved {
        report: m.report,
        skipped: bad.into_iter().map(|(_, rel, why)| (rel, why)).collect(),
        left,
    })
}

/// [`move_out`]'s state while it moves.
struct Mover<'a> {
    bad: &'a [PathBuf],
    report: Report,
    on_file: &'a mut dyn FnMut(&Path),
}

impl Mover<'_> {
    /// Move `from` to `to` (numbered when taken): whole, unless it is a folder holding an entry
    /// that breaks the rules; then its folder is made and what is safe in it moved, one by one.
    fn entry(&mut self, from: &Path, to: PathBuf) -> io::Result<()> {
        let holds_bad = self.bad.iter().any(|b| b.starts_with(from));
        if holds_bad {
            require_directory(from)?;
            let (folder, ()) = reserve_numbered(&to, |candidate| fs::create_dir(candidate))?;
            self.report.renamed += u64::from(folder != to);
            let mut inside = fs::read_dir(from)?
                .map(|e| e.map(|e| e.path()))
                .collect::<io::Result<Vec<_>>>()?;
            inside.sort();
            for path in inside {
                if self.bad.contains(&path) {
                    continue;
                }
                if let Some(name) = path.file_name() {
                    self.entry(&path, folder.join(name))?;
                }
            }
            return Ok(());
        }
        let (moved, ()) = reserve_numbered(&to, |candidate| rename_no_replace(from, candidate))?;
        self.report.renamed += u64::from(moved != to);
        self.report.files += if fs::symlink_metadata(&moved)?.is_dir() {
            mark_all(&moved, self.on_file)?
        } else {
            (self.on_file)(&moved);
            1
        };
        Ok(())
    }
}

/// Remove the empty folders under `root`, deepest first, then `root` if it is empty: never a
/// file, never a link.
fn prune(root: &Path) {
    let mut dirs = vec![root.to_path_buf()];
    let mut i = 0;
    while i < dirs.len() {
        if let Ok(rd) = require_directory(&dirs[i]).and_then(|()| fs::read_dir(&dirs[i])) {
            for e in rd.flatten() {
                if require_directory(&e.path()).is_ok() {
                    dirs.push(e.path());
                }
            }
        }
        i += 1;
    }
    for d in dirs.iter().rev() {
        let _ = fs::remove_dir(d);
    }
}
