# Microsoft Store edition

The Store edition is a separate MSIX distribution of the native Qt app. The
GitHub NSIS installer remains unsigned. Store certification and Microsoft signing
apply to the MSIX distributed through the Store, not the EXE on GitHub.

## Identity and build

Reserve the product as an MSIX app in Partner Center. Copy the exact
Package/Identity/Name, Package/Identity/Publisher and Publisher display name from
Product identity. These public identifiers are not authentication credentials.
Never use guessed publisher values for a submission.

Run the `Auralis Microsoft Store MSIX` workflow with those three inputs from the
branch containing this change. It stages a Store-edition build and uploads an
unsigned `.msix` plus SHA-256 file for submission. The workflow does not submit,
publish, install, create certificates or change system security settings.
Before this workflow is present on the default branch, a commit on
`wip/auralis-qt-shell` with `[build-auralis-store]` also runs it. That path reads
the public `name`, `publisher` and `publisherDisplayName` fields from
`qt-ui/packaging/store-identity.json`, which must first be filled from the reserved
product. No placeholder identity file is committed.

Equivalent local packaging after the standard pinned toolchain is configured:

```powershell
./qt-ui/packaging/build-windows.ps1 -StoreEdition -StageOnly
./qt-ui/packaging/pack-msix.ps1 -StageDirectory $stage `
  -IdentityName $identityName -Publisher $publisher `
  -PublisherDisplayName $publisherDisplayName -OutputDirectory $output
```

The build omits the separately licensed release font bundle and the elevated
Chrome-policy helper. Users install the browser extension from its marketplace
and explicitly connect it using Auralis browser settings. System-wide browser
policy changes are not part of the Store package.

## Runtime and certification

- GitHub updater commands are blocked in the Store edition, including direct
  bridge requests. Update controls open Microsoft Store, and release-push
  notifications are disabled. The Store owns app updates.
- Sign-in startup uses the declared Windows startup task, initially disabled.
  The existing minimized/window choice is saved independently. Windows can refuse
  startup changes when the user or an administrator disabled the task.
- This initial package requires Windows 11 (build 22000+) so browser integration
  can use narrowly scoped virtualization exclusions. Windows 10 users retain the
  existing GitHub installer.
- `runFullTrust` is required for the Qt/Rust desktop downloader and native helper.
  `unvirtualizedResources` is required only to expose this app's five native-host
  registration keys, its native messaging manifests, and its existing download
  profile to browser processes outside the package. The manifest does not disable
  virtualization for all registry entries or all AppData.
- The existing `%APPDATA%\misterdownloadmanager` profile is shared with the NSIS
  edition. Avoid running both editions at once. Browser repair explicitly chooses
  which installation handles downloads. Registration points into a versioned
  package folder: test repair after Store upgrades and uninstall. Existing profile
  and browser registration exclusions persist on uninstall; disclose this behavior.
- MakeAppx validates the manifest and package structure. It does not prove browser
  integration or Store approval. Before submission, run Windows App Certification
  Kit and test a registered package on a clean Windows 11 account: first launch,
  Chrome/Edge/Firefox handoff, native host cold start, startup enabled/disabled and
  minimized/window modes, Store update, uninstall/reinstall, and download recovery.
- Review the Auralis-specific privacy policy, license notices, optional helper
  downloads (including Deno/media tools), remote pairing and permissions in the
  Store listing and certification notes. Do not claim no data handling or guaranteed
  certification. Store listing screenshots and age-rating answers must describe
  the actual app.

The available GitHub plugin can prepare the repository, but no Partner Center
submission connector was found. Account verification, legal agreements, product
reservation and certification submission require owner access or a separately
configured official submission API. Do not send passwords, client secrets or
access tokens in chat.

References: [Microsoft signing options](https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options),
[manual MSIX packaging](https://learn.microsoft.com/windows/msix/desktop/desktop-to-uwp-manual-conversion),
[scoped virtualization](https://learn.microsoft.com/windows/msix/desktop/flexible-virtualization),
[startup tasks](https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptask).

## Preparation validation (26 November 2026)

- The Store-edition Qt application compiled and linked using Qt 6.11.3 and the
  Windows 11 SDK 10.0.26100.0, including the C++/WinRT startup integration.
- MakeAppx successfully validated and packed the generated manifest, scoped
  exclusions, startup extension and icon assets using a disposable fixture.
  That fixture contains dummy payload files and is not an installable app or a
  Store submission; no sample identity is used for distribution.
- Packaging rejected invalid identity names and output nested inside its input.
- PowerShell scripts parsed successfully; workflow YAML parsed with explicit
  build gating and read-only repository permissions.
- Actual Partner Center identity values are still required. A registered-package
  runtime test and Store certification have not been completed.
