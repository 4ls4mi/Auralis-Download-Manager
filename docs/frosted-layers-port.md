# Frosted Layers 3.5.1 port notes

## Reference and scope
The supplied `resources.rar` matches the Water Bubble Frosted Layers 3.5.1 reference source. Its pane renderer uses WebGL straight-alpha composition, five offset panes and a front pane; it does not capture the desktop or use Windows acrylic. The reference design uses a 742 × 522 logical canvas. Its shader is the source of truth for the pane geometry and lighting. Existing Auralis controls, window types and engine data remain the source of truth for functionality.

## Changes currently made
- Added `frostedLayersShader.ts` from the reference pane shader and `FrostedLayers.tsx`, which draws it behind existing content. Drawing is resized with the canvas, uses device pixel ratios up to 2, and supplies a static fallback when WebGL is unavailable. Context restoration requests a new renderer.
- Registered `frosted-water-351` as a distinct material and placed the renderer in the shared `CrystalWindow`, so window types using that wrapper share it.
- For this material only, suppressed the old `.cg-content` surface, its pseudo-element overlays, backdrop filter, and Windows acrylic effect. These layers otherwise stack on top of the reference artwork. Other materials retain their prior behavior.
- The native region is removed for this material, allowing the transparent shader edges to define the visible outline. The existing custom window controls remain responsible for actions.
- Added a content inset and subdued secondary glass styles. These are adaptation decisions rather than reference geometry and must be checked at different Auralis window sizes; the current shader stretches its reference artboard to the window rather than uniformly scaling it.

## Still required
- The shader-only browser check is not a full Auralis or Windows validation. Check all main, settings, add, progress, completion, confirmation and other windows at multiple sizes, DPI scales and desktop backgrounds; check hit testing, shadows, visibility, readability, resizing and contrast. Adjust the layout without removing controls.
- Port the approved ribbon and clear/frosted capsule designs; keep progress sourced from real engine data, provide a usable GPU fallback, and avoid a separate WebGL context for every download row.
- Implement and independently preview the requested progress, connection and graph shapes, colors and track/backdrop materials. The 14 later sculpted track shapes were supplied as images, not executable source; their geometry needs to be built and visually checked. Preserve worker telemetry, per-connection progress, loss states and actual graph data.
- Do not claim the reference is pixel-matched, or ship a release, until the integrated Windows appearance and behavior have been checked.

## Applying this approach to another material
Inventory the existing material's CSS selectors, native window region and system backdrop first. Add a material-specific renderer and remove only the overlapping layers for that material; keep other materials untouched. Test the resulting single compositing stack, desktop alpha and window interactions against its own visual reference. Keep a record of every removed or bypassed layer and the fallback.

## Ribbon progress, current implementation
- `frostedRibbonShader.ts` retains the reference ribbon and clear capsule calculations, mapped to the bar's own rectangle. `FrostedRibbon.tsx` shares one WebGL context among bars and copies the rendered result into each visible 2D canvas. The shader receives the existing total-file percentage; a CSS gradient remains available if WebGL cannot initialize.
- A new independent progress-fill selection enables the approved ribbon with the rounded shape. Its original ice-blue colors are baked into the reference shader. It does not yet support the independently chosen palette, the other shapes, connection blocks, an animated phase, indeterminate progress, or selectable alternative tracks. These must not be presented as complete.
- Browser checks rendered 0%, 82%, and 100% and confirmed the output changes. This is not a Windows application test. The first browser main-window check identified table clipping in the inset shell, so scoped table sizing and empty-state spacing were adjusted; smaller sizes and other windows still need checking.
- Browser check at 1100 × 700 confirmed the scoped grid change removes measured horizontal table overflow. At 600 × 420 the available area remains very tight and the list needs scrolling; further layout work and Windows verification are required. Browser screenshots use mocked backend data and do not verify Tauri window behavior.

## Foreground contrast adaptation
- For Frosted Layers only, dark and light modes now select separate ink, secondary text and field colors. Text-bearing panels and title/menu surfaces receive a stable dark or light translucent base, so text does not depend entirely on whatever happens to be behind the transparent window. Colored action icons remain colored. The pane shader is not altered. The panel interiors are more opaque, while the surrounding pane stack stays visible.
- The shader has no access to actual desktop pixels. Semantic dark/light surfaces are used instead of claiming to sample the desktop. Contrast and the balance between glass visibility and readability still require Windows testing across modes and backgrounds.
- Added an independent progress-track finish selector (default, clear, frosted, recessed), tint selector and empty-track preview. The ice ribbon shader changes the unfilled track without changing the filled ribbon. These are initial options; the referenced sculpted designs, their accuracy, and separate graph/connection backdrops remain unfinished.

## Readability revision
The user rejected the opaque panel backgrounds because they broke the continuous glass design. They were removed. Instead, the pane shader now darkens the whole glass in dark mode while preserving alpha and pane geometry; light mode retains the supplied shader colors. Foreground text colors and restrained shadows differ by mode, and action icons retain their own colors. Small text and translucent fields need further checks against real desktop backgrounds: the shader cannot sample the desktop, so this is not automatic pixel-based contrast detection.

## User correction: one glass appearance
The user requested the original glass color back and no separate light/dark versions for non-solid material designs. The dark-mode shader tint was removed, so Frosted Layers uses the supplied pane colors again. For desktop and wallpaper backgrounds, the interface ignores the light/dark solid-color preference; solid backgrounds retain that preference, with Frosted Layers itself kept fixed. The existing material-specific foreground contrast treatment still needs validation on real Windows backgrounds.

## Small-window scaling check
At 600 × 420, the Frosted Layers main window now keeps the sidebar vertical and scrollable, uses a compact list header and restores the narrow row layout. An empty-list browser check shows its add button within the list area. The renderer still stretches its reference artboard to fit the window, and responsive behavior for populated lists, dialogs, settings, DPI changes and actual Windows desktop composition has not been verified. The screenshot is a browser preview with mocked backend data.

## Experimental sculpted indicator geometry
The 14 image-reference shapes now have initial SVG centerline geometries in `SculptedTrack.tsx`, selectable independently for total progress, connection indicators and the graph backdrop. Progress follows each shape's SVG path length; separate glass links fill in sequence. Connection elements continue using worker range percentages and the existing loss/paused state; the graph data stays on its ordinary axes, with the selected geometry used only behind it. The rendering uses SVG gradients and strokes; it is not yet a faithful recreation of the reference ribbon, tapered/hourglass widths, reflections or lighting. The selected Frosted Ribbon shader and track-finish settings do not yet apply to these SVG shapes. Small connection blocks may not retain enough detail. Do not describe these as visually finished or release them without reviewing the image comparisons, telemetry and layouts on Windows.

## Sculpted track refinement
Added layered glass highlights and masked fold strokes, variable-width outlines for hourglass and tapered wave, plus the selected progress-track finish and tint on sculpted progress bars. These are hand-drawn SVG effects, not a port of the reference ribbon shader; appearance, scale at connection-block sizes, graph backdrop behavior and visual matching remain unverified on Windows. Browser checks rendered all 14 and confirmed sample 42% total/25% connection data still reach their visual masks; the existing suite passed.

## Design direction and small connection indicators
The user clarified that the sculpted reference images are inspiration and do not need exact reproduction. The indicator renderer may use original artwork while preserving clear real progress and application behavior. A browser preview of the actual progress-window layout showed that full sculpted paths became too thin in 32 small slots; sculpted connection slots now retain a distinct block, a fill proportional to the worker's assigned range, and a red lost/paused backdrop, with the selected shape overlaid. This still needs review with real download telemetry and Windows scaling.

## Shaped connection track correction
The user rejected rectangular connection backdrops. Sculpted connection slots, including unused ones, now draw the selected shape as their track. A lost connection uses a red shaped track with its last known colored progress over it; a paused download uses an all-red shaped track with no progress overlay. Active filled shapes have a moving masked reflection that respects reduced-motion preferences. The reference ice-ribbon shader now receives the selected indicator palette while retaining its fold lighting. Browser checks exercised receiving, lost and paused cases and compared two ribbon palettes. The effect is still under visual and Windows review.

## Indicator settings and readability
The appearance page now presents one indicator or backdrop preview at a time rather than compressing all cards into a tiny font. Settings and their navigation can scroll independently, and the window-fit measurement no longer shrinks the whole UI to fit those scrollable panels. The preview follows the selected shape and palette; rounded bars offer the separate reference ribbon fill, while sculpted tracks use their own glass rendering. Browser screenshots use simulated data and do not establish actual Windows scaling or functionality.

## Readability across windows
The user requested every text and icon to be readable. Frosted Layers foreground rules now cover the shared window's text, controls, inputs, placeholders and icon outlines; settings navigation icons retain distinct bright colors. Disabled buttons are less faded while remaining disabled. Browser previews were inspected for the main window, progress window and indicator settings only; the remaining dialogs, true desktop backgrounds and DPI combinations have not been visually validated, so this is not a verified guarantee for every window.

## Button highlight correction
The user noted that the readability pass had muted button colors. Frosted Layers now restores vivid icon colors, selected states, full-button hover fills and the distinct title-button hover colors while retaining contrasting text. A browser check measured the Add button changing from transparent to green on hover; this remains subject to Windows visual review.

## Short progress-window overlap
A simulated 720 × 420 progress window showed the indicator grid and graph running behind the bottom buttons. For Frosted Layers at short heights, metadata and tabs now use compact spacing, the connection grid shares the available indicator height, and the graph remains clipped within its own panel. Browser geometry checks at 720 × 420 and 1100 × 700 confirmed all 32 slots stayed within the connection panel and the indicator row ended above the buttons. This is not a substitute for testing Windows DPI scaling and real downloads.

## Input field backdrop
The user clarified that the opaque dark input fields, rather than the layered window background, felt out of place. Frosted Layers inputs, text areas and selects now use translucent, softly edged glass with legible light text and a distinct focus outline. Native select option lists keep an opaque backing for readability. Browser previews of file-info and completion windows were checked; real Windows backdrops and contrast still require validation.

## Sculpted indicator depth pass
The user reported that shaped indicators looked flat. Added a shadow, layered glass rim and narrow upper and lower reflections; full-sized indicators also receive a soft glow, while compact connection indicators avoid the full-size blur treatment. Browser checks retained the receiving, lost and paused connection semantics and the 32-slot display. The new shading is still a work in progress and needs Windows and performance review, especially with many downloads.

## Transparent background and edge resize follow-up
The user reported a rectangular tinted area outside the panes and resize grips far away from the visible glass. Wallpaper and solid background elements are now masked by the rendered pane alpha, and newly created windows explicitly request a transparent native background. Frosted Layers hit-tests its resize directions against the rendered alpha contour, instead of the invisible rectangular WebView boundary. Browser tests check transparent corners and dispatch a resize from a visible edge; actual Windows compositing and native resize dragging still require verification. Main-list progress and connection indicators also received more space in populated rows.
