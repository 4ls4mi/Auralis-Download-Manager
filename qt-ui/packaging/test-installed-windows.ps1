# Test the distributable installer without touching the runner user's installation or data.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $env:AURALIS_QT_JOB 'smoke-install'
$data = Join-Path $env:AURALIS_QT_JOB 'smoke-data'
$exe = Join-Path $fixture 'auralis-download-manager.exe'
$marker = Join-Path $data 'qt-engine-smoke.ok'
$previousData = $env:MDM_DATA_DIR
$previousDownloads = $env:MDM_DOWNLOADS
$previousSkipHost = $env:AURALIS_TEST_SKIP_HOST
$previousRenderer = $env:QSG_RHI_BACKEND
$previousGraphicsInfo = $env:QSG_INFO
$env:MDM_DATA_DIR = $data
$env:MDM_DOWNLOADS = Join-Path $data 'downloads'
$env:AURALIS_TEST_SKIP_HOST = '1'
$env:QSG_INFO = '1'
Remove-Item Env:QSG_RHI_BACKEND -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $data, $env:MDM_DOWNLOADS | Out-Null

function Write-FixtureDiagnostics([DateTime]$StartedAt) {
    $console = Join-Path $env:MDM_DATA_DIR 'qt-smoke-console.log'
    if (Test-Path -LiteralPath $console) {
        Write-Host 'Auralis smoke diagnostics'
        Get-Content -LiteralPath $console -Tail 60 | ForEach-Object { Write-Host $_ }
    }
    try {
        $filter = @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $StartedAt }
        Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
            Where-Object { $_.Properties.Value -contains $exe } |
            Select-Object -First 2 | ForEach-Object { Write-Host $_.Message }
    } catch {
        Write-Host 'The runner could not read the application error log.'
    }
}

function Run-Fixture([string]$Process, [string[]]$Arguments, [int]$Timeout = 180000) {
    $startedAt = Get-Date
    $child = Start-Process -FilePath $Process -ArgumentList $Arguments -WorkingDirectory (Split-Path -Parent $Process) -PassThru
    if (!$child.WaitForExit($Timeout)) {
        Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        Write-FixtureDiagnostics $startedAt
        throw "Timed out waiting for $Process."
    }
    if ($child.ExitCode -ne 0) {
        Start-Sleep -Seconds 2
        Write-FixtureDiagnostics $startedAt
        throw "$Process exited with code $($child.ExitCode)."
    }
}

try {
    # NSIS requires the unquoted /D= argument to come last.
    Run-Fixture $env:AURALIS_QT_INSTALLER @('/S', '/NOREG', "/D=$fixture")
    if (!(Test-Path $exe) -or !(Test-Path (Join-Path $fixture 'uninstall.exe'))) {
        throw 'The standalone Qt installation is incomplete.'
    }
    try {
        Run-Fixture $exe @('--engine-smoke') 90000
    } catch {
        $defaultRendererFailure = $_
        $env:QSG_RHI_BACKEND = 'd3d11'
        $env:MDM_DATA_DIR = Join-Path $data 'diagnostic-d3d11'
        $env:MDM_DOWNLOADS = Join-Path $env:MDM_DATA_DIR 'downloads'
        New-Item -ItemType Directory -Force -Path $env:MDM_DOWNLOADS | Out-Null
        try {
            Run-Fixture $exe @('--engine-smoke') 90000
            Write-Host 'The installed application completed the fixture when forced to use Direct3D 11.'
        } catch {
            Write-Host "The Direct3D 11 comparison also failed: $_"
        } finally {
            $env:MDM_DATA_DIR = $data
            $env:MDM_DOWNLOADS = Join-Path $data 'downloads'
            Remove-Item Env:QSG_RHI_BACKEND -ErrorAction SilentlyContinue
        }
        throw $defaultRendererFailure
    }
    if (!(Test-Path $marker)) { throw 'The installed application did not verify its engine transfer.' }

    # Exercise the in-app updater's NSIS arguments and wait for the installed app
    # to verify a loopback transfer again after the installer launches it.
    Remove-Item -LiteralPath $marker -Force
    $upgradedAt = Get-Date
    Run-Fixture $env:AURALIS_QT_INSTALLER @('/P', '/UPDATE', '/R', '/NOREG', '/ARGS=--engine-smoke', "/D=$fixture")
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (!(Test-Path $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (!(Test-Path $marker)) {
        Write-FixtureDiagnostics $upgradedAt
        throw 'The passive update did not relaunch a working installed app.'
    }

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
    $env:QSG_RHI_BACKEND = $previousRenderer
    $env:QSG_INFO = $previousGraphicsInfo
}
