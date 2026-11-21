# Auralis WinUI shell — development only

This is a WinUI 3 development preview, not a replacement for the current shell
and not a release. It requests native Windows desktop
Acrylic, Mica and Mica Alt for the built-in material names, with light and dark
preview overlays, so they can be evaluated over real Windows content. Mica and Acrylic are different system backdrops: Windows
controls their supported versions and may reduce effects according to system
settings. The preview does not use installed settings or download data.

The **Preview interface** and **Appearance settings** buttons display the real
local interface inside an isolated WebView profile, using sample empty data.
The sample preview disables downloader operations and blocks external navigation and
network resources. The interface minimize, maximize/restore and close controls address the native
preview window. Material and theme changes request native backdrops; they do
not modify the installed app. Build the interface assets first with
`cd glass-ui; npm install; npm run build`.

The **Isolated downloader** button starts the Rust engine in a fresh temporary
folder and shows its empty download list and settings through a restricted bridge. A few display preferences can be changed in the
temporary profile. HTTP and HTTPS test downloads use its temporary downloads
folder; the test interface supports start, pause and per-file speed limits. Closing the window stops the test engine; this
mode does not use the installed app's data. Windows validation is still needed.

Test files remain in the temporary profile; this preview does not import or alter
the installed app’s download list.

The existing Auralis app, Rust downloader, browser integration and release
installer are unchanged by this prototype. A narrow Rust bridge for the embedded downloader, its list and visual state,
single-download start/pause, add-link and a restricted set of settings controls is under development in `crates/auralis-winui-bridge`.
The sample preview does not load it or touch the user’s data. Preview windows share their isolated appearance settings and close with the main window.
The replacement still needs a production connection to the real interface, the remaining
secure bridge operations, tray and production lifecycle, settings and theme migration, update
and installer integration, accessibility, and end-to-end Windows tests before
it can replace the current shell.

To build on Windows x64 with .NET 8, Visual Studio MSBuild and the Windows App SDK prerequisites:

```powershell
MSBuild winui-shell/Auralis.WinUI/Auralis.WinUI.csproj /restore /p:Configuration=Debug /p:Platform=x64
```

The desktop preview reduces the old WebView surface layers, including the
Frosted Layers canvas, to give the Windows backdrop room to show through.
The validation workflow uploads a temporary **auralis-winui-development-preview**
artifact after its checks pass. Extract all files before launching
`Auralis.WinUI.exe`; keep the adjacent DLLs and `interface` folder together.
This development build may require the .NET 8 Desktop Runtime and WebView2
Runtime. It is not an installer or replacement for the released app.

Native backdrop visibility must be checked on Windows; a successful build alone
does not establish that the material looks right or works on every system.
