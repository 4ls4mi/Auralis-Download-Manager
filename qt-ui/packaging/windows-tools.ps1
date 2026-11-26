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
$minimumSystemSpace = 20 * 1024 * 1024 * 1024
$alternate = $volumes | Where-Object { $_.DeviceID -ne $env:SystemDrive -and $_.FreeSpace -ge $minimumAlternateSpace } | Select-Object -First 1
$runnerRoot = Join-Path $env:LOCALAPPDATA 'AuralisRunner'
if ($system -and $system.FreeSpace -lt $minimumSystemSpace -and $alternate) {
    $runnerRoot = Join-Path ($alternate.DeviceID + '\') 'AuralisRunner'
}
# Qt SDK extraction may use a roomy alternate drive while Cargo keeps the
# same cache path as the existing self-hosted release workflow.
$rustRoot = Join-Path $env:LOCALAPPDATA 'AuralisRunner'
if ($system -and $system.FreeSpace -lt $minimumSystemSpace -and $alternate) {
    $rustRoot = Join-Path ($alternate.DeviceID + '\') 'AuralisRunner'
}
$targetDir = Join-Path $rustRoot 'target'
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

# Microsoft DirectXShaderCompiler v1.9.2609, GitHub release asset 596913261.
$dxcSha = 'ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1'
$dxc = Join-Path $qtCache 'dxc-1.9.2609-x64'
$dxcMark = Join-Path $dxc ".auralis-$dxcSha"
$dxcMembers = @{
    'bin\x64\dxcompiler.dll' = 'dxcompiler.dll'
    'bin\x64\dxil.dll' = 'dxil.dll'
    'LICENCE-MIT.txt' = 'LICENCE-MIT.txt'
    'LICENSE-LLVM.txt' = 'LICENSE-LLVM.txt'
    'LICENSE-MS.txt' = 'LICENSE-MS.txt'
}
$missingDxc = @($dxcMembers.Values | Where-Object { !(Test-Path -LiteralPath (Join-Path $dxc $_) -PathType Leaf) })
if (!(Test-Path -LiteralPath $dxcMark -PathType Leaf) -or $missingDxc.Count) {
    $archive = Join-Path $qtCache 'dxc_2026_09_29.zip'
    Receive-Pinned 'https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip' $archive $dxcSha
    New-Item -ItemType Directory -Force -Path $dxc | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($member in $dxcMembers.GetEnumerator()) {
            $entry = $zip.GetEntry($member.Key)
            if (!$entry) { throw "DXC release archive is missing $($member.Key)." }
            $destination = Join-Path $dxc $member.Value
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
        }
    } finally { $zip.Dispose() }
    New-Item -ItemType File -Path $dxcMark -Force | Out-Null
}

# Exact package names and SHA-256 values from the official Qt repository.
$qtVersion = '6.11.3'
$qtSeries = '6113'
$qtBuild = '6.11.3-0-202610220312'
$qtBase = "https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_$qtSeries/qt6_${qtSeries}_msvc2022_64"
$qtArchives = @(
    @{ Module='qtbase'; Sha='68be61b613b963daf206834fdcc57dd3b84baff3082e50679e5846ca4a7a8b86' },
    @{ Module='qtdeclarative'; Sha='7c1bb872495144f154d24931b0b58f817defbfd4099b0ac99372062bdfd2ac81' },
    @{ Module='qttools'; Sha='b519f552424d8c748ed37c6b3a7615d29a1e3920383ee8ccf9b2066998341c2c' },
    @{ Module='qtsvg'; Sha='e8c789e1a059601dd82114dd9560952891e7c8e94e1cb291166eb61d74800353' },
    @{ Module='qtshadertools'; Addon=$true; Sha='dd2bfa173037be6c1c5b6e4a3c1b27b19c2c3422b21ff0addc625f5c21cd407f' },
    @{ Module='qtquicktimeline'; Addon=$true; Sha='6bf980bd3c1c4158d830fb703deff22335f7a5c11d930a302d6c126909e351c3' },
    @{ Module='qtquick3d'; Addon=$true; Sha='231fdc53ec2fe3c4c5d6c394862f44fa76df6a095a2da33118189c95e5fde5f6' },
    @{ Module='qtmultimedia'; Addon=$true; Sha='344fb1b0185ab810cfc247dabd1470d14e23999e6861f3a7e62d217fa6ec5fc5' },
    @{ Module='qtwebsockets'; Addon=$true; Sha='471d4033691b34d3a1aa0b7f20b75d49f55e66c47cf2fc16cb639ec6e52d37da' },
    @{ Module='d3dcompiler'; Archive='d3dcompiler_47-x64.7z'; Sha='be4292719fe0930c988236972bca7f5926db1342e1c85b247e1cef87b903fc9a' }
)
$sdk = Join-Path $qtCache "$qtVersion/msvc2022_64"
$archiveCache = Join-Path $qtCache 'archives'
New-Item -ItemType Directory -Force -Path $archiveCache, $sdk | Out-Null
foreach ($package in $qtArchives) {
    $mark = Join-Path $sdk ".auralis-$($package.Module)-$($package.Sha)"
    if (Test-Path $mark) { continue }
    $module = $package.Module
    $component = if ($package.Addon) { "qt.qt6.$qtSeries.addons.$module.win64_msvc2022_64" } else { "qt.qt6.$qtSeries.win64_msvc2022_64" }
    $archiveName = if ($package.Archive) { $package.Archive } else { "$module-Windows-Windows_11_24H2-MSVC2022-Windows-Windows_11_24H2-X86_64.7z" }
    $archiveName = "$qtBuild$archiveName"
    $archive = Join-Path $archiveCache $archiveName
    Receive-Pinned "$qtBase/$component/$archiveName" $archive $package.Sha
    Push-Location $sdk
    try { Invoke-Checked $cmake @('-E','tar','xf',$archive) } finally { Pop-Location }
    New-Item -ItemType File -Path $mark -Force | Out-Null
}
foreach ($file in @(
    'bin/windeployqt.exe','bin/qtpaths.exe','bin/lrelease.exe',
    'lib/cmake/Qt6/Qt6Config.cmake','lib/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake',
    'lib/cmake/Qt6LinguistTools/Qt6LinguistToolsConfig.cmake',
    'lib/cmake/Qt6WebSockets/Qt6WebSocketsConfig.cmake','qml/QtMultimedia/qmldir'
)) {
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
"AURALIS_QT_DXC=$dxc" >> $env:GITHUB_ENV
