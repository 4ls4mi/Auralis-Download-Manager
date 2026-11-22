# Test the distributable installer without touching the runner user's installation or data.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $env:AURALIS_QT_JOB 'smoke-install'
$data = Join-Path $env:AURALIS_QT_JOB 'smoke-data'
$exe = Join-Path $fixture 'auralis-download-manager.exe'
$marker = Join-Path $data 'qt-engine-smoke.ok'
$previousData = $env:MDM_DATA_DIR
$previousDownloads = $env:MDM_DOWNLOADS
$previousSkipHost = $env:AURALIS_TEST_SKIP_HOST
$env:MDM_DATA_DIR = $data
$env:MDM_DOWNLOADS = Join-Path $data 'downloads'
$env:AURALIS_TEST_SKIP_HOST = '1'
New-Item -ItemType Directory -Force -Path $data, $env:MDM_DOWNLOADS | Out-Null

function Run-Fixture([string]$Process, [string[]]$Arguments, [int]$Timeout = 180000) {
    $child = Start-Process -FilePath $Process -ArgumentList $Arguments -PassThru
    if (!$child.WaitForExit($Timeout)) {
        Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        throw "Timed out waiting for $Process."
    }
    if ($child.ExitCode -ne 0) { throw "$Process exited with code $($child.ExitCode)." }
}

try {
    # NSIS requires the unquoted /D= argument to come last.
    Run-Fixture $env:AURALIS_QT_INSTALLER @('/S', '/NOREG', "/D=$fixture")
    if (!(Test-Path $exe) -or !(Test-Path (Join-Path $fixture 'uninstall.exe'))) {
        throw 'The standalone Qt installation is incomplete.'
    }
    Run-Fixture $exe @('--engine-smoke') 90000
    if (!(Test-Path $marker)) { throw 'The installed application did not verify its engine transfer.' }

    # Exercise the in-app updater's NSIS arguments and wait for the installed app
    # to verify a loopback transfer again after the installer launches it.
    Remove-Item -LiteralPath $marker -Force
    Run-Fixture $env:AURALIS_QT_INSTALLER @('/P', '/UPDATE', '/R', '/NOREG', '/ARGS=--engine-smoke', "/D=$fixture")
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (!(Test-Path $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (!(Test-Path $marker)) { throw 'The passive update did not relaunch a working installed app.' }

    Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $exe } | Wait-Process -Timeout 10

    # Confirm that the uninstaller preserves user-created files.
    $ownedByUser = Join-Path $fixture 'keep-after-uninstall.txt'
    Set-Content -LiteralPath $ownedByUser -Value 'User file'
    Run-Fixture (Join-Path $fixture 'uninstall.exe') @('/S', '/NOREG')
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Test-Path $exe) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if ((Test-Path $exe) -or !(Test-Path $ownedByUser)) {
        throw 'The uninstaller did not remove only the packaged application files.'
    }
    Write-Host 'Verified silent install, native Qt and engine startup, passive upgrade relaunch, and scoped uninstallation.'
} finally {
    Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $exe } | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture, $data -Recurse -Force -ErrorAction SilentlyContinue
    $env:MDM_DATA_DIR = $previousData
    $env:MDM_DOWNLOADS = $previousDownloads
    $env:AURALIS_TEST_SKIP_HOST = $previousSkipHost
}
