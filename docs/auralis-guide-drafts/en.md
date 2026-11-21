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

## Back up preferences

In **Settings → General → Preferences backup**, choose **Save backup** and keep the resulting file somewhere safe. On a new installation choose **Restore backup** there, or use the first-install restore prompt if shown. The current backup includes preferences and appearance, including custom materials; it does **not** include downloaded files, partial downloads or download history. Passwords, account credentials and browser cookies are excluded. Paths may need updating on a new PC. A backup that also includes downloaded files and partial downloads is in development.

## Windows startup and updates

Use **Settings → General** to choose whether Auralis starts with Windows and whether it starts minimized. The tray provides controls when the main window is hidden. Under **Advanced → Updates**, choose how update notifications appear, check for a release and review its details before installing.

## Integrity and limitations

When a supported whole-file checksum is supplied by a server, Auralis can use it to check the completed download. A locally generated hash can detect later changes to data but cannot independently prove what the server originally sent. In the download window, **Check saved data** checks blocks with saved hashes. For compatible HTTP sources, **Check source and repair** can prepare changed ranges for downloading again. Under **Find a torrent for recovery**, you can request an Internet Archive search, choose a torrent file, or compare a magnet. A matching piece does not verify the remaining file. Continuing uses torrent peers, saves to a separate folder and preserves the original partial. Torrent recovery currently excludes private downloads and downloads with an expected whole-file checksum. Automatic torrent fallback and full-file backup are still in development.
