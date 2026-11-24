# Compile and stage the native Qt app, engine DLL, browser host and Deno.
param([string]$PrivateFontDirectory, [switch]$BundleReleaseFonts)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$releaseFontKey = $env:AURALIS_RELEASE_FONT_KEY
Remove-Item Env:AURALIS_RELEASE_FONT_KEY -ErrorAction SilentlyContinue
if ($PrivateFontDirectory -and $BundleReleaseFonts) {
    throw 'Choose either private fonts or the release font bundle.'
}

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
$jobName = "run-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$installerKind = 'setup'
$privateFonts = @()
if ($PrivateFontDirectory) {
    if ($env:GITHUB_ACTIONS -eq 'true' -or $env:GITHUB_ENV) {
        throw 'Build the private font installer locally so GitHub Actions cannot upload it.'
    }
    $privateFonts = @(Get-ChildItem -LiteralPath $PrivateFontDirectory -File -Filter '*.font')
    if (!$privateFonts -or ($privateFonts | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
        throw 'The private font directory must contain regular Auralis .font files.'
    }
    $jobName = 'private-' + [guid]::NewGuid().ToString('N')
    $installerKind = 'private-setup'
}
$job = Join-Path $env:AURALIS_QT_WORK $jobName
$stage = Join-Path $job 'payload'
foreach ($path in @($build, $job, $stage)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
if ($env:GITHUB_ENV) { "AURALIS_QT_JOB=$job" >> $env:GITHUB_ENV }
try {
    if ($BundleReleaseFonts) {
        . (Join-Path $PSScriptRoot 'release-fonts.ps1')
        $releaseFonts = Join-Path $stage 'interface-fonts'
        Expand-AuralisReleaseFonts (Join-Path $source 'assets/fonts/auralis-release-fonts.zip.aes') $releaseFonts $releaseFontKey
        Copy-Item -LiteralPath (Join-Path $source 'assets/fonts/SOURCES.md') -Destination $releaseFonts
        if ($env:GITHUB_ENV) { 'AURALIS_QT_RELEASE_FONTS=1' >> $env:GITHUB_ENV }
    }
} finally { $releaseFontKey = $null }

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
    Copy-Item -LiteralPath (Join-Path $builtApp 'auralis-chrome-approval.exe') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $rust 'auralis_engine.dll') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $rust 'misterdownloadmanager-nmhost.exe') -Destination (Join-Path $stage 'auralis-browser-host.exe')
    Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DENO 'deno.exe') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $env:AURALIS_QT_DENO 'deno-LICENSE.md') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $repo 'auralis-extension') -Destination $stage -Recurse
    if ($privateFonts) {
        $destination = Join-Path $stage 'interface-fonts'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $privateFonts.FullName -Destination $destination
    }
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

    # Qt's deployment scanner includes optional Controls styles. The app selects Basic
    # before loading QML, and its explicit style imports also use Basic.
    foreach ($style in @('FluentWinUI3','Fusion','Imagine','Material','Universal','Windows')) {
        $styleModule = Join-Path $stage "qml/QtQuick/Controls/$style"
        if (Test-Path -LiteralPath $styleModule -PathType Container) {
            Remove-Item -LiteralPath $styleModule -Recurse -Force
        }
        Get-ChildItem -LiteralPath $stage -File -Filter "Qt6QuickControls2$style*.dll" | Remove-Item -Force
    }

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

    foreach ($file in @('auralis-download-manager.exe','auralis-chrome-approval.exe','auralis_engine.dll','auralis-browser-host.exe','deno.exe',
        'dxcompiler.dll','dxil.dll','directx-shader-compiler/LICENCE-MIT.txt','directx-shader-compiler/LICENSE-LLVM.txt',
        'directx-shader-compiler/LICENSE-MS.txt',
        'Qt6Core.dll','Qt6Quick3D.dll','Qt6Multimedia.dll','platforms/qwindows.dll','qml/QtQuick3D/qmldir',
        'Qt6WebSockets.dll','tls/qschannelbackend.dll',
        'qml/QtQuick/Controls/qmldir','qml/QtQuick/Controls/Basic/qmldir','Qt6QuickControls2Basic.dll',
        'qml/QtMultimedia/qmldir','multimedia/ffmpegmediaplugin.dll',
        'msvcp140.dll','vcruntime140.dll','auralis-extension/manifest.json',$shortcutIcon)) {
        if (!(Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) { throw "Missing deployed package file: $file" }
    }
    Get-ChildItem -LiteralPath $stage -Recurse -File -Filter '*.pdb' | Remove-Item -Force

    $installed = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)
    $uninstall = Join-Path $job 'uninstall-files.nsh'
    $lines = foreach ($file in $installed) {
        $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
        if ($relative -match '[\r\n"$]') { throw "Cannot encode installer filename: $relative" }
        '    ${If} ${FileExists} "$INSTDIR\' + $relative + '"'
        '        ClearErrors'
        '        Delete "$INSTDIR\' + $relative + '"'
        '        ${If} ${Errors}'
        '            StrCpy $UninstallFailed 1'
        '        ${EndIf}'
        '    ${EndIf}'
    }
    $lines += @(Get-ChildItem -LiteralPath $stage -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { '    RMDir "$INSTDIR\' + [IO.Path]::GetRelativePath($stage, $_.FullName) + '"' })
    $lines | Set-Content -LiteralPath $uninstall -Encoding utf8

    # MakeNSIS is 32-bit. Its attempt to open System32 checkout paths is redirected by Windows.
    $icon = Join-Path $job 'auralis.ico'
    $installerScript = Join-Path $job 'installer.nsi'
    Copy-Item -LiteralPath $brandIcon -Destination $icon
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer.nsi') -Destination $installerScript
    $installer = Join-Path $job "Auralis.Download.Manager_$($version)_x64-$installerKind.exe"
    Push-Location $job
    try {
        Invoke-Checked $env:AURALIS_QT_NSIS @('/V3',"/DVERSION=$version","/DOUTPUT=$installer","/DPAYLOAD=$stage",
            "/DUNINSTALL_FILES=$uninstall","/DICON=$icon","/DSHORTCUT_ICON=$shortcutIcon",$installerScript)
    } finally { Pop-Location }
    if (!(Test-Path $installer) -or (Get-Item $installer).Length -gt 268435456) {
        throw 'The finished installer is missing or exceeds the size limit for automatic updates.'
    }
    if ($env:GITHUB_ENV) {
        "AURALIS_QT_INSTALLER=$installer" >> $env:GITHUB_ENV
        "AURALIS_QT_VERSION=$version" >> $env:GITHUB_ENV
    } else {
        Write-Output $installer
    }
} finally { Pop-Location }
