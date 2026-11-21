# WinUI migration work

This is an implementation checklist for the development branch. The WinUI
preview is not yet the application and must not be packaged as a release.

## Native window and materials

- The preview selects a Windows system backdrop for each built-in material and
  applies a translucent theme-coloured overlay. One window has one system
  backdrop at a time; Mica and Acrylic are different Windows effects.
- The isolated visual preview hosts the real local interface with sample data and forwards validated material and theme changes to a native appearance callback. It blocks external resources and cannot access the downloader. Verify the visual result on Windows; the production WebView host and downloader remain unconnected.
- Connect material and theme selection to the saved Auralis appearance,
  including custom material JSON. Preserve per-window background choices,
  focus states, readability, keyboard navigation, resizing, tiling and high DPI.
- Verify on Windows with real changing windows and wallpaper behind Auralis.
  Windows version and accessibility/transparency settings may affect effects.

## Downloader and command boundary

- The Rust bridge currently has only start, stop, download-list, visual-state,
  single-download start/pause and add-link operations, and a restricted subset of settings reads and writes. The development host now starts the engine in a new separate development directory and exposes list, visuals, settings reads, isolated display and connection preferences, queue controls and HTTP/HTTPS test downloads in its development folder. Its isolated test must pass on Windows before production integration.
  Do not expose an arbitrary IPC command or credentials to a web view.
- A limited set of scalar download and connection preferences, including
  network adapter and proxy authentication, is available in the isolated
  development profile. Stored proxy passwords are never returned to the
  interface. Remaining preferences and integration controls require separate
  production-safe handling; empty sections in the preview are not evidence of
  feature parity.
- The development bridge exposes read-only checking of stopped test-download
  checkpoints, checksums for completed test files, and replacement HTTP/HTTPS
  addresses for stopped test downloads. These paths still require Windows and
  backend integration tests before production use. Torrent recovery and
  saved-data repair remain separate, unfinished work.
- Preserve the existing instance lock, data directory, authenticated local IPC,
  downloader shutdown and in-progress download state. Starting a second shell
  must not take over or stop a running instance.
- Port and test download actions, add URL, queues, properties, torrent recovery,
  browser integration and media tools before making the shell the default.

## Shell parity

- Preview settings and progress windows share an isolated WebView profile and
  support native minimize, maximize and close. Complete and validate resize,
  drag, production lifecycle, all tray actions and close-to-tray semantics.
- The development shell contains opt-in startup registration, release checking,
  in-app update notices and a Windows-notification path. Validate notifications
  on Windows and complete installer verification and safe installation before
  enabling updates. Port preferences/theme backup, dialogs, file selection,
  browser native host, and helper setup.
- Test fresh install and upgrade from the released shell with existing downloads
  and settings. Produce a separate signed-off release only after these checks.
