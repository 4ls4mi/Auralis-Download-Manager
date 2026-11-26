# Package a Store-edition staging directory. No certificates or Store credentials needed.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StageDirectory,
    [Parameter(Mandatory)][string]$IdentityName,
    [Parameter(Mandatory)][string]$Publisher,
    [Parameter(Mandatory)][string]$PublisherDisplayName,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DisplayName = 'Auralis Download Manager',
    [string]$MakeAppx
)
$ErrorActionPreference = 'Stop'
if ($IdentityName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') { throw 'Use the exact Package/Identity/Name from Partner Center.' }
if ($Publisher -notmatch '^CN=\S' -or [string]::IsNullOrWhiteSpace($PublisherDisplayName)) { throw 'Use the exact publisher identity and display name from Partner Center.' }
$stage = (Resolve-Path -LiteralPath $StageDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $output -ieq $stage) {
    throw 'The output directory must be outside the input payload.'
}
$metadata = Get-Content -LiteralPath (Join-Path $stage 'auralis-distribution.json') -Raw | ConvertFrom-Json
if ($metadata.edition -ne 'microsoft-store' -or $metadata.architecture -ne 'x64' -or $metadata.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Build a fresh payload using build-windows.ps1 -StoreEdition -StageOnly first.'
}
$version = [version]"$($metadata.version).0"
if (@($version.Major, $version.Minor, $version.Build) | Where-Object { $_ -gt 65535 }) { throw 'MSIX version components must be at most 65535.' }
foreach ($file in @('auralis-download-manager.exe','auralis_engine.dll','auralis-browser-host.exe','Qt6Core.dll','platforms/qwindows.dll','LICENSE.txt','THIRD-PARTY.txt')) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) { throw "Missing payload file: $file" }
}
if (Test-Path -LiteralPath (Join-Path $stage 'interface-fonts')) { throw 'Review additional font redistribution terms before including fonts in a Store package.' }
if (Get-ChildItem -LiteralPath $stage -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
    throw 'The package input must not contain symlinks or junctions.'
}
if (!$MakeAppx) {
    $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $MakeAppx = Get-ChildItem -LiteralPath $sdk -Directory | Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } |
        Sort-Object { [version]$_.Name } -Descending | ForEach-Object { Join-Path $_.FullName 'x64/makeappx.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (!$MakeAppx -or !(Test-Path -LiteralPath $MakeAppx -PathType Leaf)) { throw 'Install the Windows SDK MSIX packaging tools (MakeAppx.exe).' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
$package = Join-Path $output "Auralis.Download.Manager_$($version)_x64.msix"
if (Test-Path -LiteralPath $package) { throw "Refusing to overwrite $package" }
$work = Join-Path $output ('msix-stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Get-ChildItem -LiteralPath $stage -Force | Copy-Item -Destination $work -Recurse
foreach ($name in @('auralis-chrome-approval.exe','uninstall.exe','auralis-distribution.json')) {
    $item = Join-Path $work $name
    if (Test-Path -LiteralPath $item) { Remove-Item -LiteralPath $item }
}
$assets = Join-Path $work 'StoreAssets'
New-Item -ItemType Directory -Path $assets | Out-Null
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Image]::FromFile((Join-Path $PSScriptRoot '../assets/auralis.png'))
try {
    foreach ($entry in @(@('Square44x44Logo.png',44), @('Square150x150Logo.png',150), @('StoreLogo.png',50))) {
        $size = [int]$entry[1]
        $bitmap = [Drawing.Bitmap]::new($size,$size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $ratio = [Math]::Min(($size * 0.8) / $source.Width, ($size * 0.8) / $source.Height)
            $width = [int]($source.Width * $ratio); $height = [int]($source.Height * $ratio)
            $graphics.DrawImage($source, [int](($size-$width)/2), [int](($size-$height)/2), $width, $height)
            $bitmap.Save((Join-Path $assets $entry[0]), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $source.Dispose() }
function Escape-Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
$identityXml = Escape-Xml $IdentityName
$publisherXml = Escape-Xml $Publisher
$publisherDisplayXml = Escape-Xml $PublisherDisplayName
$displayXml = Escape-Xml $DisplayName
# Windows 11 allows precise browser/profile exclusions rather than disabling
# registry/AppData virtualization across the user's entire account.
$hostName = 'com.misterdownloadmanager.host'
$keys = @('Software\Google\Chrome\NativeMessagingHosts','Software\Microsoft\Edge\NativeMessagingHosts',
    'Software\Chromium\NativeMessagingHosts','Software\BraveSoftware\Brave-Browser\NativeMessagingHosts','Software\Mozilla\NativeMessagingHosts')
$excludedKeys = ($keys | ForEach-Object { "<virtualization:ExcludedKey>HKEY_CURRENT_USER\$_\$hostName</virtualization:ExcludedKey>" }) -join "`n"
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
 xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
 xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
 xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 xmlns:virtualization="http://schemas.microsoft.com/appx/manifest/virtualization/windows10"
 IgnorableNamespaces="uap uap10 desktop rescap virtualization">
 <Identity Name="$identityXml" Publisher="$publisherXml" Version="$version" ProcessorArchitecture="x64" />
 <Properties>
  <DisplayName>$displayXml</DisplayName><PublisherDisplayName>$publisherDisplayXml</PublisherDisplayName>
  <Logo>StoreAssets\StoreLogo.png</Logo>
  <virtualization:RegistryWriteVirtualization><virtualization:ExcludedKeys>
   $excludedKeys
  </virtualization:ExcludedKeys></virtualization:RegistryWriteVirtualization>
  <virtualization:FileSystemWriteVirtualization><virtualization:ExcludedDirectories>
   <virtualization:ExcludedDirectory>`$(KnownFolder:LocalAppData)\MisterHybridGlass\NativeMessaging</virtualization:ExcludedDirectory>
   <virtualization:ExcludedDirectory>`$(KnownFolder:RoamingAppData)\misterdownloadmanager</virtualization:ExcludedDirectory>
  </virtualization:ExcludedDirectories></virtualization:FileSystemWriteVirtualization>
 </Properties>
 <Resources><Resource Language="en-US" /></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22000.0" MaxVersionTested="10.0.26100.0" /></Dependencies>
 <Applications><Application Id="Auralis" Executable="auralis-download-manager.exe" EntryPoint="Windows.FullTrustApplication">
  <uap:VisualElements DisplayName="$displayXml" Description="Download manager with browser integration and customizable transfer displays"
   BackgroundColor="transparent" Square44x44Logo="StoreAssets\Square44x44Logo.png" Square150x150Logo="StoreAssets\Square150x150Logo.png" />
  <Extensions><desktop:Extension Category="windows.startupTask" uap10:Parameters="--auralis-store-startup" Executable="auralis-download-manager.exe" EntryPoint="Windows.FullTrustApplication">
   <desktop:StartupTask TaskId="AuralisStartup" Enabled="false" DisplayName="$displayXml" />
  </desktop:Extension></Extensions>
 </Application></Applications>
 <Capabilities><rescap:Capability Name="runFullTrust" /><rescap:Capability Name="unvirtualizedResources" /></Capabilities>
</Package>
"@
$manifest | Set-Content -LiteralPath (Join-Path $work 'AppxManifest.xml') -Encoding utf8
& $MakeAppx pack /d $work /p $package
if ($LASTEXITCODE -ne 0) { throw "MakeAppx validation/packaging failed ($LASTEXITCODE). Staging kept at $work" }
$digest = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $([IO.Path]::GetFileName($package))" | Set-Content -LiteralPath "$package.sha256" -Encoding ascii
if ($env:GITHUB_ENV) { "AURALIS_STORE_PACKAGE=$package" >> $env:GITHUB_ENV }
Write-Output $package
