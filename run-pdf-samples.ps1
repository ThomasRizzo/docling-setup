[CmdletBinding()]
param(
    [string]$OcrLanguage = 'eng',
    [string]$OutputDirectory,
    [string]$FileName = '*.pdf',
    [ValidateRange(1, 64)]
    [int]$PageBatchSize = 1,
    [ValidateRange(1, 64)]
    [int]$NumThreads = 1,
    [ValidateSet('pypdfium2', 'docling_parse', 'threaded_docling_parse', 'dlparse_v1', 'dlparse_v2', 'dlparse_v4')]
    [string]$PdfBackend = 'pypdfium2',
    [ValidateSet('placeholder', 'embedded', 'referenced')]
    [string]$ImageExportMode = 'referenced',
    [switch]$AllowHuggingFaceNetwork
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'output'
}

$docling = Join-Path $PSScriptRoot '.venv\Scripts\docling.exe'
$sampleDirectory = Join-Path $PSScriptRoot 'pdf-samples'
$tesseractDirectory = Join-Path $env:ProgramFiles 'Tesseract-OCR'
$tesseract = Join-Path $tesseractDirectory 'tesseract.exe'
$tessdata = Join-Path $tesseractDirectory 'tessdata'

if (-not (Test-Path -LiteralPath $docling)) {
    throw 'Docling is not installed. Run .\setup-docling.ps1 first.'
}
if (-not (Test-Path -LiteralPath $tesseract)) {
    throw 'Tesseract is not installed. Run .\setup-docling.ps1 first.'
}
if (-not (Test-Path -LiteralPath $sampleDirectory)) {
    throw "PDF sample directory not found: $sampleDirectory"
}

$pdfs = @(Get-ChildItem -LiteralPath $sampleDirectory -Filter $FileName -File | Sort-Object Name)
if ($pdfs.Count -eq 0) {
    throw "No PDF files matching '$FileName' found in $sampleDirectory."
}

# Docling expects TESSDATA_PREFIX to include a trailing slash.
$env:PATH = "$tesseractDirectory;$env:PATH"
$env:TESSDATA_PREFIX = "$($tessdata.TrimEnd('\', '/'))/"
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = '1'
if (-not $AllowHuggingFaceNetwork) {
    $env:HF_HUB_OFFLINE = '1'
    $env:TRANSFORMERS_OFFLINE = '1'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path

Write-Host "Processing $($pdfs.Count) PDF(s) with Tesseract ($OcrLanguage), batch size $PageBatchSize, $NumThreads thread(s)..." -ForegroundColor Cyan
foreach ($pdf in $pdfs) {
    Write-Host "`n==> $($pdf.Name)" -ForegroundColor Yellow
    & $docling convert $pdf.FullName `
        --from pdf `
        --to md `
        --image-export-mode $ImageExportMode `
        --output $resolvedOutput `
        --ocr `
        --ocr-engine tesseract `
        --ocr-lang $OcrLanguage `
        --page-batch-size $PageBatchSize `
        --num-threads $NumThreads `
        --pdf-backend $PdfBackend `
        --device cpu

    if ($LASTEXITCODE -ne 0) {
        throw "Docling failed for $($pdf.FullName) with exit code $LASTEXITCODE."
    }
}

Write-Host "`nDone. Markdown output: $resolvedOutput" -ForegroundColor Green
