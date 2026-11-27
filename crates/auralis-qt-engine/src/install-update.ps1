$ErrorActionPreference = 'Stop'
$script:background = $env:AURALIS_UPDATE_BACKGROUND -eq '1'
$script:logPath = $env:AURALIS_UPDATE_LOG
if (!$script:logPath -and $env:LOCALAPPDATA) {
    $script:logPath = Join-Path $env:LOCALAPPDATA 'Auralis Download Manager Updates/update.log'
}

function Write-UpdateLog([string]$message) {
    try {
        $directory = [IO.Path]::GetDirectoryName($script:logPath)
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        $line = '{0:o} {1}{2}' -f [DateTime]::UtcNow, $message, [Environment]::NewLine
        [IO.File]::AppendAllText($script:logPath, $line, [Text.UTF8Encoding]::new($false))
    } catch { }
}

function Start-Application([string]$path) {
    $start = [Diagnostics.ProcessStartInfo]::new($path)
    $start.WorkingDirectory = [Environment]::SystemDirectory
    $start.UseShellExecute = $false
    if ($script:background) { $start.Arguments = '--auralis-startup-minimized' }
    [Diagnostics.Process]::Start($start).Dispose()
}

function Get-AuralisProcess([string]$path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    Get-Process -Name $name -ErrorAction SilentlyContinue |
        Where-Object { try { $_.Path -ieq $path } catch { $false } } |
        Select-Object -First 1
}

function Wait-ForAuralis([string]$path, [int]$seconds) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $seconds) {
        if (Get-AuralisProcess $path) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return [bool](Get-AuralisProcess $path)
}

try {
    $appPath = $env:AURALIS_UPDATE_OLD
    $installer = $env:AURALIS_UPDATE_INSTALLER
    $manifest = $env:AURALIS_UPDATE_MANIFEST
    $appDirectory = [IO.Path]::GetDirectoryName($appPath)
    $appProcess = 0
    if (![int]::TryParse($env:AURALIS_UPDATE_PID, [ref]$appProcess) -or $appProcess -le 0) {
        throw 'The closing Auralis process ID is invalid.'
    }
    if (!$appPath -or !$installer -or !$manifest -or !$appDirectory) {
        throw 'The update handoff paths are incomplete.'
    }
    Write-UpdateLog "Update handoff started for $appPath. Waiting for process $appProcess to close."

    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt 90 -and (Get-Process -Id $appProcess -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $appProcess -ErrorAction SilentlyContinue) {
        throw 'Timed out waiting for Auralis to close.'
    }
    Write-UpdateLog 'Auralis closed; waiting for its download engine to release installation files.'

    $backend = Join-Path $appDirectory 'mdm-legacy.exe'
    $busy = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $busy = Get-Process -Name 'mdm-legacy' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -ieq $backend }
        if (!$busy) { break }
        Start-Sleep -Seconds 1
    }
    if ($busy) { throw 'The Auralis download engine did not release its files.' }

    # Keep this read-only handle through setup so the staged executable cannot be
    # replaced or deleted after verification and before NSIS exits.
    $file = [IO.File]::Open($installer, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($file.Length -ne [long]$env:AURALIS_UPDATE_SIZE) { throw 'The downloaded installer size changed.' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash($file)).Replace('-', '') }
        finally { $sha.Dispose() }
        if ($digest -ine $env:AURALIS_UPDATE_SHA256) { throw 'The downloaded installer digest changed.' }

        Write-UpdateLog 'Verified staged installer; starting silent per-user setup.'
        $start = [Diagnostics.ProcessStartInfo]::new($installer)
        $start.WorkingDirectory = [Environment]::SystemDirectory
        $start.UseShellExecute = $false
        # NSIS requires the unquoted /D= path as the last argument, including spaces.
        if ($script:background) {
            $start.Arguments = '/S /P /UPDATE /D=' + $appDirectory
        } else {
            $start.Arguments = '/P /UPDATE /R /D=' + $appDirectory
        }
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            Write-UpdateLog "Setup exited with code $exitCode."
            if ($exitCode -ne 0) { throw "Auralis setup failed with exit code $exitCode." }
        } finally { $process.Dispose() }
    } finally { $file.Dispose() }

    if ($script:background) {
        Write-UpdateLog 'Setup succeeded; restarting Auralis in the system tray.'
        if (!(Get-AuralisProcess $appPath)) { Start-Application $appPath }
        if (!(Wait-ForAuralis $appPath 20)) { throw 'Auralis setup succeeded, but the app did not start.' }
    } elseif (!(Wait-ForAuralis $appPath 15)) {
        Write-UpdateLog 'Setup succeeded but did not relaunch Auralis; starting it directly.'
        Start-Application $appPath
        if (!(Wait-ForAuralis $appPath 20)) { throw 'Auralis setup succeeded, but the app did not start.' }
    }

    Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    Write-UpdateLog 'Auralis started successfully after setup.'
    exit 0
} catch {
    $message = $_.Exception.Message
    Write-UpdateLog "Update handoff failed: $message"
    try {
        if ($appPath -and !(Get-AuralisProcess $appPath)) {
            Write-UpdateLog 'Attempting to reopen Auralis after the failed update.'
            Start-Application $appPath
            if (Wait-ForAuralis $appPath 20) {
                Write-UpdateLog 'Auralis reopened after the failed update.'
            } else {
                Write-UpdateLog 'Auralis did not appear after the recovery launch.'
            }
        } else {
            Write-UpdateLog 'Auralis is already running; recovery launch is unnecessary.'
        }
    } catch {
        Write-UpdateLog "Recovery launch failed: $($_.Exception.Message)"
    }
    exit 1
}
