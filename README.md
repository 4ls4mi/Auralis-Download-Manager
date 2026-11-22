# Auralis Download Manager

[English](README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt-BR.md) · [简体中文](README.zh-CN.md)

Auralis is a free Windows x64 download manager with a glass-inspired interface, detailed transfer controls and its own browser extension. It is an independent GPL-3.0 fork of [Mister Download Manager](https://github.com/anefzaoui/misterdownloadmanager); it is not an official upstream release.

[Download Auralis for Windows](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Download the Auralis browser extension](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [Release notes](https://github.com/4ls4mi/Auralis-Download-Manager/releases)

## Screenshots

### Download manager

![Download manager](docs/images/auralis/user-picture-1.png)

### Live download

![Live download](docs/images/auralis/user-picture-2.png)

![▶ Watch the download video (muted)](docs/images/auralis/download-demo.gif)

### Download file information

![Download file information](docs/images/auralis/user-picture-3.png)

### Download completed

![Download completed](docs/images/auralis/user-picture-4.png)

### Appearance settings

![Appearance settings](docs/images/auralis/user-picture-5.png)


## What you can do with Auralis

### Downloads, queues and speed

- Add an HTTP, HTTPS or FTP link, or send a supported download from your browser. See the file's progress, speed, connection activity and remaining time in its download window.
- Pause and resume where the source supports it, group downloads into queues, schedule them and set speed limits. The system tray keeps controls available while a window is hidden.
- Multi-connection downloads write received bytes to their positions in one temporary file as they arrive. Ordinary segmented files therefore do not normally need separate chunk files joined at the end; disk flushing and verification can still take time.

### Check and recover an interrupted download

- **Check saved data** compares downloaded blocks with recorded local hashes. It can identify later changes to those blocks; local hashes do not prove the server originally sent the correct data, and older data without hashes cannot be checked this way.
- **Check source and repair** can prepare changed ranges for re-download when a compatible HTTP source supports the required ranges and validation. A server that does not provide ranges cannot be forced to resume from an arbitrary position. Expired or changed links can also prevent a resume.
- Under **Find a torrent for recovery**, you can request a search of Internet Archive, choose a `.torrent` file or compare a magnet link. Matching complete pieces can be copied into a separate recovery folder and the download continued from torrent peers; the original partial file is kept. Matching some pieces does not prove the rest of the file is identical. Searches disclose filename terms to Internet Archive, and magnet checks contact peers. Private downloads and downloads with an expected whole-file checksum are currently excluded from this fallback.
- Supported whole-file checksums supplied by a server can be used to verify a completed download. Automatic torrent fallback and full-file backup are still in development.

### Video, audio and torrents

- With the browser extension and yt-dlp set up, look up available video and audio qualities on supported pages and choose subtitles where offered. Some sources need FFmpeg for final audio/video processing; availability depends on the site.
- Add a `.torrent` file or magnet, review the files and destination, and download from available peers. Torrent pieces can be rechecked using the torrent's hashes.

### Appearance, settings and backup

- Choose themes, surface materials, progress bars, connection indicators and graphs independently. Liquid styles animate the progress, connections and graph using the downloader's actual values; colors can be adjusted in Appearance settings.
- Export the current theme to an editable JSON file and import it again. The export includes the palette, surface material, typography and independent indicator choices. Wallpaper files are not embedded. See the [theme format](docs/auralis-theme-format.md) if you or an assistant want to edit it.
- Save and restore appearance and download **preferences**. The current preferences backup does **not** include downloaded files, partial files or download history, and excludes passwords, account credentials and browser cookies. A full-file backup is in development.
- Choose whether Auralis starts with Windows and use update notices and the system tray to keep downloads accessible.

## Guides and recovery

Read the [English guide](docs/auralis-guide-drafts/en.md) or [Arabic guide](docs/auralis-guide-drafts/ar.md). Short guides are also available in [French](docs/auralis-guide-drafts/fr.md), [German](docs/auralis-guide-drafts/de.md), [Spanish](docs/auralis-guide-drafts/es.md), [Portuguese](docs/auralis-guide-drafts/pt-BR.md) and [Simplified Chinese](docs/auralis-guide-drafts/zh-CN.md). These guides are being updated alongside the app.

Ordinary segmented downloads write their received bytes directly into a single temporary file. Saved-data checking can detect changes in blocks that have recorded hashes; repair depends on a compatible server and cannot make a server support byte ranges. For a stopped direct download, the recovery window can compare a chosen torrent or magnet, or search Internet Archive after you request it. Matching saved pieces do not prove the remaining content is identical. Torrent recovery needs peers and retains the original partial file. Automatic fallback is still in development.

Appearance settings can export and import an editable theme JSON; indicator choices are included. Preferences backup does not yet include downloaded files, partial files or download history. A full-file backup is being developed.

## Installation

1. Download and run the Windows x64 installer from the [latest release](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest).
2. Open **Settings → Browser Integration** to prepare the connection and media helpers, and install the matching browser extension. Approve the browser's installation prompt when required.
3. Choose a destination in **Settings → Downloads**, then use **Add URL** or send a supported link from the browser. Double-click a download to open its progress window.
4. Open **Settings → Appearance** to choose themes, materials and indicator styles; use **Export current theme…** and **Import theme…** to save and load an editable theme.

## License and attribution

Auralis is distributed under the [GNU GPL v3](LICENSE). It is a fork of Mister Download Manager by Ahmed Nefzaoui and contributors; see [ATTRIBUTION.md](ATTRIBUTION.md) and the [upstream project](https://github.com/anefzaoui/misterdownloadmanager).
