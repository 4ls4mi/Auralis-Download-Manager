# Mister Hybrid Glass: Windows x64 validation

This branch retains the original Rust downloader as the bundled headless backend. Glass adapts its existing actions and asynchronous probes; it does not replace the download engine. The original `main` branch is unchanged and no merge is authorized.

## Behavior being validated

- Browser captures open **Download File Info**. The user confirms the category, destination, description, remembered folder and selected connection count before the download is added. Original browser headers and credentials remain in the backend.
- Main-list rows and progress windows independently show overall percentage, selected-count chunk blocks and measured speed history. Choosing 8 or 32 creates exactly that many stable byte-range groups. Their fills are intersections with actual received engine ranges, including adaptive splits and resume. Actual active connection count is shown separately; server limits may allow fewer connections.
- Progress starts with the original compact URL/status/size/downloaded/rate/time/resume/server fields. Connection details expand inside the chunk section. Extended metadata remains in Properties.
- The native shell owns completion transitions while the main window is hidden. It closes progress and opens Download Complete when the preference is enabled. Title bars can hide windows to the single Glass tray; completed files have native drag support.
- Deletion uses a Glass confirmation with separate list removal, disk deletion and remembered confirmation choices. Context-menu operations delegate to original MDM actions.
- Original queue selection, duplicate decisions, scheduler, batch expansion, Link Grabber, archive extraction, checksum verification, categories, site authentication and service sign-in are adapted for Glass. Passwords and saved service credentials are never returned to a WebView.
- Interface material and controls share dark/light tokens. Download indicators keep the navy-to-purple palette independently of the interface theme. Content fits the available window; long lists use pages. Buttons have hover/press feedback and respect reduced-motion preferences.

## Evidence and limits

A successful installer build is **compilation/packaging evidence only**. The native workflow uploads `mister-hybrid-glass-windows-proof` separately from the installer candidate. Its `results.json` records actual assertions; PNGs show real Windows WebViews, not image mockups.

The acceptance script uses an isolated data directory, original native-messaging host, actual Tauri commands and original HTTP engine. A local range server checks browser cookie, referrer and User-Agent handoff. It exercises chosen paths, 8/32 chunk counts, pause/resume, output bytes, checksum verification, completion while main is hidden, safe list removal, optional disk deletion and both color modes. Headless smoke checks include typed settings, write-only secrets, batch parsing and schedule roundtrips.

Windows x64 frontend compilation, chunk-accounting tests, original IPC and native-host tests, installer packaging and headless smoke checks have passed. Native Windows acceptance passed for the rebuilt Glass shell against the original backend from installer candidate run 43819326680. It confirmed the completion setting saves; Pause keeps progress open and Stop from the main list closes it; browser-host capture preserves request context; 8 and 32 measured chunks appear in the progress window; the small main and expanded progress windows fit; actual transfer completion closes progress and opens the completion window while main is hidden; checksum verification and both deletion modes work; and large typography and light/dark appearance propagate. The full installer workflow tests its own bundled backend and must pass separately. The original clipboard watcher was restored after the review candidate backend was built, so it requires verification in the newer full build and hands-on Windows review.

Manual Windows review still covers:

- Actual Chrome/Edge/Firefox extension interception and browser cold start. The framed native-host test does not install or drive a browser extension.
- Explorer/application drag and drop, physical monitors at 100/125/150/200% DPI, native Acrylic and desktop translucency.
- User-selected image/video wallpapers, multiple monitor arrangements and native file pickers.
- Public-server country/flag and measured RTT, proxy/PAC/DNS, FTP, authenticated websites and service accounts.
- Torrent selection/seeding, video-helper flows, archive passwords and external Open/Open With tools.
- Queue wake, dial-up disconnect, exit and computer power actions. CI does not execute shutdown/sleep/hibernate; these retain MDM's original cancellable countdown.

These are verification limits, not claims of proven parity across every original MDM feature. Any remaining migration gaps must be recorded with the actual behavior found during review.

## Known migration gaps

The original application source and downloader are retained, but full UI parity is still being completed. The Glass headless path does not yet expose the original video/playlist selection dialog, and the Click'n'Load listener is disabled in headless mode even though its original preference is present. Remote-control and other advanced original dialogs also need a complete parity review. The original asynchronous clipboard watcher is enabled for the Glass desktop backend and retains the original file-type and preference checks; it still requires hands-on Windows verification. These are open implementation items, not behaviors proven by an installer build.
