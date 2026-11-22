# Auralis Download Manager — feature guide (draft)

This is a draft for the next release. Check the final interface and release notes before publishing; features still in development are not described as available.

## Get started

1. Install the Windows x64 application from the [latest release](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest).
2. Open **Settings → Browser Integration** and use **Set up everything** to prepare the browser connection and missing media helpers. Install the appropriate extension in your browser and approve the browser's installation prompt when required.
3. Choose a download folder in **Settings → Downloads**. You can also set categories and other preferences there.

## Download and resume

Click **Add URL**, paste an HTTP, HTTPS or FTP address, review the name and destination, and start the download. Or use the browser extension to send a supported link. Double-click a list item to open its progress window. The window shows progress, connection activity, transfer speed and whether resume is supported.

Use **Pause** and **Resume** for an interrupted transfer. Resume depends on the source and on the file remaining the same. If a signed address expires, stop the download, choose **Refresh download address**, supply a new address for the same file, and try again. A server that cannot send byte ranges may not be resumable. Auralis keeps ordinary segmented downloads in one temporary file as bytes arrive, so they do not normally require a final merge of separate chunk files. Disk flushes and verification can still take time.

## Queues, scheduling and limits

Select downloads and use **Add to queue** to group them. Open **Scheduler** to set queue timing and completion actions. The progress window's **Speed Limiter** controls a file's limit; connection and general download settings provide additional controls.

## Browser video and audio

With the extension connected and yt-dlp available, open a supported video page and use the Auralis control to look up available video and audio qualities. Choose subtitles before starting when offered. Sizes are shown when the source provides them; unavailable sizes are labelled accordingly. Some streams need separate video and audio files to be joined with FFmpeg. Availability depends on the source and its restrictions.

## Torrents

Use **Add Torrent** to open a `.torrent` file or paste a magnet link. Review the files and destination before starting. Torrent downloads use peers and can be rechecked using their piece hashes. A torrent is only useful while matching data is available from peers.

## Appearance and liquid indicators

Open **Settings → Appearance** to choose a color theme and surface material. Under **Indicators**, choose the progress bar, connection and graph styles, shapes and colors independently. Liquid styles animate the indicators while the values come from actual transfer information.

To export the current theme, select **Export current theme…**, edit the JSON and use **Import theme…**. The file is declarative data, not executable code; see [the material format](../auralis-material-format.md). You can ask someone or an AI assistant to help edit it, then review and import the resulting file.

## Back up and restore

In **Settings → General → Download backup**, choose **Back up downloads…**. Stop active transfers, checks and queues first. The `.auralis-backup` archive saves settings, appearance, history, queues, supported downloaded files and saved progress. On the new installation select **Restore downloads…**, choose the archive and pick a destination for the restored files.

To copy only settings and appearance, use **General → Preferences backup → Save backup…**. Import the JSON through **Restore backup…** or the first-install restore prompt. Backups exclude passwords, account credentials and browser cookies. Review device-specific paths after restoring.

## Windows startup and updates

Use **Settings → General** to choose whether Auralis starts with Windows and whether it starts minimized. The tray provides controls when the main window is hidden. Under **Advanced → Updates**, choose how update notifications appear, check for a release and review its details before installing.

## Integrity and limitations

When a supported whole-file checksum is supplied by a server, Auralis can use it to check the completed download. A locally generated hash can detect later changes to data but cannot independently prove what the server originally sent. In the download window, **Check saved data** checks blocks with saved hashes. For compatible HTTP sources, **Check source and repair** can prepare changed ranges for downloading again.

In the upcoming Windows build, open **Settings → Torrents → Torrent recovery after a direct download fails** to opt in. After eligible direct downloads exhaust their retries, Auralis searches Internet Archive with words from the filename. Choose **Search for matching torrents, then ask me** to review the match yourself, or enable automatic continuation for a single match with at least two verified pieces and successful candidate checks. Private downloads and those with expected whole-file checksums are excluded.

In the download window, **Find a torrent for recovery** also checks a local torrent file, a magnet, or a public HTTP(S) torrent link. Auralis copies verified pieces to a new recovery folder, keeps the original partial and fetches missing pieces from BitTorrent peers. The download window shows search and transfer details. The list shows **Direct → Torrent** for recovered downloads.
