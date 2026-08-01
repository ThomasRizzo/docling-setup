[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$HuggingFaceHome,
    [string[]]$ModelPatterns = @('models--docling-project--*')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $PSScriptRoot 'docling-huggingface-models.zip'
}

if ([string]::IsNullOrWhiteSpace($HuggingFaceHome)) {
    $HuggingFaceHome = if ($env:HF_HOME) { $env:HF_HOME } else { Join-Path $env:USERPROFILE '.cache\huggingface' }
}

$hubDirectory = Join-Path $HuggingFaceHome 'hub'
if (-not (Test-Path -LiteralPath $hubDirectory -PathType Container)) {
    throw "Hugging Face hub cache not found: $hubDirectory"
}

$modelDirectories = @(
    foreach ($pattern in $ModelPatterns) {
        Get-ChildItem -LiteralPath $hubDirectory -Directory -Filter $pattern
    }
) | Sort-Object FullName -Unique

if ($modelDirectories.Count -eq 0) {
    throw "No cached models matched: $($ModelPatterns -join ', ')"
}

$archiveFullPath = [IO.Path]::GetFullPath($ArchivePath)
$archiveParent = Split-Path -Parent $archiveFullPath
New-Item -ItemType Directory -Path $archiveParent -Force | Out-Null
$temporaryArchive = "$archiveFullPath.partial"
if (Test-Path -LiteralPath $temporaryArchive) {
    Remove-Item -LiteralPath $temporaryArchive -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$manifestModels = @()
$archiveStream = [IO.File]::Open($temporaryArchive, [IO.FileMode]::CreateNew)
try {
    $zip = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($modelDirectory in $modelDirectories) {
            $files = @(Get-ChildItem -LiteralPath $modelDirectory.FullName -Recurse -File)
            $modelBytes = [long](($files | Measure-Object Length -Sum).Sum)
            $manifestModels += [ordered]@{
                name = $modelDirectory.Name
                files = $files.Count
                bytes = $modelBytes
            }

            Write-Host "Packing $($modelDirectory.Name) ($($files.Count) files)..." -ForegroundColor Cyan
            foreach ($file in $files) {
                $relativeFile = $file.FullName.Substring($modelDirectory.FullName.Length).TrimStart('\', '/')
                $entryName = "hub/$($modelDirectory.Name)/$($relativeFile.Replace('\', '/'))"
                $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
                $entryStream = $entry.Open()
                $inputStream = $file.OpenRead()
                try { $inputStream.CopyTo($entryStream) }
                finally {
                    $inputStream.Dispose()
                    $entryStream.Dispose()
                }
            }
        }

        $manifest = [ordered]@{
            format = 'docling-huggingface-cache'
            version = 1
            created_utc = [DateTime]::UtcNow.ToString('o')
            models = $manifestModels
        } | ConvertTo-Json -Depth 5
        $manifestEntry = $zip.CreateEntry('manifest.json', [IO.Compression.CompressionLevel]::Optimal)
        $writer = [IO.StreamWriter]::new($manifestEntry.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($manifest) } finally { $writer.Dispose() }
    }
    finally { $zip.Dispose() }
}
finally { $archiveStream.Dispose() }

Move-Item -LiteralPath $temporaryArchive -Destination $archiveFullPath -Force
$archive = Get-Item -LiteralPath $archiveFullPath
Write-Host "`nPacked $($modelDirectories.Count) model cache(s)." -ForegroundColor Green
Write-Host "Archive: $($archive.FullName)"
Write-Host "Size: $([math]::Round($archive.Length / 1MB, 1)) MB"
