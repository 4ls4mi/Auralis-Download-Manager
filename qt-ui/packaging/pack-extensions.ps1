$ErrorActionPreference = 'Stop'
$source = Join-Path (Resolve-Path "$PSScriptRoot/../..").Path 'auralis-extension'
foreach ($name in @('background.js','popup.js','appearance.js','appearance-profile.js','companion-appearance.js','video.js','thumbnail.js')) {
    node --check (Join-Path $source $name)
    if ($LASTEXITCODE -ne 0) { throw "Invalid extension script: $name" }
}
$copies = Join-Path $env:AURALIS_QT_JOB 'extension-staging'
$packages = Join-Path $env:AURALIS_QT_JOB 'extensions'
New-Item -ItemType Directory -Force -Path $copies, $packages | Out-Null
foreach ($browser in @('chromium','edge-store','firefox')) {
    $folder = Join-Path $copies $browser
    Copy-Item -LiteralPath $source -Destination $folder -Recurse
    $manifest = Join-Path $folder 'manifest.json'
    if ($browser -eq 'edge-store') {
        $json = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        $json.PSObject.Properties.Remove('key')
        $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifest -Encoding utf8
    } elseif ($browser -eq 'firefox') {
        Copy-Item -LiteralPath (Join-Path $folder 'manifest.firefox.json') -Destination $manifest -Force
    }
    Compress-Archive -Path (Join-Path $folder '*') -DestinationPath (Join-Path $packages "auralis-$browser.zip")
}
# Both stores assign the extension identity, so they use the same key-free Chromium package.
Copy-Item -LiteralPath (Join-Path $packages 'auralis-edge-store.zip') -Destination (Join-Path $packages 'auralis-chrome-store.zip')
"AURALIS_QT_EXTENSIONS=$packages" >> $env:GITHUB_ENV
