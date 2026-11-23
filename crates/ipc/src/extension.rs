//! The browser extension's identity and whether a browser has it, shared by the native messaging
//! host (which serves it and notes each browser that starts it) and the app (which offers to
//! install it until one has).

use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::time::Duration;

/// The extension's ID loaded unpacked (the public key in extension/manifest.json).
pub const UNPACKED_ID: &str = "oogbclbbninliongijffeeggalppliok";
/// The separate Auralis development extension, with its own public key.
pub const AURALIS_UNPACKED_ID: &str = "ghelllciojchjjlnghidngnfedogaggk";
/// Its ID in the Chrome Web Store, which signs it with the store's own key
/// (tools/extension/pack.ps1 leaves the manifest's key out of the store's copy). [`store_id`] is
/// `None` while this is not a valid ID (a placeholder), and then nothing names it.
pub const STORE_ID: &str = "bobmhloppnfipdjjncalidjenegfgebg";
/// Previously supported upstream store extension, retained for existing installations.
pub const LEGACY_STORE_ID: &str = "ejoleppdfgjdndddcjoehopknmlglojp";
/// Its IDs in Microsoft Edge Add-ons and Opera add-ons, which give their own; placeholders until
/// listed there, never served then (`valid_id`).
pub const OTHER_STORE_IDS: [&str; 2] = ["EDGE_ADDONS_ID_PENDING", "OPERA_ADDONS_ID_PENDING"];
/// The Firefox add-on's page on addons.mozilla.org (listed: Firefox installs and updates it from
/// there).
pub const FIREFOX_PAGE: &str = "https://addons.mozilla.org/firefox/addon/mister-download-manager/";
/// The Firefox add-on's ID (extension/manifest.firefox.json).
pub const FIREFOX_ID: &str = "integration@misterdownloadmanager.com";
pub const AURALIS_FIREFOX_ID: &str = "integration@auralis.download";
/// Chrome's update service: an external-install entry naming it makes Chrome offer the store's
/// extension at its next start (developer.chrome.com, "Alternative extension distribution
/// options").
pub const STORE_UPDATE_URL: &str = "https://clients2.google.com/service/update2/crx";
/// Helium's name for the Chrome Web Store's update service (its proxy-extension-downloads.patch,
/// `kChromeWebstoreUpdateURL`): an entry naming it goes through Helium's own services, while
/// Google's address, asked directly without the browser's version, answers "no update" (#685).
pub const HELIUM_STORE_UPDATE_URL: &str = "https://update-url-to-be-replaced.qjz9zk";

/// A Chromium extension ID: 32 letters from a to p.
pub fn valid_id(id: &str) -> bool {
    id.len() == 32 && id.bytes().all(|b| (b'a'..=b'p').contains(&b))
}

/// The store's ID, once it is a real one.
pub fn store_id() -> Option<&'static str> {
    valid_id(STORE_ID).then_some(STORE_ID)
}

/// The project’s Chromium extension identities, excluding the upstream legacy copies.
pub fn is_auralis_chromium_id(id: &str) -> bool {
    store_id() == Some(id) || id == AURALIS_UNPACKED_ID
}

/// The Chromium extensions the native host serves: unpacked, and each store's once listed.
pub fn chromium_ids() -> Vec<&'static str> {
    std::iter::once(UNPACKED_ID)
        .chain(std::iter::once(AURALIS_UNPACKED_ID))
        .chain(std::iter::once(LEGACY_STORE_ID))
        .chain(store_id())
        .chain(OTHER_STORE_IDS.into_iter().filter(|id| valid_id(id)))
        .collect()
}

/// The extension's page in the Chrome Web Store (Chrome, Edge, Brave, Opera and Vivaldi all
/// install from it), once it is listed: the listing's own address, its name then its ID.
pub fn store_page() -> Option<String> {
    store_id()
        .map(|id| format!("https://chromewebstore.google.com/detail/auralis-download-manager/{id}"))
}

/// The tutorial that adds the extension: from the stores, and by hand (a build of its own, or
/// a browser that can't use its store). Its file in docs/: the app opens it on the website, in
/// the interface language (the app's help::page_url).
pub const GUIDE_DOC: &str = "guide-catch-browser-downloads.md";

/// The help page for a browser that doesn't reach Mister Download Manager, at the section for
/// `why` (the native host's reasons, and the app's own checks): its file in docs/ and the
/// section, as GUIDE_DOC.
pub fn help_doc(why: &str) -> String {
    format!("browser-help.md#{why}")
}

/// Marks the data folder once a browser has started the host for the extension.
const SEEN: &str = "extension-seen";
const HANDSHAKE: &str = "extension-recent-handshake";
const HANDSHAKE_LIFETIME: Duration = Duration::from_secs(120);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StoreBrowser {
    Chrome,
    Edge,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BrowserExtensionPresence {
    Unverified,
    Missing,
    Store,
    Unpacked,
}

impl BrowserExtensionPresence {
    pub fn source(self) -> Option<&'static str> {
        match self {
            Self::Store => Some("store"),
            Self::Unpacked => Some("unpacked"),
            Self::Unverified | Self::Missing => None,
        }
    }

    pub fn discovery(self) -> &'static str {
        match self {
            Self::Unverified => "unverified",
            Self::Missing => "missing",
            Self::Store | Self::Unpacked => "present",
        }
    }
}

impl StoreBrowser {
    pub fn id(self) -> &'static str {
        match self {
            Self::Chrome => "chrome",
            Self::Edge => "edge",
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Chrome => "Google Chrome",
            Self::Edge => "Microsoft Edge",
        }
    }

    fn marker(self) -> &'static str {
        match self {
            Self::Chrome => "extension-chrome-store-handshake",
            Self::Edge => "extension-edge-store-handshake",
        }
    }

    fn unpacked_marker(self) -> &'static str {
        match self {
            Self::Chrome => "extension-chrome-auralis-unpacked-handshake",
            Self::Edge => "extension-edge-auralis-unpacked-handshake",
        }
    }

    /// The browser owning the Windows HTTPS handler or launching the native host. Chromium
    /// forks can use chrome.exe and identify themselves as Chrome in their User-Agent.
    pub fn from_windows_executable(program: &str) -> Option<Self> {
        let path = program.to_ascii_lowercase().replace('/', "\\");
        let (directory, executable) = path.rsplit_once('\\')?;
        let (vendor, channel) = directory.strip_suffix(r"\application")?.rsplit_once('\\')?;
        if executable == "chrome.exe"
            && vendor.ends_with(r"\google")
            && ["chrome", "chrome beta", "chrome dev", "chrome sxs"].contains(&channel)
        {
            return Some(Self::Chrome);
        }
        if executable == "msedge.exe"
            && vendor.ends_with(r"\microsoft")
            && ["edge", "edge beta", "edge dev", "edge sxs"].contains(&channel)
        {
            return Some(Self::Edge);
        }
        None
    }

    /// Discover a project copy in the default data folder for this Windows channel.
    /// A manifest alone does not mean the extension is enabled or connected.
    pub fn windows_extension_presence(self, program: &str) -> BrowserExtensionPresence {
        let Some(root) = std::env::var_os("LOCALAPPDATA").map(std::path::PathBuf::from) else {
            return BrowserExtensionPresence::Unverified;
        };
        if !root.is_absolute() || Self::from_windows_executable(program) != Some(self) {
            return BrowserExtensionPresence::Unverified;
        }
        let Some(channel) = program.rsplit(['\\', '/']).nth(2) else {
            return BrowserExtensionPresence::Unverified;
        };
        let vendor = match self {
            Self::Chrome => "Google",
            Self::Edge => "Microsoft",
        };
        Self::extension_presence_in(&root.join(vendor).join(channel).join("User Data"))
    }

    fn extension_presence_in(root: &Path) -> BrowserExtensionPresence {
        use BrowserExtensionPresence::*;
        if !root.ancestors().all(plain_directory) {
            return Unverified;
        }
        let Ok(profiles) = std::fs::read_dir(root) else {
            return Unverified;
        };
        let mut checked_profile = false;
        let mut uncertain = false;
        let mut unpacked = false;
        for (index, profile) in profiles.enumerate() {
            if index >= 512 {
                uncertain = true;
                break;
            }
            let Ok(profile) = profile else {
                uncertain = true;
                continue;
            };
            let name = profile.file_name();
            let Some(name) = name.to_str() else { continue };
            if name != "Default"
                && !name
                    .strip_prefix("Profile ")
                    .is_some_and(|n| decimal(n) && n.parse::<u32>().is_ok())
            {
                continue;
            }
            let profile = profile.path();
            let extensions = profile.join("Extensions");
            if !plain_directory(&profile) {
                uncertain = true;
                continue;
            }
            match optional_directory(&extensions) {
                Ok(true) => {}
                Ok(false) if plain_file(&profile.join("Preferences")) => {
                    // Inspect only the existence of the profile marker, never its contents.
                    checked_profile = true;
                    continue;
                }
                Ok(false) | Err(()) => {
                    uncertain = true;
                    continue;
                }
            }
            checked_profile = true;
            if let Some(id) = store_id() {
                match installed_manifest(&extensions.join(id)) {
                    Ok(true) => return Store,
                    Ok(false) => {}
                    Err(()) => uncertain = true,
                }
            }
            match installed_manifest(&extensions.join(AURALIS_UNPACKED_ID)) {
                Ok(found) => unpacked |= found,
                Err(()) => uncertain = true,
            }
        }
        if unpacked {
            Unpacked
        } else if checked_profile && !uncertain {
            Missing
        } else {
            Unverified
        }
    }
}

fn ordinary_entry(metadata: &std::fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return false;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const REPARSE_POINT: u32 = 0x400;
        if metadata.file_attributes() & REPARSE_POINT != 0 {
            return false;
        }
    }
    true
}

fn plain_directory(path: &Path) -> bool {
    optional_directory(path) == Ok(true)
}

fn optional_directory(path: &Path) -> Result<bool, ()> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if ordinary_entry(&metadata) && metadata.is_dir() => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        _ => Err(()),
    }
}

fn plain_file(path: &Path) -> bool {
    std::fs::symlink_metadata(path)
        .is_ok_and(|metadata| ordinary_entry(&metadata) && metadata.is_file())
}

/// An existing project folder without a readable manifest can be mid-install.
fn installed_manifest(extension: &Path) -> Result<bool, ()> {
    if !optional_directory(extension)? {
        return Ok(false);
    }
    let versions = std::fs::read_dir(extension).map_err(|_| ())?;
    for (index, version) in versions.enumerate() {
        if index >= 128 {
            break;
        }
        let Ok(version) = version else { continue };
        if version
            .file_name()
            .to_str()
            .is_some_and(extension_version_folder)
            && plain_directory(&version.path())
            && plain_file(&version.path().join("manifest.json"))
        {
            return Ok(true);
        }
    }
    Err(())
}

fn extension_version_folder(name: &str) -> bool {
    let Some((version, generation)) = name.split_once('_') else {
        return false;
    };
    decimal(generation)
        && generation.parse::<u32>().is_ok()
        && (1..=4).contains(&version.split('.').count())
        && version
            .split('.')
            .all(|component| decimal(component) && component.parse::<u16>().is_ok())
}

fn decimal(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

/// The host, started by a browser for the extension: the extension is installed there. The
/// file holds one line per browser (`capture::browser_named`), with the extension's version.
pub fn mark_seen(
    browser: &str,
    version: &str,
    extension_id: Option<&str>,
    store_browser: Option<StoreBrowser>,
) {
    let Some(dir) = crate::data_dir() else {
        return;
    };
    // Timestamp a real browser-to-host handshake independently of historical installs.
    let _ = crate::private_dir(&dir);
    let id = extension_id.filter(|id| valid_id(id)).unwrap_or("");
    let handshake = format!("{browser}\t{id}");
    let _ = crate::private_write(&dir.join(HANDSHAKE), handshake.as_bytes());
    if let Some(store_browser) = store_browser.filter(|_| is_auralis_chromium_id(id)) {
        let marker = if store_id() == Some(id) {
            store_browser.marker()
        } else {
            store_browser.unpacked_marker()
        };
        let record = format!("{}\t{id}", store_browser.name());
        let _ = crate::private_write(&dir.join(marker), record.as_bytes());
    }
    let file = dir.join(SEEN);
    let known = std::fs::read_to_string(&file).ok();
    let mut lines: Vec<(String, String)> = known.as_deref().map(parse_seen).unwrap_or_default();
    let entry = (browser.to_owned(), version.to_owned());
    if known.is_some() && (browser.is_empty() || lines.contains(&entry)) {
        return;
    }
    lines.retain(|(b, _)| b != browser);
    lines.push(entry);
    let text: String = lines.iter().map(|(b, v)| format!("{b}\t{v}\n")).collect();
    let _ = crate::private_dir(&dir);
    let _ = crate::private_write(&file, text.as_bytes());
}

/// The lines of `extension-seen`: (browser, extension version). An older file holds only a
/// browser's name.
fn parse_seen(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| match l.split_once('\t') {
            Some((b, v)) => (b.to_owned(), v.to_owned()),
            None => (l.to_owned(), String::new()),
        })
        .collect()
}

/// Has any browser's extension reached the app?
pub fn seen() -> bool {
    crate::data_dir().is_some_and(|d| d.join(SEEN).exists())
}

/// True only shortly after a browser actually started the native host.
pub fn recently_connected() -> bool {
    crate::data_dir()
        .and_then(|d| std::fs::metadata(d.join(HANDSHAKE)).ok())
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.elapsed().ok())
        .is_some_and(|age| age < HANDSHAKE_LIFETIME)
}

/// Browser associated with the latest recent handshake, when identified.
pub fn recently_connected_browser() -> Option<String> {
    if !recently_connected() {
        return None;
    }
    crate::data_dir()
        .and_then(|d| std::fs::read_to_string(d.join(HANDSHAKE)).ok())
        .and_then(|s| s.split('\t').next().map(str::to_owned))
        .filter(|s| !s.is_empty() && s != "connected" && s.len() <= 128)
}

/// The Chromium extension ID that made the latest native-messaging handshake.
pub fn recently_connected_extension_id() -> Option<String> {
    if !recently_connected() {
        return None;
    }
    crate::data_dir()
        .and_then(|d| std::fs::read_to_string(d.join(HANDSHAKE)).ok())
        .and_then(|s| {
            s.split('\t')
                .nth(1)
                .filter(|id| valid_id(id))
                .map(str::to_owned)
        })
}

/// Verified Auralis connections and separate historical familiarity with this browser.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct BrowserStoreStatus {
    pub connected_recently: bool,
    pub connected_source: Option<&'static str>,
    pub extension_previously_connected: bool,
    pub store_previously_connected: bool,
    pub browser_previously_connected: bool,
}

pub fn browser_store_status(browser: StoreBrowser) -> BrowserStoreStatus {
    crate::data_dir().map_or_else(BrowserStoreStatus::default, |dir| {
        browser_store_status_in(&dir, browser)
    })
}

fn browser_store_status_in(dir: &Path, browser: StoreBrowser) -> BrowserStoreStatus {
    // The native host replaces this record atomically. Read its timestamp and both values
    // through one open handle so another browser cannot replace only half of the result.
    let handshake = |marker: &str, expected_id: &str| {
        let file = File::open(dir.join(marker)).ok()?;
        let modified = file.metadata().ok()?.modified().ok()?;
        let record = bounded_text(file, 256)?;
        let (record_browser, id) = record.split_once('\t')?;
        (record_browser == browser.name() && id == expected_id).then_some(modified)
    };
    let store_handshake = store_id().and_then(|id| handshake(browser.marker(), id));
    let unpacked_handshake = handshake(browser.unpacked_marker(), AURALIS_UNPACKED_ID);
    let connected_source = [
        store_handshake.map(|time| (time, "store")),
        unpacked_handshake.map(|time| (time, "unpacked")),
    ]
    .into_iter()
    .flatten()
    .filter(|(time, _)| time.elapsed().is_ok_and(|age| age < HANDSHAKE_LIFETIME))
    .max_by_key(|(time, _)| *time)
    .map(|(_, source)| source);
    let extension_previously_connected = store_handshake.is_some() || unpacked_handshake.is_some();
    // Older records describe the browser and version only. They can prevent a repeat
    // invitation, but cannot identify which extension is installed in that browser.
    let browser_previously_connected = extension_previously_connected
        || File::open(dir.join(SEEN))
            .ok()
            .and_then(|file| bounded_text(file, 16 * 1024))
            .is_some_and(|history| {
                history
                    .lines()
                    .any(|line| line.split('\t').next() == Some(browser.name()))
            });
    BrowserStoreStatus {
        connected_recently: connected_source.is_some(),
        connected_source,
        extension_previously_connected,
        store_previously_connected: store_handshake.is_some(),
        browser_previously_connected,
    }
}

fn bounded_text(file: File, limit: u64) -> Option<String> {
    let mut text = String::new();
    file.take(limit + 1).read_to_string(&mut text).ok()?;
    (text.len() as u64 <= limit).then_some(text)
}

/// The browsers whose extension has reached the app, with its version (empty when unknown).
pub fn seen_browsers() -> Vec<(String, String)> {
    crate::data_dir()
        .and_then(|d| std::fs::read_to_string(d.join(SEEN)).ok())
        .as_deref()
        .map(parse_seen)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_chromium_ids() {
        assert!(valid_id(UNPACKED_ID));
        assert!(!valid_id("STORE_ID_PENDING") && !valid_id("abc"));
        // A placeholder store ID is never served, registered or linked.
        assert_eq!(store_id().is_some(), valid_id(STORE_ID));
        assert!(chromium_ids().iter().all(|id| valid_id(id)));
        assert_eq!(store_page().is_some(), store_id().is_some());
    }

    /// The store's copy and the app folder's (unpacked) both reach the host: the manifests'
    /// allowed_origins and the host's own caller check are this list.
    #[test]
    fn store_and_unpacked_both_served() {
        assert_eq!(STORE_ID, "bobmhloppnfipdjjncalidjenegfgebg");
        assert_eq!(UNPACKED_ID, "oogbclbbninliongijffeeggalppliok");
        let ids = chromium_ids();
        assert!(
            ids.contains(&UNPACKED_ID) && ids.contains(&STORE_ID),
            "{ids:?}"
        );
        assert_eq!(
            store_page().as_deref(),
            Some(
                "https://chromewebstore.google.com/detail/auralis-download-manager/bobmhloppnfipdjjncalidjenegfgebg"
            )
        );
    }

    #[test]
    fn store_status_requires_the_correct_browsers_verified_handshake() {
        let profile = tempfile::tempdir().unwrap();
        let profile = profile.path();
        let handshake = profile.join(StoreBrowser::Chrome.marker());
        let history = profile.join(SEEN);
        let status = || browser_store_status_in(profile, StoreBrowser::Chrome);
        assert_eq!(status(), BrowserStoreStatus::default());
        std::fs::write(&history, "Google Chrome\t0.1.10\n").unwrap();
        std::fs::write(
            profile.join(HANDSHAKE),
            format!("Google Chrome\t{STORE_ID}"),
        )
        .unwrap();
        assert!(status().browser_previously_connected);
        assert!(!status().connected_recently);

        for record in [
            format!("Microsoft Edge\t{STORE_ID}"),
            format!("Google Chrome\t{AURALIS_UNPACKED_ID}"),
            format!("Google Chrome\t{STORE_ID}\tother"),
            format!("Google Chrome\t{STORE_ID}{}", "x".repeat(256)),
        ] {
            std::fs::write(&handshake, record).unwrap();
            assert!(!status().connected_recently);
        }

        std::fs::write(&handshake, format!("Google Chrome\t{STORE_ID}")).unwrap();
        assert_eq!(
            status(),
            BrowserStoreStatus {
                connected_recently: true,
                connected_source: Some("store"),
                extension_previously_connected: true,
                store_previously_connected: true,
                browser_previously_connected: true,
            }
        );
        let old = std::time::SystemTime::now() - HANDSHAKE_LIFETIME - Duration::from_secs(1);
        File::options()
            .write(true)
            .open(&handshake)
            .unwrap()
            .set_times(std::fs::FileTimes::new().set_modified(old))
            .unwrap();
        assert!(!status().connected_recently);
        assert!(status().store_previously_connected);
        assert!(status().browser_previously_connected);

        std::fs::write(
            profile.join(StoreBrowser::Edge.marker()),
            format!("Microsoft Edge\t{STORE_ID}"),
        )
        .unwrap();
        assert!(!status().connected_recently);
        assert!(browser_store_status_in(profile, StoreBrowser::Edge).connected_recently);
    }

    #[test]
    fn verifies_only_the_project_unpacked_copy_in_the_identified_browser() {
        assert!(is_auralis_chromium_id(STORE_ID));
        assert!(is_auralis_chromium_id(AURALIS_UNPACKED_ID));
        assert!(!is_auralis_chromium_id(UNPACKED_ID));
        assert!(!is_auralis_chromium_id(LEGACY_STORE_ID));
        let profile = tempfile::tempdir().unwrap();
        let profile = profile.path();
        let handshake = profile.join(StoreBrowser::Edge.unpacked_marker());
        let status = || browser_store_status_in(profile, StoreBrowser::Edge);
        for record in [
            format!("Microsoft Edge\t{LEGACY_STORE_ID}"),
            format!("Microsoft Edge\t{UNPACKED_ID}"),
            format!("Google Chrome\t{AURALIS_UNPACKED_ID}"),
        ] {
            std::fs::write(&handshake, record).unwrap();
            assert_eq!(status(), BrowserStoreStatus::default());
        }
        std::fs::write(&handshake, format!("Microsoft Edge\t{AURALIS_UNPACKED_ID}")).unwrap();
        assert_eq!(
            status(),
            BrowserStoreStatus {
                connected_recently: true,
                connected_source: Some("unpacked"),
                extension_previously_connected: true,
                store_previously_connected: false,
                browser_previously_connected: true,
            }
        );
        assert_eq!(
            browser_store_status_in(profile, StoreBrowser::Chrome),
            BrowserStoreStatus::default()
        );
    }

    #[test]
    fn windows_browser_requires_the_vendor_and_executable() {
        assert_eq!(
            StoreBrowser::from_windows_executable(
                r"C:\Program Files\Google\Chrome\Application\chrome.exe"
            ),
            Some(StoreBrowser::Chrome)
        );
        assert_eq!(
            StoreBrowser::from_windows_executable(
                r"C:\Program Files (x86)\Microsoft\Edge Beta\Application\msedge.exe"
            ),
            Some(StoreBrowser::Edge)
        );
        assert_eq!(
            StoreBrowser::from_windows_executable(r"C:\Imput\Helium\Application\chrome.exe"),
            None
        );
        assert_eq!(
            StoreBrowser::from_windows_executable(r"C:\Google\Chrome\Application\chromium.exe"),
            None
        );
    }

    #[test]
    fn presence_requires_a_known_identity_and_ordinary_profile_files() {
        use BrowserExtensionPresence::*;
        let root = tempfile::tempdir().unwrap();
        let root = root.path().canonicalize().unwrap();
        let profile = root.join("Profile 1").join("Extensions");
        let other = profile.join(LEGACY_STORE_ID).join("0.1.10_0");
        let unpacked = profile.join(AURALIS_UNPACKED_ID).join("0.1.10_0");
        let official = profile.join(STORE_ID).join("0.1.10_0");
        assert_eq!(StoreBrowser::extension_presence_in(&root), Unverified);
        let default = root.join("Default");
        std::fs::create_dir(&default).unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Unverified);
        std::fs::write(default.join("Preferences"), []).unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Missing);
        std::fs::create_dir_all(&other).unwrap();
        std::fs::write(other.join("manifest.json"), b"{}").unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Missing);
        std::fs::create_dir_all(&official).unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Unverified);
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(other.join("manifest.json"), official.join("manifest.json"))
                .unwrap();
            assert_eq!(StoreBrowser::extension_presence_in(&root), Unverified);
            std::fs::remove_file(official.join("manifest.json")).unwrap();
        }
        std::fs::create_dir_all(&unpacked).unwrap();
        std::fs::write(unpacked.join("manifest.json"), b"{}").unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Unpacked);
        std::fs::write(official.join("manifest.json"), b"{}").unwrap();
        assert_eq!(StoreBrowser::extension_presence_in(&root), Store);
    }

    #[test]
    fn seen_lines_old_and_new() {
        assert_eq!(
            parse_seen("Google Chrome\n"),
            vec![("Google Chrome".into(), String::new())]
        );
        assert_eq!(
            parse_seen("Google Chrome\t0.2.5\nMozilla Firefox\t0.2.5\n").len(),
            2
        );
    }
}
