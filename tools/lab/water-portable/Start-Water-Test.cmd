@echo off
setlocal
set "MDM_DATA_DIR=%TEMP%\MisterHybridGlass-WaterTest"
set "WEBVIEW2_USER_DATA_FOLDER=%TEMP%\MisterHybridGlass-WaterTest-WebView"
set "MHG_EXPERIMENTAL_WATER=1"
set "MHG_EXPERIMENTAL_RENDERER=d3d11"
set "MHG_EXPERIMENTAL_HOSTBACKDROP=1"
start "" "%~dp0mister-hybrid-glass.exe"
