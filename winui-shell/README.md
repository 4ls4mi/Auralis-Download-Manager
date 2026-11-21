# Auralis WinUI shell — development only

This is the beginning of a WinUI 3 replacement for the current shell, not a
working downloader and not a release. It requests native Windows desktop
Acrylic, Mica and Mica Alt for the built-in material names, with light and dark
preview overlays, so they can be evaluated over real Windows content. Mica and Acrylic are different system backdrops: Windows
controls their supported versions and may reduce effects according to system
settings. The preview has no connection to saved settings or download data.

The **Preview interface** and **Appearance settings** buttons display the real
local interface inside an isolated WebView profile, using sample empty data.
The preview disables downloader operations and blocks external navigation and
network resources. Material and theme changes request native backdrops; they do
not modify the installed app. Build the interface assets first with
`cd glass-ui; npm install; npm run build`.

The **Isolated downloader** button starts the Rust engine in a fresh temporary
folder and shows its empty download list and settings through a restricted bridge. A few display preferences can be changed in the
temporary profile. Download actions are disabled. Closing the window stops the test engine; this
mode does not use the installed app's data. Windows validation is still needed.

The existing Auralis app, Rust downloader, browser integration and release
installer are unchanged by this prototype. A narrow Rust bridge for the embedded downloader, its list and visual state,
single-download start/pause, add-link and a restricted set of settings controls is under development in `crates/auralis-winui-bridge`.
The sample preview does not load it or touch the user’s data. The replacement still needs a
production connection to the real interface, the remaining secure bridge operations, the tray and
multi-window lifecycle, settings and theme migration, window controls, update
and installer integration, accessibility, and end-to-end Windows tests before
it can replace the current shell.

To build on Windows x64 with .NET 8, Visual Studio MSBuild and the Windows App SDK prerequisites:

```powershell
MSBuild winui-shell/Auralis.WinUI/Auralis.WinUI.csproj /restore /p:Configuration=Debug /p:Platform=x64
```

Native backdrop visibility must be checked on Windows; a successful build alone
does not establish that the material looks right or works on every system.
