# Auralis WinUI shell — development only

This is the beginning of a WinUI 3 replacement for the current shell, not a
working downloader and not a release. It requests native Windows desktop
Acrylic, Mica and Mica Alt for the built-in material names, with light and dark
preview overlays, so they can be evaluated over real Windows content. Mica and Acrylic are different system backdrops: Windows
controls their supported versions and may reduce effects according to system
settings. The preview has no connection to saved settings or download data.

The existing Auralis app, Rust downloader, browser integration and release
installer are unchanged by this prototype. A narrow Rust bridge for starting and stopping an embedded downloader and reading
its list and visual state is under development in `crates/auralis-winui-bridge`.
The preview does not load it or touch the user’s data. The replacement still needs the
real interface, the remaining secure bridge operations, the tray and
multi-window lifecycle, settings and theme migration, window controls, update
and installer integration, accessibility, and end-to-end Windows tests before
it can replace the current shell.

To build on Windows x64 with .NET 8, Visual Studio MSBuild and the Windows App SDK prerequisites:

```powershell
MSBuild winui-shell/Auralis.WinUI/Auralis.WinUI.csproj /restore /p:Configuration=Debug /p:Platform=x64
```

Native backdrop visibility must be checked on Windows; a successful build alone
does not establish that the material looks right or works on every system.
