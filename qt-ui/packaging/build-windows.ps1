# Compile and stage the native Qt app, engine DLL, browser host and Deno.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-Checked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE." }
}

$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$source = Join-Path $repo 'qt-ui'
$version = [regex]::Match((Get-Content (Join-Path $source 'CMakeLists.txt') -Raw), 'project\s*\(\s*AuralisQt\s+VERSION\s+(\d+\.\d+\.\d+)\s').Groups[1].Value
if (!$version) { throw 'AuralisQt project version was not found.' }
$build = Join-Path $env:AURALIS_QT_WORK 'cmake'
$builtApp = Join-Path $build 'application'
$job = Join-Path $env:AURALIS_QT_WORK "run-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$stage = Join-Path $job 'payload'
foreach ($path in @($build, $job, $stage)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
"AURALIS_QT_JOB=$job" >> $env:GITHUB_ENV

Push-Location $repo
try {
    $configure = @('-S',$source,'-B',$build,'-G','Visual Studio 17 2022','-A','x64',
        "-DCMAKE_PREFIX_PATH:PATH=$env:AURALIS_QT_ROOT","-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE:PATH=$builtApp")
    $cache = Join-Path $build 'CMakeCache.txt'
    if (Test-Path -LiteralPath $cache) {
        $cachedSource = Select-String -LiteralPath $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$' -List |
            ForEach-Object { $_.Matches[0].Groups[1].Value }
        if ($cachedSource -ine $source.Replace('\', '/')) {
            Write-Host 'Refreshing the CMake configuration for the current checkout.'
            $configure += '--fresh'
        }
    }
    Invoke-Checked 'cmake' $configure

    $env:AURALIS_ENGINE_REV = (git log -1 '--format=%h' '--' crates i18n assets Cargo.toml Cargo.lock .cargo rust-toolchain.toml).Trim()
    if ($LASTEXITCODE -ne 0 -or !$env:AURALIS_ENGINE_REV) { throw 'Could not determine the backend revision.' }
    Invoke-Checked 'cargo' @('build','--locked','--release','--target','x86_64-pc-windows-msvc','-p','auralis-qt-engine','-p','mdm-nmhost')
    $rust = Join-Path $env:CARGO_TARGET_DIR 'x86_64-pc-windows-msvc/release'

    Invoke-Checked 'cmake' @('--build',$build,'--config','Release','--target','auralis-download-manager')
    Copy-Item -LiteralPath (Join-Path $builtApp 'auralis-download-manager.exe') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $rust 'auralis_engine.dll') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $rust 'misterdownloadmanager-nmhost.exe') -Destination (Join-Path $stage 'auralis-browser-host.exe')
    Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DENO 'deno.exe') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DENO 'deno-LICENSE.md') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $repo 'auralis-extension') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY.txt') -Destination $stage
    $brandIcon = Join-Path $source 'assets/auralis.ico'
    $iconHash = (Get-FileHash -LiteralPath $brandIcon -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
    $shortcutIcon = "auralis-taskbar-$iconHash.ico"
    Copy-Item -LiteralPath $brandIcon -Destination (Join-Path $stage $shortcutIcon)

    $exe = Join-Path $stage 'auralis-download-manager.exe'
    Invoke-Checked (Join-Path $env:AURALIS_QT_ROOT 'bin/windeployqt.exe') @('--release','--no-translations',
        '--no-compiler-runtime','--no-system-dxc-compiler','--include-plugins','qsvg,qsvgicon,ffmpegmediaplugin',
        '--qmldir',$source,'--dir',$stage,$exe)
    # Use the same app-local x64 DXC pair on every installation.
    foreach ($file in @('dxcompiler.dll','dxil.dll')) {
        Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DXC $file) -Destination $stage
    }
    $dxcLicenses = Join-Path $stage 'directx-shader-compiler'
    New-Item -ItemType Directory -Force -Path $dxcLicenses | Out-Null
    foreach ($file in @('LICENCE-MIT.txt','LICENSE-LLVM.txt','LICENSE-MS.txt')) {
        Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DXC $file) -Destination $dxcLicenses
    }

    # Bundle the x64 C++ runtime app-local so setup stays per-user.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -latest -property installationPath
    if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio 2022 with x64 C++ tools is required.' }
    $redists = Get-ChildItem -LiteralPath (Join-Path $vs 'VC/Redist/MSVC') -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } | Sort-Object { [version]$_.Name } -Descending
    $crt = $redists | ForEach-Object {
        Get-ChildItem -Path (Join-Path $_.FullName 'x64/Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue
    } | Select-Object -First 1
    if (!$crt) { throw 'The x64 MSVC redistributable files were not found.' }
    Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $stage

    foreach ($file in @('auralis-download-manager.exe','auralis_engine.dll','auralis-browser-host.exe','deno.exe',
        'dxcompiler.dll','dxil.dll','directx-shader-compiler/LICENCE-MIT.txt','directx-shader-compiler/LICENSE-LLVM.txt',
        'directx-shader-compiler/LICENSE-MS.txt',
        'Qt6Core.dll','Qt6Quick3D.dll','Qt6Multimedia.dll','platforms/qwindows.dll','qml/QtQuick3D/qmldir',
        'Qt6WebSockets.dll','tls/qschannelbackend.dll',
        'qml/QtQuick/Controls/qmldir','qml/QtMultimedia/qmldir','multimedia/ffmpegmediaplugin.dll',
        'msvcp140.dll','vcruntime140.dll','auralis-extension/manifest.json',$shortcutIcon)) {
        if (!(Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) { throw "Missing deployed package file: $file" }
    }
    Get-ChildItem -LiteralPath $stage -Recurse -File -Filter '*.pdb' | Remove-Item -Force

    $installed = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)
    $uninstall = Join-Path $job 'uninstall-files.nsh'
    $lines = foreach ($file in $installed) {
        $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
        if ($relative -match '[\r\n"$]') { throw "Cannot encode installer filename: $relative" }
        '    Delete "$INSTDIR\' + $relative + '"'
    }
    $lines += @(Get-ChildItem -LiteralPath $stage -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { '    RMDir "$INSTDIR\' + [IO.Path]::GetRelativePath($stage, $_.FullName) + '"' })
    $lines | Set-Content -LiteralPath $uninstall -Encoding utf8

    # MakeNSIS is 32-bit. Its attempt to open System32 checkout paths is redirected by Windows.
    $icon = Join-Path $job 'auralis.ico'
    $installerScript = Join-Path $job 'installer.nsi'
    Copy-Item -LiteralPath $brandIcon -Destination $icon
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer.nsi') -Destination $installerScript
    $installer = Join-Path $job "Auralis.Download.Manager_$($version)_x64-setup.exe"
    Push-Location $job
    try {
        Invoke-Checked $env:AURALIS_QT_NSIS @('/V3',"/DVERSION=$version","/DOUTPUT=$installer","/DPAYLOAD=$stage",
            "/DUNINSTALL_FILES=$uninstall","/DICON=$icon","/DSHORTCUT_ICON=$shortcutIcon",$installerScript)
    } finally { Pop-Location }
    if (!(Test-Path $installer) -or (Get-Item $installer).Length -gt 268435456) {
        throw 'The finished installer is missing or exceeds the size limit for automatic updates.'
    }
    "AURALIS_QT_INSTALLER=$installer" >> $env:GITHUB_ENV
    "AURALIS_QT_VERSION=$version" >> $env:GITHUB_ENV
} finally { Pop-Location }
