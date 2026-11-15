# Windows-only visual regression check for Plexo glass.
# Captures the *real* compiled app with and without a bright local wallpaper,
# then checks that the selected image materially changes rendered pixels.
param(
    [Parameter(Mandatory)][string]$Exe,
    [string]$Output = "target\qa"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$Exe = (Resolve-Path $Exe).Path
$root = (Resolve-Path ".").Path
$qa = Join-Path $root $Output
New-Item -ItemType Directory -Force $qa | Out-Null
$photo = Join-Path $qa "colorful-test-wallpaper.png"

# A deterministic, high-contrast synthetic wallpaper. No network or copyrighted assets.
$bmp = New-Object System.Drawing.Bitmap(960, 540)
$g = [System.Drawing.Graphics]::FromImage($bmp)
try {
    for ($y = 0; $y -lt 540; $y += 3) {
        $f = $y / 540.0
        $color = [System.Drawing.Color]::FromArgb(255,
            [int](38 + 182 * $f), [int](185 - 60 * $f), [int](215 - 130 * $f))
        $brush = New-Object System.Drawing.SolidBrush($color)
        try { $g.FillRectangle($brush, 0, $y, 960, 3) }
        finally { $brush.Dispose() }
    }
    $amber = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 250, 194, 85))
    try { $g.FillEllipse($amber, 570, 75, 260, 260) }
    finally { $amber.Dispose() }
    $bmp.Save($photo, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $g.Dispose()
    $bmp.Dispose()
}
function Capture([string]$name, [string]$wallpaper) {
    $data = Join-Path $qa "data-$name"
    New-Item -ItemType Directory -Force $data | Out-Null
    $settings = @{
        theme = "plexo"
        always_dark = $true
        dark_mode_support = $true
        wallpaper_main = $wallpaper
        wallpaper_dim = 10
        wallpaper_blur = 2
        wallpaper_glass = 52
        language = "en"
        language_asked = $true
        helpers_asked = $true
        extension_never_ask = $true
        update_check = $false
    }
    $json = @{ next_id=1; items=@(); version=2; settings=$settings } |
        ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $data "downloads.json"), $json,
        (New-Object System.Text.UTF8Encoding($false)))
    $env:MDM_OFFSCREEN = "1"
    $env:MDM_OFFSCREEN_AT = "40,40"
    $env:MDM_DATA_DIR = $data
    $env:GALLIUM_DRIVER = "llvmpipe"
    $proc = Start-Process -PassThru -FilePath $Exe
    $outputFile = Join-Path $qa "$name.png"
    try {
        for ($n = 0; $n -lt 22; $n++) {
            Start-Sleep -Milliseconds 900
            try {
                & "$root\tools\lab\cap-own.ps1" -ProcessId $proc.Id -Title "Mister Download Manager" -Out $outputFile | Out-Null
                if ((Test-Path $outputFile) -and ((Get-Item $outputFile).Length -gt 15000)) { break }
            } catch {}
        }
        if (!(Test-Path $outputFile)) { throw "Cannot capture the $name window" }
    } finally {
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
        Start-Sleep -Milliseconds 700
    }
    return $outputFile
}
$noWallpaper = Capture "glass-no-wallpaper" ""
$withWallpaper = Capture "glass-with-wallpaper" $photo
$a = [System.Drawing.Bitmap]::FromFile($noWallpaper)
$b = [System.Drawing.Bitmap]::FromFile($withWallpaper)
try {
    if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) {
        throw "Screenshot dimensions differ unexpectedly"
    }
    $sum = 0.0; $count = 0
    $startX = [int]($a.Width * 0.36); $endX = [int]($a.Width * 0.90)
    $startY = [int]($a.Height * 0.34); $endY = [int]($a.Height * 0.74)
    for ($y = $startY; $y -lt $endY; $y += 8) {
        for ($x = $startX; $x -lt $endX; $x += 8) {
            $c = $a.GetPixel($x, $y)
            $d = $b.GetPixel($x, $y)
            $sum += ([Math]::Abs([int]$c.R - [int]$d.R) +
                [Math]::Abs([int]$c.G - [int]$d.G) +
                [Math]::Abs([int]$c.B - [int]$d.B)) / 3.0
            $count++
        }
    }
    $difference = $sum / [Math]::Max($count, 1)
    "Mean visible wallpaper difference: $([Math]::Round($difference, 2)) levels/pixel"
    if ($difference -lt 8) {
        throw "Wallpaper visibility regression: selecting an image barely changed the rendered window"
    }
    "PASS: selecting an image changed the displayed application."
} finally {
    $a.Dispose(); $b.Dispose()
}
