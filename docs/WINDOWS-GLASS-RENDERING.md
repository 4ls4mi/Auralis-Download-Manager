# Material rendering rebuild

The former material presets and their overlapping WebGL highlight, SVG surface, native region and per-material CSS effects have been removed from the active interface. The neutral interface keeps theme accents and optional Windows backdrop blur. Existing progress/connection shape and gradient choices remain independent. Saved old material preferences are retained but have no visual effect.

`tools/lab/webgpu-materials/` is a standalone WebGPU geometry and shader experiment for six reference styles. Serve the directory over localhost and open it in a WebGPU-capable browser to try it. It draws a synthetic background, not the desktop. It has not been integrated into the application and is not a finished material implementation. Device, shader and browser compatibility, appearance, performance, scaling, and screenshots must be checked on Windows x64.

## Architecture to investigate and build

* A single GPU composition pipeline should own each window's background, silhouette, bevels and material-specific surface geometry. The same geometry must govern clipping and interaction, so an extra rectangular layer does not extend over rounded or faceted edges. Keep controls and text readable above it. Derive tint from the selected accent once.
* Build Water Bubble as a vertical slice: deformable outline and smooth specular edges; then Ice Edge, Smoked Crystal, Frosted Layers, Aero Gloss and Prismatic Glass each need their own authored geometry and shader parameters. The generated reference images are visual targets, not implementation assets.
* Keep progress shapes and colors independently selectable, and connect the existing engine-driven indicators and transfer graph. A shape that follows a material can be a preset without forcing it.
* Prototype Windows Composition host-backdrop and Direct2D/Direct3D integration with Tauri's WebView2 window before committing to a production compositor. A compositor backdrop brush and a CSS backdrop filter are not proof that arbitrary desktop pixels are available to a shader. Direct2D exposes displacement effects, but feeding a real desktop backdrop into them alongside WebView2 needs a Windows prototype. Do not silently capture the screen to fake refraction.
* If desktop capture is needed, obtain user consent and investigate capture exclusion, recursion, protected content, mixed DPI, monitor changes, device loss and resource cleanup. Provide a clear fallback. Test both Windows 10 and 11 x64 where supported.
* Verify all windows, both light and dark modes, accent choices, resizing, text contrast, hit testing, GPU fallbacks and real download behavior on Windows. Compare screenshots directly with the references; a successful installer or shader compilation does not establish visual fidelity.

## References

* [Windows Composition host backdrop brush](https://learn.microsoft.com/en-us/uwp/api/windows.ui.composition.compositor.createhostbackdropbrush)
* [Direct2D displacement map effect](https://learn.microsoft.com/en-us/windows/win32/direct2d/displacement-map)
* [Windows screen capture](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/screen-capture)
* [Desktop window composition target](https://learn.microsoft.com/en-us/windows/win32/api/windows.ui.composition.interop/nf-windows-ui-composition-interop-icompositordesktopinterop-createdesktopwindowtarget)
