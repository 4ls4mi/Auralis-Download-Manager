# Direct2D native material geometry experiment

This standalone Windows x64 experiment tests an alternative to WebGPU using the Windows Direct2D hardware-backed rendering path. Open a Visual Studio x64 developer command prompt at the repository root:

```bat
cl /nologo /EHsc /std:c++17 tools\lab\native-glass\main.cpp /link /subsystem:windows /out:native-glass-lab.exe
native-glass-lab.exe
```

Press 1–6 to switch shapes, L for light/dark, and C to change accent; resize the window to exercise geometry scaling. `native-glass-lab.exe --self-test` creates each geometry and returns a nonzero exit code on failure; the CI job checks this on Windows x64.

This is an isolated geometry and gradient experiment with an opaque background. It does not yet render the real desktop, integrate with Tauri/WebView2, reproduce the approved images, coordinate native clipping/hit testing, show real downloads or verify physical GPU acceleration. A successful self-test is not a visual test. The intended production investigation includes DirectComposition host-backdrop integration, effects and proper composition with the application's existing controls.
