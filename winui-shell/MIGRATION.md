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
  single-download start/pause and add-link operations, and a restricted subset of settings reads and writes. The development host now starts the engine in a new temporary test directory and exposes list, visuals, settings reads and a small set of isolated display preference changes. Its isolated test must pass on Windows before production integration.
  Do not expose an arbitrary IPC command or credentials to a web view.
- Preserve the existing instance lock, data directory, authenticated local IPC,
  downloader shutdown and in-progress download state. Starting a second shell
  must not take over or stop a running instance.
- Port and test download actions, add URL, queues, properties, torrent recovery,
  browser integration and media tools before making the shell the default.

## Shell parity

- Restore multiple progress windows and independent minimize, maximize, resize,
  drag and tray behavior; keep all tray actions and close-to-tray semantics.
- Port notifications, update checks/install, startup, preferences/theme backup,
  dialogs, file selection, clipboard, browser native host, and helper setup.
- Test fresh install and upgrade from the released shell with existing downloads
  and settings. Produce a separate signed-off release only after these checks.
