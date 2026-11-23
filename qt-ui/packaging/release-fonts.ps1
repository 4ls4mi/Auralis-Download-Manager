# Keep these names in step with the application font catalog in Typography.cpp.
function Get-AuralisReleaseFontNames {
    @(
        'talina-demo.font', 'milkyway.font', 'mochi-boom-demo.font', 'qilka.font', 'qurova-demo.font',
        'kidzhood-arabic-demo.font', 'tinta-arabic.font', 'madani-arabic-demo.font',
        'mahameru-arabic-demo.font', 'gumela-arabic-demo.font', 'tufuli-arabic-demo.font',
        'lutfey-arabic-demo.font'
    )
}

function Expand-AuralisReleaseFonts([string]$BundlePath, [string]$Destination, [string]$EncodedKey) {
    $key = $null
    $plaintext = $null
    $createdDestination = $false
    $finished = $false
    $headerSize = 32
    $maximumBundleBytes = 64MB
    $maximumFontBytes = 16MB
    try {
        if (!$EncodedKey) { throw 'The release font encryption key is missing.' }
        try { $key = [Convert]::FromBase64String($EncodedKey) }
        catch { throw 'The release font encryption key must be base64.' }
        finally { $EncodedKey = $null }
        if ($key.Length -ne 32) { throw 'The release font encryption key must be 32 bytes.' }

        $file = Get-Item -LiteralPath $BundlePath
        if ($file -isnot [IO.FileInfo] -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The encrypted release font bundle must be a regular file.'
        }
        $bundle = [IO.BinaryReader]::new([IO.File]::OpenRead($file.FullName))
        try {
            $size = $bundle.BaseStream.Length
            if ($size -le $headerSize -or $size -gt $maximumBundleBytes -or
                [Text.Encoding]::ASCII.GetString($bundle.ReadBytes(4)) -cne 'AFB1') {
                throw 'The encrypted release font bundle has an invalid header or size.'
            }
            $nonce = $bundle.ReadBytes(12)
            $tag = $bundle.ReadBytes(16)
            $ciphertext = $bundle.ReadBytes([int]($size - $headerSize))
        } finally { $bundle.Dispose() }

        $plaintext = [byte[]]::new($ciphertext.Length)
        $aes = [Security.Cryptography.AesGcm]::new($key)
        try { $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext, $null) }
        catch { throw 'Could not authenticate the release font bundle.' }
        finally { $aes.Dispose() }

        $expected = @(Get-AuralisReleaseFontNames)
        $stream = [IO.MemoryStream]::new($plaintext, $false)
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
            try {
                if ($archive.Entries.Count -ne $expected.Count) {
                    throw 'The release font bundle must contain exactly the catalog font files.'
                }
                $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $total = 0L
                foreach ($entry in $archive.Entries) {
                    $unixType = ($entry.ExternalAttributes -shr 16) -band 0xf000
                    if ($expected -cnotcontains $entry.FullName -or !$seen.Add($entry.FullName) -or
                        ($unixType -ne 0 -and $unixType -ne 0x8000) -or
                        ($entry.ExternalAttributes -band [int]([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -or
                        $entry.Length -lt 12 -or $entry.Length -gt $maximumFontBytes) {
                        throw 'The release font bundle contains an invalid or duplicate font entry.'
                    }
                    $total += $entry.Length
                    if ($total -gt $maximumBundleBytes) { throw 'The release font bundle expands beyond its size limit.' }
                }

                if (Test-Path -LiteralPath $Destination) { throw 'The release font staging folder already exists.' }
                New-Item -ItemType Directory -Path $Destination | Out-Null
                $createdDestination = $true
                foreach ($name in $expected) {
                    $entry = $archive.GetEntry($name)
                    $reader = [IO.BinaryReader]::new($entry.Open())
                    try {
                        $bytes = $reader.ReadBytes([int]$entry.Length)
                        if ($bytes.Length -ne $entry.Length -or $reader.BaseStream.ReadByte() -ne -1) {
                            throw 'A release font decompresses to a different size than declared.'
                        }
                        $isSingleFace = [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ceq 'OTTO' -or
                            ($bytes[0] -eq 0 -and $bytes[1] -eq 1 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0)
                        $tables = (([int]$bytes[4]) -shl 8) -bor $bytes[5]
                        if (!$isSingleFace -or $tables -lt 1 -or (12 + 16 * $tables) -gt $bytes.Length) {
                            throw 'A release font is not a valid single-face TTF or OTF file.'
                        }
                        [IO.File]::WriteAllBytes((Join-Path $Destination $name), $bytes)
                    } finally { $reader.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
        $finished = $true
    } finally {
        if ($key) { [Array]::Clear($key, 0, $key.Length) }
        if ($plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
        if (!$finished -and $createdDestination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    }
}
