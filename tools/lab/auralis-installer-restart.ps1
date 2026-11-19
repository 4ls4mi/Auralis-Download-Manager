# Exercise the same NSIS installer arguments as the in-app updater in an isolated runner.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'auralis-upgrade-fixture'
$data = Join-Path $env:RUNNER_TEMP 'auralis-upgrade-data'
$oldSetup = Join-Path $env:RUNNER_TEMP 'auralis-0.3.12.exe'
$exe = Join-Path $root 'auralis-download-manager.exe'
$newSetup = @(Get-ChildItem 'glass-ui/src-tauri/target/release/bundle/nsis' -Filter '*.exe' -File)
if ($newSetup.Count -ne 1) { throw 'Expected one Auralis installer' }
Invoke-WebRequest 'https://github.com/4ls4mi/Auralis-Download-Manager/releases/download/v0.3.12/Auralis.Download.Manager_0.3.12_x64-setup.exe' -OutFile $oldSetup
if ((Get-FileHash $oldSetup -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'b97f1e185e83806442f28c38d098eac3e0e72b030849289ed94b06a77855f2fe') { throw 'The 0.3.12 installer digest differs from the verified release' }
$previousData = $env:MDM_DATA_DIR
$env:MDM_DATA_DIR = $data
try {
  $old = Start-Process -FilePath $oldSetup -ArgumentList @('/S', "/D=$root") -PassThru
  if (!$old.WaitForExit(180000) -or $old.ExitCode -ne 0 -or !(Test-Path $exe)) { throw 'The 0.3.12 fixture installation failed' }
  $update = Start-Process -FilePath $newSetup[0].FullName -ArgumentList @('/P','/UPDATE','/R') -PassThru
  if (!$update.WaitForExit(180000)) { throw 'The passive upgrade did not finish' }
  if ($update.ExitCode -ne 0) { throw "Passive upgrade failed: $($update.ExitCode)" }
  $restarted=$null
  for ($i=0; $i -lt 45; $i++) {
    $restarted=Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Select-Object -First 1
    if ($restarted) { break }
    Start-Sleep -Seconds 1
  }
  if (!$restarted) { throw 'The updated app did not restart automatically' }
  $version=(Get-Item $exe).VersionInfo.ProductVersion
  if ($version -notlike '0.3.13*') { throw "Expected 0.3.13 after upgrade, got $version" }
  Write-Host "PASS: 0.3.12 upgraded to $version and automatically reopened."
} finally {
  Get-Process -Name 'auralis-download-manager','mdm-legacy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($root,[System.StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
  $uninstaller=Join-Path $root 'uninstall.exe'
  if (Test-Path $uninstaller) { Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -ErrorAction SilentlyContinue }
  $env:MDM_DATA_DIR=$previousData
}
