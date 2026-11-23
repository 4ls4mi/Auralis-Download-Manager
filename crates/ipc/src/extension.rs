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
const CHROME_STORE_HANDSHAKE: &str = "extension-chrome-store-handshake";
const HANDSHAKE_LIFETIME: Duration = Duration::from_secs(120);
const GOOGLE_CHROME: &str = "Google Chrome";

/// The host, started by a browser for the extension: the extension is installed there. The
/// file holds one line per browser (`capture::browser_named`), with the extension's version.
pub fn mark_seen(browser: &str, version: &str, extension_id: Option<&str>) {
    let Some(dir) = crate::data_dir() else {
        return;
    };
    // Timestamp a real browser-to-host handshake independently of historical installs.
    let _ = crate::private_dir(&dir);
    let id = extension_id.filter(|id| valid_id(id)).unwrap_or("");
    let handshake = format!("{browser}\t{id}");
    let _ = crate::private_write(&dir.join(HANDSHAKE), handshake.as_bytes());
    if browser == GOOGLE_CHROME && store_id() == Some(id) {
        let _ = crate::private_write(&dir.join(CHROME_STORE_HANDSHAKE), handshake.as_bytes());
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

/// A recent Chrome Web Store connection and separate historical familiarity with Chrome.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct ChromeStoreStatus {
    pub connected_recently: bool,
    pub store_previously_connected: bool,
    pub chrome_previously_connected: bool,
}

pub fn chrome_store_status() -> ChromeStoreStatus {
    crate::data_dir().map_or_else(ChromeStoreStatus::default, |dir| {
        chrome_store_status_in(&dir)
    })
}

fn chrome_store_status_in(dir: &Path) -> ChromeStoreStatus {
    // The native host replaces this record atomically. Read its timestamp and both values
    // through one open handle so another browser cannot replace only half of the result.
    let read_chrome_handshake = |name| {
        let file = File::open(dir.join(name)).ok()?;
        let modified = file.metadata().ok()?.modified().ok()?;
        let record = bounded_text(file, 256)?;
        let (browser, id) = record.split_once('\t')?;
        (browser == GOOGLE_CHROME).then_some((store_id() == Some(id), modified))
    };
    let handshake = read_chrome_handshake(HANDSHAKE);
    // A different browser or unpacked extension can replace the shared record at any time.
    // Preserve Chrome Store history separately and honor existing shared records on upgrade.
    let store_handshake = read_chrome_handshake(CHROME_STORE_HANDSHAKE)
        .into_iter()
        .chain(handshake)
        .filter_map(|(official, modified)| official.then_some(modified))
        .max();
    let connected_recently = store_handshake
        .is_some_and(|modified| modified.elapsed().is_ok_and(|age| age < HANDSHAKE_LIFETIME));
    // Older records describe the browser and version only. They can prevent a repeat
    // invitation, but cannot identify which extension is installed in that browser.
    let chrome_previously_connected = store_handshake.is_some()
        || handshake.is_some()
        || File::open(dir.join(SEEN))
            .ok()
            .and_then(|file| bounded_text(file, 16 * 1024))
            .is_some_and(|history| {
                history
                    .lines()
                    .any(|line| line.split('\t').next() == Some(GOOGLE_CHROME))
            });
    ChromeStoreStatus {
        connected_recently,
        store_previously_connected: store_handshake.is_some(),
        chrome_previously_connected,
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
    fn chrome_store_status_uses_a_fresh_matching_handshake() {
        let profile = tempfile::tempdir().unwrap();
        let profile = profile.path();
        let handshake = profile.join(HANDSHAKE);
        let history = profile.join(SEEN);
        let status = || chrome_store_status_in(profile);
        assert_eq!(status(), ChromeStoreStatus::default());
        std::fs::write(&history, "Google Chrome\t0.1.10\n").unwrap();
        assert!(status().chrome_previously_connected);
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
            ChromeStoreStatus {
                connected_recently: true,
                store_previously_connected: true,
                chrome_previously_connected: true,
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
        assert!(status().chrome_previously_connected);

        std::fs::write(
            profile.join(CHROME_STORE_HANDSHAKE),
            format!("Google Chrome\t{STORE_ID}"),
        )
        .unwrap();
        std::fs::write(&handshake, format!("Microsoft Edge\t{STORE_ID}")).unwrap();
        assert!(status().connected_recently);
        assert!(status().store_previously_connected);
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
