[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$HuggingFaceHome
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $PSScriptRoot 'docling-huggingface-models.zip'
}

if ([string]::IsNullOrWhiteSpace($HuggingFaceHome)) {
    $HuggingFaceHome = if ($env:HF_HOME) { $env:HF_HOME } else { Join-Path $env:USERPROFILE '.cache\huggingface' }
}

$archiveFullPath = [IO.Path]::GetFullPath($ArchivePath)
if (-not (Test-Path -LiteralPath $archiveFullPath -PathType Leaf)) {
    throw "Model archive not found: $archiveFullPath"
}

$destinationRoot = [IO.Path]::GetFullPath($HuggingFaceHome).TrimEnd('\', '/')
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [IO.Compression.ZipFile]::OpenRead($archiveFullPath)
try {
    $manifestEntry = $zip.GetEntry('manifest.json')
    if (-not $manifestEntry) { throw 'Archive has no manifest.json.' }
    $reader = [IO.StreamReader]::new($manifestEntry.Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }
    if ($manifest.format -ne 'docling-huggingface-cache' -or $manifest.version -ne 1) {
        throw 'Archive is not a supported Docling Hugging Face cache bundle.'
    }

    $fileEntries = @($zip.Entries | Where-Object { $_.FullName -ne 'manifest.json' -and $_.Name })
    foreach ($entry in $fileEntries) {
        $relativePath = $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not $relativePath.StartsWith("hub$([IO.Path]::DirectorySeparatorChar)models--", [StringComparison]::Ordinal)) {
            throw "Unsafe or unexpected archive entry: $($entry.FullName)"
        }

        $destination = [IO.Path]::GetFullPath((Join-Path $destinationRoot $relativePath))
        if (-not $destination.StartsWith("$destinationRoot$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Archive entry escapes the cache directory: $($entry.FullName)"
        }

        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $inputStream = $entry.Open()
        $outputStream = [IO.File]::Open($destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $inputStream.CopyTo($outputStream) }
        finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    }
}
finally { $zip.Dispose() }

$env:HF_HOME = $destinationRoot
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
Write-Host "Restored $($fileEntries.Count) cache files to $destinationRoot" -ForegroundColor Green
Write-Host 'Docling can now run with Hugging Face network access disabled.'
