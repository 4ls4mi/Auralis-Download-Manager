# Auralis WinUI shell — development only

This is the beginning of a WinUI 3 replacement for the current shell, not a
working downloader and not a release. It requests native Windows desktop
Acrylic, Mica and Mica Alt on the window so they can be evaluated over real
Windows content. Mica and Acrylic are different system backdrops: Windows
controls their supported versions and may reduce effects according to system
settings. The preview has no connection to saved settings or download data.

The existing Auralis app, Rust downloader, browser integration and release
installer are unchanged by this prototype. The replacement still needs the
real interface, a secure bridge to the existing downloader, the tray and
multi-window lifecycle, settings and theme migration, window controls, update
and installer integration, accessibility, and end-to-end Windows tests before
it can replace the current shell.

To build on Windows x64 with .NET 8 and the Windows App SDK prerequisites:

```powershell
dotnet build winui-shell/Auralis.WinUI/Auralis.WinUI.csproj -c Debug -p:Platform=x64
```

Native backdrop visibility must be checked on Windows; a successful build alone
does not establish that the material looks right or works on every system.
