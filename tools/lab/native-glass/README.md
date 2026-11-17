# Direct2D native material geometry experiment

This standalone Windows x64 experiment tests an alternative to WebGPU using the Windows Direct2D hardware-backed rendering path. Open a Visual Studio x64 developer command prompt at the repository root:

```bat
cl /nologo /EHsc /std:c++17 tools\lab\native-glass\main.cpp /link /subsystem:windows /out:native-glass-lab.exe
native-glass-lab.exe
```

Press 1–6 to switch shapes, L for light/dark, and C to change accent; resize the window to exercise geometry scaling. `native-glass-lab.exe --self-test` creates each geometry and returns a nonzero exit code on failure; the CI job checks this on Windows x64.

This is an isolated geometry and gradient experiment with an opaque background. It does not yet render the real desktop, integrate with Tauri/WebView2, reproduce the approved images, coordinate native clipping/hit testing, show real downloads or verify physical GPU acceleration. A successful self-test is not a visual test. The intended production investigation includes DirectComposition host-backdrop integration, effects and proper composition with the application's existing controls.

## Windows host backdrop experiment

`backdrop.cpp` separately tests a native Windows Composition host-backdrop brush on a Win32 window. It requires Windows 11 build 22000 or later for `DWMWA_USE_HOSTBACKDROPBRUSH`, and uses Windows Composition rather than capturing the screen. It is not yet integrated with WebView2 or the Direct2D surface. Compile on Windows with the x64 Visual Studio tools:

```bat
cl /nologo /EHsc /std:c++20 tools\lab\native-glass\backdrop.cpp /link /subsystem:windows /out:host-backdrop-lab.exe
host-backdrop-lab.exe
```

Visually verify that other windows and the desktop are actually visible through the target, and check resize, interaction, display changes and GPU compatibility. The compilation check alone cannot prove backdrop or Tauri integration works. Windows 10 needs a separately tested fallback.
