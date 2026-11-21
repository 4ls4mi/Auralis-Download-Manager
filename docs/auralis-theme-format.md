# Editable Auralis themes

In **Settings → Appearance → Color themes**, choose **Export current theme**. Edit the resulting JSON file with a text editor, then choose **Import theme**. The imported theme appears with the other color choices. You can also ask another person or an AI assistant to help edit the file. Save a copy before changing it.

The file contains the currently selected surface material, palette, text settings and separate progress, connection and graph styles. It does not contain executable code, CSS, wallpaper files or download data. The separate preferences backup is not a backup of downloaded files.

- `palette.name` is the name shown in the app; choose a new name to keep a separate copy.
- `palette.accent` and `palette.secondary` are six-digit hexadecimal colors such as `#33aaff`.
- `palette.surface` is either `null` or an array of three RGB values, for example `[245, 250, 255]`. Set `palette.light` to `true` for a light surface and `false` for a dark one so the app uses suitable text colors. A light theme needs an explicit light surface.
- `material` identifies a built-in material. A custom material uses `"material": "custom"` and includes its values in `customMaterial`.
- `settings` contains the selected indicator palettes and shapes, the material for each indicator, text settings, theme tint, interface size, and wallpaper dimming and blur. Export a configuration using the app's controls to see valid values.

Auralis validates imported files and rejects unsupported values. If a file is rejected, check the error and start from a fresh export. Keep theme files to 32 KB or less.
