# Mister Hybrid V2 — Plexo-inspired glass theme and wallpapers

**Development branch:** `feature/plexo-theme-wallpaper`

This is a redesign of the existing **Rust/egui** desktop app, not an Electron wrapper. Mister's download engine, pause/resume/cancel, categories, scheduler, torrent processing, and browser integration are retained.

## Visual baseline

- Built-in **Plexo Dark Glass** theme, with charcoal (#0B0F11 / #161D20), teal accents, amber warnings, rounded cards, fine borders and minimalist monochrome Metro icons.
- New theme available under **View → Theme → Plexo Dark Glass**. One-time migration selects it for a previously unmodified Classic theme; it can be changed back at any time.
- Main download list receives dark glass styling with optional wallpaper transparency and small colored status capsules.
- Main footer shows measured total download speed history.
- Download progress window uses live-speed graph, 4 transfer-stat cards, byte-range grid, segment-color legend, and the regular connection detail table. These are derived from live engine data.

## Wallpaper controls

Open **View → Appearance & Wallpapers…**, or use the new **Appearance…** button at the bottom of **Options**.

Choose a local PNG/JPG/WebP for the main window. For download progress windows select **Use the same wallpaper as the main window**, or uncheck it to choose a separate file. Empty paths disable the relevant image.

The independent controls are:

- **Wallpaper darkness** (20–95%) — light images are dimmed more aggressively so white foreground controls remain legible.
- **Wallpaper blur** (0–28 px) — blurred once on image load, never in every frame.
- **Glass-panel opacity** (58–98%) — protective translucent surfaces; currently applied to the list, footer, previews and the dedicated appearance components.
- **Remove** and **Reset wallpaper settings**.

Settings and wallpaper paths are serialized with the rest of Mister's settings.

### Readability

Custom images are brightness-sampled and processed into a cached, size-limited texture (maximum 2048 × 1280). Text drawn directly on an image selects light or dark ink with a contrasting outline and matching panel. Existing controls remain on dark, contrast-protective surfaces regardless of the wallpaper. This deliberately favors readability over unconstrained transparency.

The image file is stored by path, **not copied into the download files**. If the user moves or deletes it, the theme remains usable and the picker shows that the image is unavailable. No file is uploaded to a server.

## Implementation files

- `crates/app/assets/themes/plexo.toml` — full-color palette, modern corners and Metro icons
- `crates/app/src/palette.rs` — built-in-theme registration
- `crates/app/src/settings.rs` — persisted wallpaper controls
- `crates/app/src/wallpaper.rs` — local image loader, GPU texture cache, preview and contrast policy
- `crates/app/src/appearance.rs` — live Appearance settings UI
- `crates/app/src/options.rs` — entry from Options
- `crates/app/src/app.rs` — main background, status graph, image picks and appearance editor
- `crates/app/src/list.rs` — semi-transparent list and status capsules
- `crates/app/src/progress.rs` — progress wallpaper and metric panel integration
- `crates/app/src/hybrid_progress.rs` — palette-following graph/chunks/metrics
- `.github/workflows/build-v2-windows.yml` — Windows x64 build

## Network chunk colors

The 192 visual squares sample real downloaded byte ranges. **Their colors distinguish download segments, not network adapters**. Mister's `Snapshot` does not provide adapter attribution; adding true Ethernet/Wi-Fi ownership would require separate engine instrumentation.

## Windows build

See the **Mister Hybrid V2 Windows** workflow under Actions on the fork. It runs Rust formatting, app tests, an x64 Windows build, smoke tests and creates a downloadable GitHub artifact containing the installer and portable ZIP. This branch should not be merged until the build and Windows visual QA pass.

## Limitations of this iteration

The main window retains Mister's existing native table/sidebar architecture; it is restyled rather than replaced with a completely new React layout. This preserves full functionality, keyboard navigation and screen-reader access. Some secondary dialogs still use their inherited native layouts, but they share the new palette and icon set.
