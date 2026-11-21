# Auralis Browser Extension Privacy Policy

Effective date: November 21, 2026

This policy explains how the Auralis browser extension handles information when connecting your browser to Auralis Download Manager. It applies to the extension and its interaction with Auralis; websites, browsers, operating systems, and other software have their own privacy practices.

## Information the extension accesses

Depending on your settings and actions, the extension can access:

- Download and link details, such as URLs, filenames, file types and sizes, the page a download came from, and page or video titles.
- Website and network information needed to find downloads and supported media, including page and media URLs, redirects, request and response metadata, referrer and origin headers, and content used to identify media streams. Some URLs and headers can contain personal information or access tokens.
- Request data from navigation and download requests, including supported form or POST data. Such data may contain personal or sensitive information if a website includes it in a request.
- Cookies and session information for relevant websites, including sign-in cookies, when required for download handoff or when a browser session is selected for a video lookup. Cookies can grant access to your accounts and should be treated as credentials.
- Extension settings and integration information, including capture preferences, excluded sites, video-button settings, the optional browser proxy setting, and a remote pairing token if a remote destination is configured.
- Browser proxy configuration when you choose to enable the browser proxy option. This option is disabled by default.

The extension requires access to websites because downloads and media may come from different domains. Its packaged scripts inspect pages for supported media or links and provide download controls. Chrome's site-access and incognito permissions control where the extension can run.

## How information is used and shared

The extension uses this information to identify and hand off downloads, find available media, preserve the request context needed by the destination website, and maintain your chosen settings. It may make requests to the relevant website to identify media or perform functions you choose.

Normally, the extension communicates with the Auralis application on your computer through native messaging. Depending on the task and your choices, it may send the application URLs, filenames, page context, request data, cookies and other information needed to perform the requested download. Auralis and its configured helpers, such as yt-dlp and FFmpeg, may then contact the relevant websites to resolve or download content. Those websites receive requests and any relevant session information in accordance with their own policies.

If you explicitly pair the extension with a remote download destination, it sends the download URL to that destination over HTTPS using a pairing token. URLs themselves may contain sensitive information. The extension's remote handoff does not include browser cookies; the remote service and its operator handle information they receive under their own practices.

If you choose the YouTube cookie-export feature, the extension creates a local cookies file for use with Auralis or a supported tool. Anyone with access to that file may be able to use the session. Store it securely and delete it when you no longer need it.

The extension code does not include a dedicated analytics or advertising service. Browser vendors, websites, GitHub, and any remote service you choose may process information under their own policies.

## Storage and retention

The extension stores preferences and integration settings in browser extension storage. It also keeps some request and media context temporarily in memory to support download and video detection. The Auralis application may retain download records, files and other information needed for downloads according to its own settings. Exported cookie files remain where your browser saves them until you delete them.

You can clear the extension's stored settings by removing the extension and its data in your browser. Delete downloaded files, cookie exports and Auralis download records separately when no longer needed. Removing the extension does not automatically delete data already handed to another application or a remote service.

## Your choices

You can pause or configure download capture, exclude sites, change video controls, limit extension site access in Chrome, choose available cookie options, and turn the browser proxy option on or off. You can disconnect a configured remote destination and uninstall the extension. Browser controls also determine whether the extension may operate in incognito windows.

## Security

The extension uses the browser's native-messaging mechanism for local integration and HTTPS for a user-configured remote destination. No method of storage or transmission is completely secure. Protect access to your computer, paired services and exported cookie files.

## Changes and contact

This policy may be updated when the extension or its data practices change. The effective date at the top will be updated when changes are made. For questions or requests concerning the extension, open an issue at https://github.com/4ls4mi/Auralis-Download-Manager/issues. Do not include passwords, cookies, access tokens, private URLs or other sensitive information in a public issue.
