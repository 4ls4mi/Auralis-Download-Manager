# Settings and indicator overhaul: validation

Checked locally and on the self-hosted Windows runner on 26 November 2026.
Release candidate: 0.3.100; verified source commit: de8e51e1252d637859e079c0259f9345ee4821ea.

Implemented changes include the additional graph materials and progress layouts,
named progress motion effects, shape/lighting integration, category-based Save to
editing, a separate File types page, typed connection choices and port limits,
installer startup options, and bundled animated first-run illustrations.

## Passed

- Windows Qt Release executable build with Qt 6.11.3 and MSVC 2022, including
  the final graph changes and startup diagnostics.
- Rust engine DLL build with `--no-default-features` for local validation.
  This does not verify the release browser-connection feature configuration.
- Rust app and test-target compile checks with `--no-default-features`.
- 20 JavaScript material-rendering and extension-boundary regression tests.
- 36 Qt rendering cases: 12 creative layouts across three frame shapes.
- Rust category-folder preference serialization and language-catalog checks.
- All 87 Qt locale resources compiled. Both locale generators ran successfully.
- Packaging PowerShell and Python generator syntax checks.
- Self-hosted Windows release build with the normal browser-connection feature,
  NSIS installer compilation, installation, and update/relaunch verification.
- All 10 release-artifact verification tests on Python 3.10 after replacing the
  Python 3.11-only hashing API with equivalent streaming SHA-256.

Runner verification: https://github.com/4ls4mi/Auralis-Download-Manager/actions/runs/45796385698

## Remaining limits

- The integrated smoke test exits at local-channel creation with
  `QLocalServerPrivate::addListener: Access is denied.` It does not reach the
  application UI or transfer fixture. Startup logging now identifies this
  failure. The self-hosted runner subsequently passed installed runtime and
  update/relaunch verification outside this restricted execution environment.
- The local NSIS compiler cannot launch: Windows reports Illegal System DLL
  Relocation. The same compiler launches and builds the installer successfully
  in the normal self-hosted runner.
- There are 87 locale choices, including English (UK), with English fallbacks;
  these are not 87 fully translated languages. The installer generator finds
  official NSIS packs for 56 of those locales. See localization-coverage.md.
- No trusted signing identity is configured. Free SignPath signing requires
  project approval. The application was submitted on 26 November 2026 and the
  provider displayed its submission confirmation. Approval is pending.
- Full optional Rust regression suite was not requested for this runner build;
  the targeted checks above passed.

Build and temporary files were directed to
`D:\AuralisRunner\target\auralis-overhaul-validation` after C: ran out of space.
