# Auralis browser integration (development build)

This extension is based on the Mister Download Manager browser integration and requires a matching Auralis desktop build with its native messaging host registered. The Chromium manifest uses a separate development identity; it can be loaded unpacked in Chrome or Edge developer mode. For Firefox development, use `manifest.firefox.json` as `manifest.json` and load it as a temporary add-on in `about:debugging`. Permanent Firefox installation requires signing. Safari needs its own signed application extension; this directory is not a Safari installer.

Cookies pasted into the video menu are session credentials. They are held in the extension page and sent to the local Auralis helper for the selected lookup; close the page when finished and do not share them. Website authentication and available video or subtitle formats still depend on the site and the installed helpers.
