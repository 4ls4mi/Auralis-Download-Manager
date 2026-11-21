# Mister Hybrid Glass — Windows Tauri/React prototype

**Status:** experimental Windows-first frontend; not a replacement release.

This is a new UI implementation in `glass-ui/` that lives on its own branch. The original Mister Download Manager Rust engine, saved downloads, network stack, resume behavior, and existing install are **not modified**. The glass UI uses the existing MDM IPC/automation API in a **bundled legacy backend executable**. The original application's egui window is started minimized to tray via `/startup` when a running instance isn't available.

## First prototype features

- Genuine React/CSS frosted-glass panes over a user-selected image/video background; **no transparency through other Windows apps**.
- Default Alpine vector wallpaper with customizable PNG/JPG/WebP/MP4/WebM/MOV backgrounds.
- Independent main dashboard and download-details wallpapers. Files are copied into the Tauri app-data wallpapers folder; video playback is muted and looping.
- Eight live-selectable accent themes, opacity/dim/blur controls, adaptive readability over bright wallpapers.
- Real downloads, statuses, bytes, download speeds, and pause/resume/add/remove commands through the existing MDM backend.
- Actual recent speed samples in the charts. Details available as a separate Tauri WebView2 window.
- The colorful block grid is **decorative progress coloring only**. As requested, its colors gradually flow from teal to blue/violet as progress fills. It does not claim network-adapter or peer attribution.
- Explicit empty/offline UI — never fake downloads or speeds.

## How the Windows build works

The GitHub Actions workflow on the `feature/tauri-glass-windows` branch builds the original Rust MDM Windows executable as a backend, copies it into Tauri resources, bundles the original app icon, installs frontend dependencies, and creates an **NSIS Windows x64 installer** for Mister Hybrid Glass.

The first build is expected to be Windows-only, desktop WebView2. It is not an official Mister Download Manager release and does not change the original `main` branch.

## Current limitations (intentional)

- The existing original MDM executable still runs as the actual download engine (normally hidden in the Windows tray); it is **not** yet replaced by an extracted headless service. The Tauri interface talks to it through local authenticated MDM IPC.
- The existing MDM automation API must be enabled for the bridge. The native bridge enables it on local MDM startup/connection, since it is off by default. Its port and token never reach frontend JavaScript.
- Per-connection/peer snapshots and detailed torrent controls are not exposed by the current IPC interface, so this iteration shows real totals but no fabricated connection metrics.
- Some original dialogs and advanced operations still belong to the legacy backend; feature parity requires a later backend service extraction.
- Wallpaper video playback is local, silent, and follows WebView2 codec support; certain MOV/codec combinations may not play on Windows.
- The frontend's live graph samples polling snapshots ~1.5 seconds apart; it is not a historical telemetry database.
- No production code signing or automatic updater for the new Tauri app is configured.
- Visual comparison against approved mockup and Windows integration QA are required before marking this complete.

## Development

On Windows, with the Rust and Node prerequisites:

```powershell
cd glass-ui
npm install
# Builds the original backend in the repository root and copies it into
# src-tauri/resources/mdm-legacy.exe before invoking the Tauri build.
npm run tauri dev
```

For `tauri dev`, the backend may also be supplied by an already-running original Mister Download Manager installation. The bundled backend exe and icon must exist for `tauri build`.

## Security

Only native Rust commands can reach the authenticated MDM IPC channel. The frontend does not receive its bearer token, and no remote API origins are enabled. Wallpapers are copied from the local file chooser to the Tauri app-data path, and only app-data assets are allowed into WebView2.
