$ErrorActionPreference = 'Stop'
$systemDirectory = [Environment]::SystemDirectory

function Start-Application([string]$path) {
    $start = [Diagnostics.ProcessStartInfo]::new($path)
    $start.WorkingDirectory = $systemDirectory
    $start.UseShellExecute = $false
    [Diagnostics.Process]::Start($start).Dispose()
}

$appProcess = [int]$env:AURALIS_UPDATE_PID
$appPath = $env:AURALIS_UPDATE_OLD
$installer = $env:AURALIS_UPDATE_INSTALLER
$appDirectory = [IO.Path]::GetDirectoryName($appPath)
Wait-Process -Id $appProcess -Timeout 90 -ErrorAction SilentlyContinue
if (Get-Process -Id $appProcess -ErrorAction SilentlyContinue) { exit 1 }

$backend = Join-Path $appDirectory 'mdm-legacy.exe'
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $busy = Get-Process -Name 'mdm-legacy' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $backend }
    if (!$busy) { break }
    Start-Sleep -Seconds 1
}
if ($busy) {
    Start-Application $appPath
    exit 1
}

try {
    # Keep a handle that denies writes and deletion from the final verification
    # through installer exit. NSIS reopens its own executable during extraction.
    $file = [IO.File]::Open($installer, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($file.Length -ne [long]$env:AURALIS_UPDATE_SIZE) { throw 'The downloaded installer size changed.' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash($file)).Replace('-', '') }
        finally { $sha.Dispose() }
        if ($digest -ine $env:AURALIS_UPDATE_SHA256) { throw 'The downloaded installer digest changed.' }

        $start = [Diagnostics.ProcessStartInfo]::new($installer)
        $start.WorkingDirectory = $systemDirectory
        $start.UseShellExecute = $false
        # NSIS requires the unquoted /D= path as the last argument, including spaces.
        $start.Arguments = '/P /UPDATE /R /D=' + $appDirectory
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw 'Auralis setup failed.' }
        } finally { $process.Dispose() }
    } finally { $file.Dispose() }
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
} catch {
    Start-Application $appPath
    exit 1
}
