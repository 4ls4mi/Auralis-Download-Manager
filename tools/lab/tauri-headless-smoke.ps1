# Windows runtime smoke test: real headless MDM + authenticated IPC + live settings.
# Uses an isolated temporary data directory; never reads or writes user downloads.
param([Parameter(Mandatory)][string]$Backend)
$ErrorActionPreference = 'Stop'
$Backend = (Resolve-Path $Backend).Path
$root = Join-Path $env:RUNNER_TEMP ("mister-glass-smoke-" + $PID)
New-Item -ItemType Directory -Force $root | Out-Null
$env:MDM_DATA_DIR = $root
$env:MDM_REMOTE = "off"
$env:MDM_GLASS_HEADLESS = "1"
$proc = $null

function Invoke-GlassIpc([hashtable] $command) {
    $epfile = Join-Path $root "ipc.json"
    $endpoint = Get-Content $epfile -Raw | ConvertFrom-Json
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect("127.0.0.1", [int]$endpoint.port)
        $client.ReceiveTimeout = 5000
        $client.SendTimeout = 5000
        $stream = $client.GetStream()
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        # MDM IPC uses #[serde(flatten)] Command, so send the fields at
        # the TOP LEVEL beside token, never a nested "cmd" object.
        $payload = @{ token = $endpoint.token }
        foreach ($entry in $command.GetEnumerator()) {
            $payload[$entry.Key] = $entry.Value
        }
        $json = $payload | ConvertTo-Json -Depth 10 -Compress
        $writer.WriteLine($json)
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { throw "Empty IPC reply" }
        return ($line | ConvertFrom-Json)
    }
    finally { $client.Dispose() }
}
try {
    Write-Host "Starting isolated Rust backend with --headless and no remote HTTP service"
    $proc = Start-Process -FilePath $Backend -ArgumentList '--headless' -PassThru
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 300
        if ($proc.HasExited) { throw "Headless downloader exited unexpectedly: $($proc.ExitCode)" }
        if (Test-Path (Join-Path $root 'ipc.json')) {
            try {
                $identity = Invoke-GlassIpc @{ query = "glass-backend" }
                if ($identity.headless -eq $true -and $identity.glass -eq $true) {
                    $ready = $true
                    break
                }
            }
            catch { Write-Host "Waiting for authenticated IPC: $_" }
        }
    }
    if (-not $ready) { throw "Never received Glass headless IPC identity" }
    Write-Host "PASS: headless=true, glass=true, IPC responds"
    $proc.Refresh()
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
        throw "Headless backend unexpectedly owns a visible Windows main window"
    }
    Write-Host "PASS: no original MDM main window"

    # The Glass progress and list windows must receive the genuine engine
    # telemetry (segment cursors / connections / server), not fake percentages.
    $visuals = Invoke-GlassIpc @{ query = "glass-visuals" }
    if (-not $visuals.PSObject.Properties.Name.Contains("downloads")) {
        throw "Glass engine visuals endpoint does not expose downloads array"
    }
    if ($null -eq $visuals.downloads) {
        throw "Visuals endpoint must return an array, even when no downloads exist"
    }
    Write-Host "PASS: authenticated original engine segment telemetry endpoint"

    $settings = Invoke-GlassIpc @{ query = "glass-settings" }
    if (-not $settings.PSObject.Properties.Name.Contains('max_connections')) {
        throw "The native Glass settings endpoint is missing connection limits"
    }
    $set = Invoke-GlassIpc @{ action = "glass-setting"; category = "max_connections"; queue = "7" }
    if ($set.saved -ne $true) { throw "Rust engine refused validated settings update" }
    $readback = Invoke-GlassIpc @{ query = "glass-settings" }
    if ($readback.max_connections -ne 7) {
        throw "Setting did not propagate to live Rust backend"
    }
    Write-Host "PASS: live engine settings can be read and updated"

    $invalid = Invoke-GlassIpc @{ action = "glass-setting"; category = "max_connections"; queue = "99999" }
    if ($invalid.code -ne "invalid-setting") { throw "Invalid connection limit was not rejected" }
    Write-Host "PASS: invalid settings rejected"
    Write-Host "Runtime smoke test PASSED"
}
finally {
    if ($proc -and !$proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $proc.WaitForExit(5000) | Out-Null
    }
    Remove-Item Env:MDM_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:MDM_GLASS_HEADLESS -ErrorAction SilentlyContinue
    Remove-Item Env:MDM_REMOTE -ErrorAction SilentlyContinue
}
