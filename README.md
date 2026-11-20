# Auralis Download Manager

Auralis is a free Windows x64 download manager with a glass-inspired interface, detailed transfer controls and its own browser extension. It is an independent GPL-3.0 fork of [Mister Download Manager](https://github.com/anefzaoui/misterdownloadmanager); it is not an official upstream release.

[Download Auralis for Windows](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Download the Auralis browser extension](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Release notes](https://github.com/4ls4mi/Auralis-Download-Manager/releases)

## Screenshots

New screenshots are being captured from the running Windows application.

## Features

- Multi-connection downloads with pause and resume, queues, bandwidth controls and a live transfer graph.
- A dedicated browser extension for sending downloads and supported media links to Auralis. See the release assets for Chromium-based browsers and Firefox; browser-specific installation and permissions are required.
- Separate download, file information, completion and settings windows, with independently configurable materials, colors and indicator previews.
- System-tray controls, optional Windows startup, and a separate tray icon for hidden download windows.
- Video and audio quality lookup using yt-dlp, with browser-session and manual cookie options where supported.
- In-app release notifications and updates, plus preferences backup and restore.
- The downloader runs inside Auralis. A small native messaging helper is used when a browser communicates with the application.

Credentials and browser cookies are excluded from preferences backups; you may need to sign in again on a new Windows installation. Browser and site restrictions can still affect video lookup.

## Installation

Download the Windows x64 installer from the [latest release](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) and run it. To connect a browser, install the matching Auralis extension from the release assets and follow the instructions in **Settings → Browser Integration**.

## License and attribution

Auralis is distributed under the [GNU GPL v3](LICENSE). It is a fork of Mister Download Manager by Ahmed Nefzaoui and contributors; see [ATTRIBUTION.md](ATTRIBUTION.md) and the [upstream project](https://github.com/anefzaoui/misterdownloadmanager).
