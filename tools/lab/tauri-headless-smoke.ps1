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
        if ($line -eq "ok") { return @{ accepted = $true } }
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
    $complete = Invoke-GlassIpc @{ action = "glass-setting"; category = "show_complete"; queue = "true" }
    if ($complete.saved -ne $true) { throw "Completion dialog preference rejected" }
    $readback = Invoke-GlassIpc @{ query = "glass-settings" }
    if ($readback.show_complete -ne $true) { throw "Completion preference did not persist to live backend" }
    $pending = Invoke-GlassIpc @{ query = "glass-file-info" }
    if ($pending.info) { throw "Fresh isolated backend unexpectedly has a pending capture" }
    Write-Host "PASS: completion setting and authenticated original FileInfo queue"
    $catalog = Invoke-GlassIpc @{ query = 'glass-original-settings' }
    if ($catalog.fields.Count -lt 50) { throw 'Original preference catalog is incomplete' }
    $proxySecret = 'local-fixture-proxy-secret'
    $set = Invoke-GlassIpc @{ action = 'glass-original-setting'; queue = (@{ key = 'proxy_pass'; value = $proxySecret } | ConvertTo-Json -Compress) }
    if ($set.ok -ne $true) { throw 'Proxy secret update failed' }
    $safe = Invoke-GlassIpc @{ query = 'glass-original-settings' }
    if (($safe | ConvertTo-Json -Depth 15).Contains($proxySecret)) { throw 'Preference query exposed a stored password' }
    $set = Invoke-GlassIpc @{ action = 'glass-original-setting'; queue = (@{ key = 'proxy_pass'; value = ''; clear = $true } | ConvertTo-Json -Compress) }
    if ($set.ok -ne $true) { throw 'Proxy secret clear failed' }
    $bad = Invoke-GlassIpc @{ action = 'glass-original-setting'; queue = (@{ key = 'proxy_mode'; value = 99 } | ConvertTo-Json -Compress) }
    if (-not $bad.error) { throw 'Invalid original proxy mode accepted' }
    Write-Host 'PASS: typed original preferences validate changes and never return stored passwords'
    $batch = Invoke-GlassIpc @{ action = 'glass-batch'; queue = (@{ address = 'https://example.com/file*.zip'; from = '1'; to = '8'; width = '2'; commit = $false } | ConvertTo-Json -Compress) }
    if ($batch.count -ne 8 -or $batch.preview[0] -ne 'https://example.com/file01.zip') { throw 'Original batch parser did not expand a numbered pattern' }
    $queues = Invoke-GlassIpc @{ query = 'glass-queues' }
    $queue = $queues.queues[0]
    $schedule = Invoke-GlassIpc @{ action = 'glass-schedule'; queue = (@{ name = $queue.name; schedule = $queue.schedule; files_at_once = 3 } | ConvertTo-Json -Depth 15 -Compress) }
    if ($schedule.ok -ne $true) { throw 'Original schedule update failed' }
    $queues = Invoke-GlassIpc @{ query = 'glass-queues' }
    if ($queues.queues[0].files_at_once -ne 3) { throw 'Original queue parallelism did not update' }
    Write-Host 'PASS: original batch pattern parser and queue schedule roundtrip'
    $batch = Invoke-GlassIpc @{ action = 'glass-batch'; queue = (@{ address = 'http://127.0.0.1:1/glass-smoke-*.zip'; from = '1'; to = '2'; width = '1'; commit = $true } | ConvertTo-Json -Compress) }
    if ($batch.ok -ne $true) { throw 'Batch queue commit failed' }
    $prompts = Invoke-GlassIpc @{ query = 'glass-prompts' }
    if (-not $prompts.queue -or $prompts.queue.count -ne 2) { throw 'Original Download Later queue panel was not exposed' }
    $stale = Invoke-GlassIpc @{ action = 'glass-prompt'; queue = (@{ kind = 'queue'; lease = $prompts.queue.lease + 99; cancel = $true } | ConvertTo-Json -Compress) }
    if (-not $stale.error) { throw 'A stale queue window answered a newer request' }
    $chosen = Invoke-GlassIpc @{ action = 'glass-prompt'; queue = (@{ kind = 'queue'; lease = $prompts.queue.lease; name = $queue.name; start = $false } | ConvertTo-Json -Compress) }
    if ($chosen.ok -ne $true) { throw 'Original queue choice was not applied' }
    $visuals = Invoke-GlassIpc @{ query = 'glass-visuals' }
    if ($visuals.downloads.Count -ne 2 -or $visuals.downloads[0].chunk_count -ne 7) { throw 'Per-download connection choice was not captured' }
    $set = Invoke-GlassIpc @{ action = 'glass-setting'; category = 'max_connections'; queue = '32' }
    $visuals = Invoke-GlassIpc @{ query = 'glass-visuals' }
    if ($visuals.downloads[0].chunk_count -ne 7) { throw 'Global limit overwrote an existing download choice' }
    $capture = Invoke-GlassIpc @{ url = 'http://127.0.0.1:1/glass-smoke-1.zip' }
    $prompts = Invoke-GlassIpc @{ query = 'glass-prompts' }
    if (-not $prompts.duplicate) { throw 'Original duplicate decision was not exposed' }
    $cancel = Invoke-GlassIpc @{ action = 'glass-prompt'; queue = (@{ kind = 'duplicate'; lease = $prompts.duplicate.lease; cancel = $true } | ConvertTo-Json -Compress) }
    if ($cancel.ok -ne $true) { throw 'Duplicate cancellation failed' }
    Write-Host 'PASS: original queue/duplicate prompts use request leases; selected chunk counts survive global changes'
    $exit = Invoke-GlassIpc @{ exit = $true }
    if (-not $proc.WaitForExit(15000)) { throw 'Backend did not save and exit' }
    $proc = Start-Process -FilePath $Backend -ArgumentList '--headless' -PassThru
    $persisted = $null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 300
        try { $persisted = Invoke-GlassIpc @{ query = 'glass-visuals' }; if ($persisted.downloads.Count -eq 2) { break } } catch {}
    }
    if (-not $persisted -or $persisted.downloads[0].chunk_count -ne 7) { throw 'Selected chunks were not restored from MDM storage' }
    Write-Host 'PASS: selected per-download chunk counts persist across an original backend restart'
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
