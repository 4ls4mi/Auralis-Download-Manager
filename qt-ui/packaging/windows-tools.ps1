# Provision a short, persistent toolchain on the dedicated Windows runner.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-Checked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE." }
}

function Receive-Pinned([string]$Url, [string]$Destination, [string]$Sha256) {
    if ((Test-Path $Destination) -and (Get-FileHash $Destination -Algorithm SHA256).Hash -ieq $Sha256) { return }
    $partial = "$Destination.part"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $partial
        if ((Get-FileHash $partial -Algorithm SHA256).Hash -ine $Sha256) { throw "Invalid download digest: $Url" }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    } finally {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}

$volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending)
$system = $volumes | Where-Object DeviceID -eq $env:SystemDrive | Select-Object -First 1
$minimumAlternateSpace = 20 * 1024 * 1024 * 1024
$minimumSystemSpace = 10 * 1024 * 1024 * 1024
$alternate = $volumes | Where-Object { $_.DeviceID -ne $env:SystemDrive -and $_.FreeSpace -ge $minimumAlternateSpace } | Select-Object -First 1
$runnerRoot = Join-Path $env:LOCALAPPDATA 'AuralisRunner'
if ($system -and $system.FreeSpace -lt $minimumSystemSpace -and $alternate) {
    $runnerRoot = Join-Path ($alternate.DeviceID + '\') 'AuralisRunner'
}
$targetDir = Join-Path $runnerRoot 'target'
$qtCache = Join-Path $runnerRoot 'qt-cache'
$temp = Join-Path $runnerRoot 'temp'
$sharedCache = Join-Path $env:RUNNER_WORKSPACE 'auralis-cache'
New-Item -ItemType Directory -Force -Path $targetDir, $qtCache, $temp, $sharedCache | Out-Null
$env:TEMP = $temp
$env:TMP = $temp
$env:CARGO_HOME = Join-Path $sharedCache 'cargo'
$env:RUSTUP_HOME = Join-Path $sharedCache 'rustup'

$rustBin = Join-Path $env:CARGO_HOME 'bin'
if (!(Test-Path (Join-Path $rustBin 'rustup.exe'))) {
    $rustupInstaller = Join-Path $sharedCache 'rustup-init.exe'
    Receive-Pinned 'https://static.rust-lang.org/rustup/archive/1.29.3/x86_64-pc-windows-msvc/rustup-init.exe' $rustupInstaller '38027d51d69a5d05493627a0634dbea52d6cd793c8f072d2373d3f4163eec7db'
    Invoke-Checked $rustupInstaller @('-y', '--profile', 'minimal', '--default-toolchain', 'stable', '--no-modify-path')
}
Invoke-Checked (Join-Path $rustBin 'rustup.exe') @('target', 'add', 'x86_64-pc-windows-msvc')

$tools = @(
    @{ Archive='cmake-3.31.10-windows-x86_64.zip'; Url='https://cmake.org/files/v3.31/cmake-3.31.10-windows-x86_64.zip'; Sha='13d1a463d7130df5339baedd63d8ae990aaf385062b2f42f372796143ae94086'; Bin='cmake-3.31.10-windows-x86_64/bin'; Exe='cmake.exe' },
    @{ Archive='nasm-2.16.03-win64.zip'; Url='https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip'; Sha='3ee4782247bcb874378d02f7eab4e294a84d3d15f3f6ee2de2f47a46aa7226e6'; Bin='nasm-2.16.03'; Exe='nasm.exe' },
    @{ Archive='node-v22.23.5-win-x64.zip'; Url='https://nodejs.org/dist/v22.23.5/node-v22.23.5-win-x64.zip'; Sha='4a191082e9706866830379d577d2cc8a50c776fcd9436a8d061b063ed0d9a0e3'; Bin='node-v22.23.5-win-x64'; Exe='node.exe' }
)
foreach ($tool in $tools) {
    $archive = Join-Path $sharedCache $tool.Archive
    $bin = Join-Path $sharedCache $tool.Bin
    if (!(Test-Path (Join-Path $bin $tool.Exe))) {
        Receive-Pinned $tool.Url $archive $tool.Sha
        Expand-Archive -LiteralPath $archive -DestinationPath $sharedCache -Force
    }
    $bin >> $env:GITHUB_PATH
}
$cmake = Join-Path $sharedCache 'cmake-3.31.10-windows-x86_64/bin/cmake.exe'

$clang = Join-Path $sharedCache 'libclang-18.1.3.2'
$libclang = Join-Path $clang 'runtimes/win-x64/native'
if (!(Test-Path (Join-Path $libclang 'libclang.dll'))) {
    $archive = Join-Path $sharedCache 'libclang-win-x64-18.1.3.2.zip'
    Receive-Pinned 'https://api.nuget.org/v3-flatcontainer/libclang.runtime.win-x64/18.1.3.2/libclang.runtime.win-x64.18.1.3.2.nupkg' $archive '524e5cce91f43a74d5bbf57debc42c11b87e8fa86f1fc95be7375dd67b427e18'
    Expand-Archive -LiteralPath $archive -DestinationPath $clang -Force
}

$nsis = Join-Path $qtCache 'nsis-3.13/makensis.exe'
if (!(Test-Path $nsis)) {
    $archive = Join-Path $qtCache 'nsis-3.13.zip'
    Receive-Pinned 'https://github.com/tauri-apps/binary-releases/releases/download/nsis-3.13/nsis-3.13.zip' $archive 'ba63dffc4410ee89193e1cb5a41989991bd77c61068da17e3156d136b7b0b3d8'
    Expand-Archive -LiteralPath $archive -DestinationPath $qtCache -Force
}

$deno = Join-Path $qtCache 'deno-2.9.8'
if (!(Test-Path (Join-Path $deno 'deno.exe'))) {
    $archive = Join-Path $sharedCache 'auralis-deno-2.9.8.zip'
    Receive-Pinned 'https://github.com/denoland/deno/releases/download/v2.9.8/deno-x86_64-pc-windows-msvc.zip' $archive 'cba84b26e0df5ae7f74fc66b86a95b866872a86292ebd84fa1e959927edd93bf'
    Expand-Archive -LiteralPath $archive -DestinationPath $deno -Force
}
$denoLicense = Join-Path $deno 'deno-LICENSE.md'
Receive-Pinned 'https://raw.githubusercontent.com/denoland/deno/v2.9.8/LICENSE.md' $denoLicense 'f62497fffecc0852960c8d3e6934b9db86d16396e9b604072e923892cae3a588'

# Exact package names and SHA-256 values from the official Qt repository.
$qtVersion = '6.11.2'
$qtBase = 'https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_6112/qt6_6112_msvc2022_64'
$qtArchives = @(
    @{ Module='qtbase'; Sha='fd984b7264361b4dd3fd2a417702ca1258e4086268f2ee6a69b9a393d9c3f6bb' },
    @{ Module='qtdeclarative'; Sha='5591ca564c1a9299a45a15b6b1d324c86e0aaed7cf6c47b7e6fe464aecae2587' },
    @{ Module='qttools'; Sha='5f2b387a1f8055102b1388ff4ea743124ed6389d442f75c659728bb5c2a56946' },
    @{ Module='qtsvg'; Sha='417f44499c835b2303f3ff78043179bb23442f33d5d2816fbf7e8dbf275b1c89' },
    @{ Module='qtshadertools'; Addon=$true; Sha='d434c320f5788cf54c71e68ab28488ceb2f1ba725e63241530155347a4c5081e' },
    @{ Module='qtquicktimeline'; Addon=$true; Sha='cca45ce1783814b47768f576828c292b89f164905bff92c5adb87c97e74ddea6' },
    @{ Module='qtquick3d'; Addon=$true; Sha='39781144a0712d710c4635208f4e50f9c26c1af8b7736bd4ae4689a076241d06' },
    @{ Module='qtmultimedia'; Addon=$true; Sha='24d73c45fefe5e260aa9a99eea1aea48adcad54f93bddaa3ec5b0574b55f57c7' },
    @{ Module='d3dcompiler'; Archive='d3dcompiler_47-x64.7z'; Sha='b1c379f739fa59a495a388c0878757e3d90fb72e0df771237a1ee4a2c1675d15' }
)
$sdk = Join-Path $qtCache "$qtVersion/msvc2022_64"
$archiveCache = Join-Path $qtCache 'archives'
New-Item -ItemType Directory -Force -Path $archiveCache, $sdk | Out-Null
foreach ($package in $qtArchives) {
    $mark = Join-Path $sdk ".auralis-$($package.Module)-$($package.Sha)"
    if (Test-Path $mark) { continue }
    $module = $package.Module
    $component = if ($package.Addon) { "qt.qt6.6112.addons.$module.win64_msvc2022_64" } else { 'qt.qt6.6112.win64_msvc2022_64' }
    $archiveName = if ($package.Archive) { $package.Archive } else { "$module-Windows-Windows_11_24H2-MSVC2022-Windows-Windows_11_24H2-X86_64.7z" }
    $archiveName = "6.11.2-0-202608131017$archiveName"
    $archive = Join-Path $archiveCache $archiveName
    Receive-Pinned "$qtBase/$component/$archiveName" $archive $package.Sha
    Push-Location $sdk
    try { Invoke-Checked $cmake @('-E','tar','xf',$archive) } finally { Pop-Location }
    New-Item -ItemType File -Path $mark -Force | Out-Null
}
foreach ($file in @('bin/windeployqt.exe','bin/qtpaths.exe','lib/cmake/Qt6/Qt6Config.cmake','lib/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake','qml/QtMultimedia/qmldir')) {
    if (!(Test-Path (Join-Path $sdk $file))) { throw "Qt SDK package is incomplete: $file" }
}
"[Paths]`nPrefix=.." | Set-Content -LiteralPath (Join-Path $sdk 'bin/qt.conf') -Encoding ascii

$rustBin >> $env:GITHUB_PATH
"LIBCLANG_PATH=$libclang" >> $env:GITHUB_ENV
"CARGO_HOME=$env:CARGO_HOME" >> $env:GITHUB_ENV
"RUSTUP_HOME=$env:RUSTUP_HOME" >> $env:GITHUB_ENV
"CARGO_TARGET_DIR=$targetDir" >> $env:GITHUB_ENV
"TEMP=$temp" >> $env:GITHUB_ENV
"TMP=$temp" >> $env:GITHUB_ENV
"AURALIS_QT_ROOT=$sdk" >> $env:GITHUB_ENV
"AURALIS_QT_WORK=$qtCache" >> $env:GITHUB_ENV
"AURALIS_QT_NSIS=$nsis" >> $env:GITHUB_ENV
"AURALIS_QT_DENO=$deno" >> $env:GITHUB_ENV
