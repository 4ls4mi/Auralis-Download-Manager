# Test the distributable installer without touching the runner user's installation or data.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $env:AURALIS_QT_JOB 'smoke-install'
$data = Join-Path $env:AURALIS_QT_JOB 'smoke-data'
$exe = Join-Path $fixture 'auralis-download-manager.exe'
$marker = Join-Path $data 'qt-engine-smoke.ok'
$suiteStartedAt = Get-Date
$diagnosticsRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$diagnostics = Join-Path $diagnosticsRoot "auralis-qt-diagnostics-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
if ($env:GITHUB_ENV) { "AURALIS_QT_DIAGNOSTICS=$diagnostics" >> $env:GITHUB_ENV }
$previousData = $env:MDM_DATA_DIR
$previousDownloads = $env:MDM_DOWNLOADS
$previousSkipHost = $env:AURALIS_TEST_SKIP_HOST
$previousRenderer = $env:QSG_RHI_BACKEND
$previousQuickBackend = $env:QT_QUICK_BACKEND
$previousGraphicsInfo = $env:QSG_INFO
$env:MDM_DATA_DIR = $data
$env:MDM_DOWNLOADS = Join-Path $data 'downloads'
$env:AURALIS_TEST_SKIP_HOST = '1'
$env:QSG_INFO = '1'
# Exercise the default renderer with the legacy software option present.
$env:QSG_RHI_BACKEND = $null
$env:QT_QUICK_BACKEND = 'software'
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

function Run-Fixture([string]$Process, [string[]]$Arguments, [int]$Timeout = 180000, [int]$ExpectedExitCode = 0) {
    $startedAt = Get-Date
    $child = Start-Process -FilePath $Process -ArgumentList $Arguments -WorkingDirectory (Split-Path -Parent $Process) -PassThru
    if (!$child.WaitForExit($Timeout)) {
        Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        Write-FixtureDiagnostics $startedAt
        throw "Timed out waiting for $Process."
    }
    if ($child.ExitCode -ne $ExpectedExitCode) {
        Start-Sleep -Seconds 2
        Write-FixtureDiagnostics $startedAt
        throw "$Process exited with code $($child.ExitCode). Expected $ExpectedExitCode."
    }
}

function Test-InstalledIcon {
    $sourceIcon = Join-Path $PSScriptRoot '../assets/auralis.ico'
    $expected = (Get-FileHash -LiteralPath $sourceIcon -Algorithm SHA256).Hash
    $shortcutIcon = Join-Path $fixture ('auralis-taskbar-' + $expected.Substring(0, 12).ToLowerInvariant() + '.ico')
    if (!(Test-Path -LiteralPath $shortcutIcon) -or
        (Get-FileHash -LiteralPath $shortcutIcon -Algorithm SHA256).Hash -ne $expected) {
        throw 'The installed shortcut icon is missing or differs from the Auralis artwork.'
    }
    [AuralisSmokeIcon]::Verify($exe, $sourceIcon)
    Write-Host 'Verified the packaged shortcut icon and every native executable icon frame.'
}

function Test-PublisherMetadata {
    foreach ($file in @($exe, $env:AURALIS_QT_INSTALLER)) {
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($file)
        if ($info.CompanyName -ne 'Alsami') {
            throw "Publisher metadata is missing from $file."
        }
    }
    Write-Host 'Verified Alsami publisher metadata on the application and installer.'
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public static class AuralisSmokeIcon {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindResource(IntPtr module, IntPtr id, IntPtr type);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")]
    private static extern int SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);

    private static byte[] ReadResource(IntPtr module, int id, int type) {
        IntPtr resource = FindResource(module, (IntPtr)id, (IntPtr)type);
        if (resource == IntPtr.Zero) throw new InvalidDataException("Missing executable icon resource.");
        int size = SizeofResource(module, resource);
        IntPtr data = LockResource(LoadResource(module, resource));
        if (size <= 0 || data == IntPtr.Zero) throw new InvalidDataException("Invalid executable icon resource.");
        byte[] bytes = new byte[size];
        Marshal.Copy(data, bytes, 0, size);
        return bytes;
    }

    public static void Verify(string executable, string iconPath) {
        byte[] icon = File.ReadAllBytes(iconPath);
        int count = BitConverter.ToUInt16(icon, 4);
        var expected = new List<string>();
        for (int i = 0; i < count; ++i) {
            int entry = 6 + 16 * i;
            int size = BitConverter.ToInt32(icon, entry + 8);
            int offset = BitConverter.ToInt32(icon, entry + 12);
            expected.Add(Convert.ToHexString(SHA256.HashData(icon.AsSpan(offset, size))));
        }

        const uint readResourcesOnly = 0x00000022;
        IntPtr module = LoadLibraryEx(executable, IntPtr.Zero, readResourcesOnly);
        if (module == IntPtr.Zero) throw new InvalidDataException("Could not inspect the installed executable's resources.");
        try {
            const int groupIcon = 14;
            const int iconFrame = 3;
            byte[] group = ReadResource(module, 1, groupIcon);
            if (BitConverter.ToUInt16(group, 4) != count) throw new InvalidDataException("The embedded icon frame count differs.");
            for (int i = 0; i < count; ++i) {
                int frame = BitConverter.ToUInt16(group, 6 + 14 * i + 12);
                string digest = Convert.ToHexString(SHA256.HashData(ReadResource(module, frame, iconFrame)));
                if (!expected.Remove(digest)) throw new InvalidDataException("An executable icon frame differs from the Auralis artwork.");
            }
        } finally {
            FreeLibrary(module);
        }
    }
}
'@

try {
    # NSIS requires the unquoted /D= argument to come last.
    Run-Fixture $env:AURALIS_QT_INSTALLER @('/S', '/NOREG', "/D=$fixture")
    if (!(Test-Path $exe) -or !(Test-Path (Join-Path $fixture 'uninstall.exe'))) {
        throw 'The standalone Qt installation is incomplete.'
    }
    Test-InstalledIcon
    Test-PublisherMetadata
    $approvalHelper = Join-Path $fixture 'auralis-chrome-approval.exe'
    Run-Fixture $approvalHelper @('remove', 'invalid-account-sid', '0') -Timeout 10000 -ExpectedExitCode 2
    if ($env:AURALIS_QT_RELEASE_FONTS -eq '1') {
        $sourceFonts = Join-Path $env:AURALIS_QT_JOB 'payload/interface-fonts'
        $installedFonts = Join-Path $fixture 'interface-fonts'
        $expected = @(Get-ChildItem -LiteralPath $sourceFonts -File -Filter '*.font')
        if ($expected.Count -ne 12) { throw 'Expected twelve staged interface fonts.' }
        foreach ($font in $expected) {
            $installedPath = Join-Path $installedFonts $font.Name
            if ((Get-FileHash -LiteralPath $installedPath).Hash -ne (Get-FileHash -LiteralPath $font.FullName).Hash) {
                throw "Installed font differs from the packaged copy: $($font.Name)"
            }
        }
        Write-Host 'Verified all twelve embedded interface font files.'
    }
    Run-Fixture $exe @('--engine-smoke', '--device=software') 90000
    if (!(Test-Path $marker)) {
        throw 'The installed application exited without its transfer-integrity success marker. See the smoke diagnostics below.'
    }
    Get-Content -LiteralPath $marker | ForEach-Object { Write-Host $_ }
    $console = Join-Path $data 'qt-smoke-console.log'
    if (!(Test-Path -LiteralPath $console) -or
        !(Select-String -LiteralPath $console -SimpleMatch 'Smoke: using Direct3D 11.' -Quiet)) {
        throw 'The installed application did not select Direct3D 11 by default.'
    }

    # Exercise the in-app updater's NSIS arguments and wait for the installed app
    # to verify a loopback transfer again after the installer launches it.
    $upgradeArgs = @('/P', '/UPDATE', '/R', '/NOREG', '/ARGS=--engine-smoke', "/D=$fixture")
    Remove-Item -LiteralPath $marker, $console -Force -ErrorAction SilentlyContinue
    Write-Host 'Testing passive upgrade with the installed executable locked.'
    $uninstallMarker = Join-Path $data 'keep-after-blocked-uninstall.txt'
    Set-Content -LiteralPath $uninstallMarker -Value 'Uninstall must preserve this profile.'
    $locked = [IO.File]::Open($exe, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Write-Host 'Testing uninstall with the installed executable in use.'
        Run-Fixture (Join-Path $fixture 'uninstall.exe') @('/S', '/NOREG', "_?=$fixture") 20000 5
        if (!(Test-Path -LiteralPath $exe) -or
            !(Test-Path -LiteralPath (Join-Path $fixture 'auralis_engine.dll')) -or
            !(Test-Path -LiteralPath (Join-Path $fixture 'auralis-browser-host.exe')) -or
            !(Test-Path -LiteralPath $uninstallMarker) -or
            (Get-Content -LiteralPath $uninstallMarker -Raw).Trim() -ne 'Uninstall must preserve this profile.') {
            throw 'The rejected uninstall changed the installed application or its profile.'
        }
        Write-Host 'Verified uninstall refuses in-use files before removing the application.'
        Run-Fixture $env:AURALIS_QT_INSTALLER $upgradeArgs 20000 5
        $relaunch = Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -ieq $exe }
        if ($relaunch -or (Test-Path -LiteralPath $console) -or (Test-Path -LiteralPath $marker)) {
            throw 'The rejected passive upgrade relaunched the app while the installed executable was locked.'
        }
    } finally { $locked.Dispose() }
    Write-Host 'Verified the in-use installer exits without relaunching.'

    Remove-Item -LiteralPath $marker, $console -Force -ErrorAction SilentlyContinue
    Write-Host 'Testing passive upgrade and relaunch after releasing the executable.'
    $upgradedAt = Get-Date
    Run-Fixture $env:AURALIS_QT_INSTALLER $upgradeArgs
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (!(Test-Path $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (!(Test-Path $marker)) {
        Write-FixtureDiagnostics $upgradedAt
        throw 'The passive update did not relaunch a working installed app.'
    }

    Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $exe } | Wait-Process -Timeout 10

    # A silent uninstall keeps custom profiles, portable data and user-created files.
    $ownedByUser = Join-Path $fixture 'keep-after-uninstall.txt'
    $portableData = Join-Path $fixture 'data'
    $portableMarker = Join-Path $portableData 'keep-portable-data.txt'
    Set-Content -LiteralPath $ownedByUser -Value 'User file'
    New-Item -ItemType Directory -Path $portableData -Force | Out-Null
    Set-Content -LiteralPath $portableMarker -Value 'Portable data'
    Run-Fixture (Join-Path $fixture 'uninstall.exe') @('/S', '/NOREG')
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Test-Path $exe) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if ((Test-Path $exe) -or !(Test-Path $ownedByUser) -or !(Test-Path $portableMarker) -or !(Test-Path $marker)) {
        throw 'The uninstaller did not remove only the packaged application files.'
    }
    Write-Host 'Verified silent install, native icons, Direct3D 11 rendering during start and resume, passive upgrade relaunch, and scoped uninstallation.'
} catch {
    # A zero exit code without a marker is also a failure. Print diagnostics for
    # all assertion failures before cleanup removes the isolated test profile.
    $verificationFailure = $_
    try {
        Write-FixtureDiagnostics $suiteStartedAt
        New-Item -ItemType Directory -Force -Path $diagnostics | Out-Null
        $console = Join-Path $data 'qt-smoke-console.log'
        if (Test-Path -LiteralPath $console) {
            Copy-Item -LiteralPath $console -Destination (Join-Path $diagnostics 'qt-smoke-console.log')
        }
        @("Verification failure: $($verificationFailure.Exception.Message)",
          "Expected marker: $marker", "Installed executable: $exe") |
            Set-Content -LiteralPath (Join-Path $diagnostics 'verification-failure.txt') -Encoding utf8
    } catch {
        Write-Warning "Could not preserve all smoke diagnostics: $($_.Exception.Message)"
    }
    throw $verificationFailure
} finally {
    Get-Process -Name 'auralis-download-manager' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $exe } | Stop-Process -Force -ErrorAction SilentlyContinue
    # NSIS can finish removing temporary files while this cleanup walks the tree.
    # Cleanup must not replace a verification failure or turn a passing test red.
    foreach ($temporaryDirectory in @($fixture, $data)) {
        try {
            if (Test-Path -LiteralPath $temporaryDirectory) {
                Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction Stop
            }
        } catch {
            Write-Warning "Temporary test cleanup was incomplete: $($_.Exception.Message)"
        }
    }
    $env:MDM_DATA_DIR = $previousData
    $env:MDM_DOWNLOADS = $previousDownloads
    $env:AURALIS_TEST_SKIP_HOST = $previousSkipHost
    $env:QSG_RHI_BACKEND = $previousRenderer
    $env:QT_QUICK_BACKEND = $previousQuickBackend
    $env:QSG_INFO = $previousGraphicsInfo
}
