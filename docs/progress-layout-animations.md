# Progress layouts and their animations

The six approved transparent designs are Liquid silk, Elastic gel, Photon streams,
Crystal shimmer, Capillary current and Vortex glass. Each provides its three
previewed motion modes. The older Classic, Status track, Pill segments, Thin line
and Striped fill layouts also have three animations of their own. Every layout
has a No motion option. Animation choices are filtered by the selected layout;
the same generic menu is no longer applied to every fill.

`ProgressStyles.js` owns the layout/animation catalog and migration rules.
`WindowAppearance.qml` stores the last animation per layout, includes that map
in backups and exported themes, and restores an appropriate choice when changing
layouts or importing old settings. Connection and graph animation settings remain
independent of the fill catalog.

The host still owns the material track. `ArtisticProgress.qml` paints only artwork,
clips it to the frame shape and the actual byte boundary, and applies lighting
with source-atop composition so gaps stay transparent. Its clock runs at about
30 frames per second only while visible and transferring; reduced motion,
completion, pause and No motion stop the clock. The old segmented overlay uses
the actual partial segment endpoint, including spacing, rather than assuming
the painted width equals the byte percentage times the full track width.

Classic retains its native glass/water/jelly rendering. Status track has breathing,
leading signal and scan effects; Pill segments has cascade, wave and compression;
Thin line has comet, packets and breathing; Striped fill has forward, reverse and
pulsing stripes. These effects are confined to their layout's fill mask.

Validation includes Node catalog, migration and clipping checks; Qt rendering at
14/32 pixels with round/square/prism contours; empty/unfilled transparency checks;
live frame comparisons for all 18 new animation modes; and host integration,
per-layout memory and backup round-trip checks. A packaged Windows build and
release are separate steps.
