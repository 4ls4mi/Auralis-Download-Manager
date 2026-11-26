# Check native packaging tools before the expensive Rust and Qt builds.
$ErrorActionPreference = 'Stop'
foreach ($name in @('AURALIS_QT_NSIS', 'CARGO_TARGET_DIR', 'TEMP')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (!$value) { throw "Set $name by running windows-tools.ps1 first." }
}
$targetDrive = [IO.Path]::GetPathRoot($env:CARGO_TARGET_DIR)
$temporaryDrive = [IO.Path]::GetPathRoot($env:TEMP)
foreach ($driveRoot in @($targetDrive, $temporaryDrive) | Select-Object -Unique) {
    $drive = [IO.DriveInfo]::new($driveRoot)
    if ($drive.AvailableFreeSpace -lt 20GB) {
        throw "The build/cache volume $driveRoot needs at least 20 GB free. Choose a larger build volume before compiling."
    }
}
try {
    $version = & $env:AURALIS_QT_NSIS /VERSION 2>&1
    if ($LASTEXITCODE -ne 0) { throw "NSIS returned $LASTEXITCODE." }
    Write-Host "NSIS compiler: $version"
} catch {
    throw "The native NSIS compiler could not start: $($_.Exception.Message) Run packaging in the normal self-hosted Windows Actions runner. A Windows DLL relocation error occurs before installer-script compilation; do not work around it by disabling Windows protection."
}
