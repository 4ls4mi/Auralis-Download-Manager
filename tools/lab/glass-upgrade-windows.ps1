# Windows runner only: install the published preview into an isolated directory,
# upgrade with the new installer and verify NSIS /UPDATE /R actually relaunches.
$ErrorActionPreference = 'Stop'
$oldSetup = Join-Path $env:RUNNER_TEMP 'glass-old-preview.exe'
$root = Join-Path $env:RUNNER_TEMP 'glass-upgrade-fixture'
$state = Join-Path $env:RUNNER_TEMP 'glass-upgrade-data'
$exe = Join-Path $root 'mister-hybrid-glass.exe'
$newSetup = @(Get-ChildItem 'glass-ui/src-tauri/target/release/bundle/nsis' -Filter '*.exe' -File)
if ($newSetup.Count -ne 1) { throw 'Expected exactly one new installer' }
Invoke-WebRequest 'https://github.com/4ls4mi/misterdownloadmanager/releases/download/v0.3.0-glass-preview.1/Mister.Hybrid.Glass_0.3.0_x64-setup.exe' -OutFile $oldSetup
if ((Get-FileHash $oldSetup -Algorithm SHA256).Hash.ToLowerInvariant() -ne '3ba9925fa271728eeb1785d760d157ca49996ccfc1f96c3304e56b29c9f2bc04') { throw 'Old preview digest differs from the released installer' }
$previousData = $env:MDM_DATA_DIR
$env:MDM_DATA_DIR = $state
try {
    $old = Start-Process -FilePath $oldSetup -ArgumentList @('/S', "/D=$root") -Wait -PassThru
    if ($old.ExitCode -ne 0 -or !(Test-Path $exe)) { throw "Isolated old-version install failed: $($old.ExitCode)" }
    if (!(Test-Path (Join-Path $root 'uninstall.exe'))) { throw 'Installed updater could not find the NSIS uninstaller' }
    $new = Start-Process -FilePath $newSetup[0].FullName -ArgumentList @('/S','/UPDATE','/R', "/D=$root") -Wait -PassThru
    if ($new.ExitCode -ne 0) { throw "Isolated upgrade failed: $($new.ExitCode)" }
    $version = (Get-Item $exe).VersionInfo.ProductVersion
    if ($version -notlike '0.3.1*') { throw "Expected 0.3.1 after upgrade, got $version" }
    $restarted = $null
    for ($i=0; $i -lt 30; $i++) {
        $restarted = Get-Process -Name 'mister-hybrid-glass' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Select-Object -First 1
        if ($restarted) { break }
        Start-Sleep -Seconds 1
    }
    if (!$restarted) { throw 'The updated application did not restart' }
    Write-Host "PASS: isolated 0.3.0 -> $version NSIS upgrade restarted the installed Glass app"
} finally {
    Get-Process -Name 'mister-hybrid-glass','mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($root,[System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
    $uninstaller = Join-Path $root 'uninstall.exe'
    if (Test-Path $uninstaller) { Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -ErrorAction SilentlyContinue | Out-Null }
    $env:MDM_DATA_DIR = $previousData
}
