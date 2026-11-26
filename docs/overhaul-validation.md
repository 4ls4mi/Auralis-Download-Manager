# Settings and indicator overhaul: validation

Checked locally on 26 November 2026. These changes are unreleased.

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

## Remaining limits

- The integrated smoke test exits at local-channel creation with
  `QLocalServerPrivate::addListener: Access is denied.` It does not reach the
  application UI or transfer fixture. Startup logging now identifies this
  failure. Full application runtime validation is still required.
- The local NSIS compiler cannot launch: Windows reports Illegal System DLL
  Relocation. Installer compilation and installation remain unverified.
- There are 87 locale choices, including English (UK), with English fallbacks;
  these are not 87 fully translated languages. The installer generator finds
  official NSIS packs for 56 of those locales. See localization-coverage.md.
- No trusted signing identity is configured. Free SignPath signing requires
  project approval; no application has been submitted. See windows-signing.md.
- No installer or GitHub release has been published for these edits.

Build and temporary files were directed to
`D:\AuralisRunner\target\auralis-overhaul-validation` after C: ran out of space.
