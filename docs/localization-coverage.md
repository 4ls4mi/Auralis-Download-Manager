# Qt and installer localization coverage

The language table currently exposes 87 locale choices, including English (UK).
This is a locale count, not a claim of 87 distinct languages or fully translated
Qt interfaces.

`tools/i18n/generate-qt-catalogs.py` reuses existing translated TSV messages and
dedicated Qt translations. New or unmatched Qt strings remain unfinished and
fall back to English. Each build writes `translations/coverage.json`, containing
translated and total message counts per locale. Do not mark English fallbacks
as completed translations.

`tools/installer/generate-nsis-languages.py` retains official NSIS translations
where available and provides an English fallback otherwise. Its `coverage.json`
identifies locales without an official NSIS pack. A language selector entry does
not imply that every custom installer page has been translated.

Before describing any locale as complete, translate and review the missing Qt
messages and custom installer labels, then verify text clipping, fonts and
right-to-left layout in that locale. Generated TS, QM and NSIS language resources
belong in the build directory, not in source control.
