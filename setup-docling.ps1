[CmdletBinding()]
param(
    [switch]$ProcessSamples,
    [switch]$Upgrade,
    [ValidateSet('User', 'System')]
    [string]$TesseractInstallScope = 'User',
    [string]$TesseractInstallRoot = 'C:\Tools'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot
$venvPath = Join-Path $repoRoot '.venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
$venvDocling = Join-Path $venvPath 'Scripts\docling.exe'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Find-RealPython {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:ProgramFiles 'Python312\python.exe')
    )

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand -and $pythonCommand.Source -notlike '*\WindowsApps\*') {
        $candidates += $pythonCommand.Source
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            $version = & $candidate -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
            if ($version -eq '3.12') { return $candidate }
        }
    }
    return $null
}

function Find-Tesseract([string]$PreferredPath) {
    if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath)) { return $PreferredPath }

    $command = Get-Command tesseract.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Tesseract-OCR\tesseract.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tesseract-OCR\tesseract.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Tesseract-OCR\tesseract.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet is required. Install or update "App Installer" from the Microsoft Store, then rerun this script.'
}

if ($TesseractInstallScope -eq 'System') {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'System Tesseract installation requires an elevated PowerShell session (Run as administrator).'
    }
}

Write-Step 'Checking Python 3.12'
$python = Find-RealPython
if (-not $python) {
    winget install --id Python.Python.3.12 --exact --source winget --scope user --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Python installation failed with exit code $LASTEXITCODE." }
    $python = Find-RealPython
}
if (-not $python) { throw 'Python 3.12 was installed but could not be located. Open a new PowerShell window and rerun this script.' }
Write-Host "Python: $python"

Write-Step 'Checking Tesseract OCR'
$userTesseractDirectory = Join-Path $TesseractInstallRoot 'Tesseract-OCR'
$userTesseract = Join-Path $userTesseractDirectory 'tesseract.exe'
$preferredTesseract = if ($TesseractInstallScope -eq 'User') {
    $userTesseract
} else {
    Join-Path $env:ProgramFiles 'Tesseract-OCR\tesseract.exe'
}
$tesseract = Find-Tesseract $preferredTesseract
if (-not $tesseract) {
    if ($TesseractInstallScope -eq 'User') {
        New-Item -ItemType Directory -Path $TesseractInstallRoot -Force | Out-Null
        $installerUrl = 'https://github.com/UB-Mannheim/tesseract/releases/download/v5.4.0.20240606/tesseract-ocr-w64-setup-5.4.0.20240606.exe'
        $installerPath = Join-Path ([IO.Path]::GetTempPath()) 'docling-tesseract-ocr-setup.exe'
        try {
            Write-Host "Installing Tesseract for the current user in $userTesseractDirectory"
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            $destinationArgument = "/D=`"$userTesseractDirectory`""
            $process = Start-Process -FilePath $installerPath -ArgumentList @('/S', $destinationArgument) -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "Tesseract installer failed with exit code $($process.ExitCode)." }
        }
        finally {
            if (Test-Path -LiteralPath $installerPath) { Remove-Item -LiteralPath $installerPath -Force }
        }
    } else {
        winget install --id UB-Mannheim.TesseractOCR --exact --source winget --scope machine --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw "Tesseract installation failed with exit code $LASTEXITCODE." }
    }
    $tesseract = Find-Tesseract $preferredTesseract
}
if (-not $tesseract) { throw 'Tesseract was installed but could not be located. Open a new PowerShell window and rerun this script.' }

$tesseractDir = Split-Path -Parent $tesseract
$tessdataPath = Join-Path $tesseractDir 'tessdata'
if (-not (Test-Path -LiteralPath $tessdataPath)) { throw "Tesseract language data was not found at $tessdataPath." }

# Configure this process and future shells. Docling expects the trailing slash.
$env:PATH = "$tesseractDir;$env:PATH"
$env:TESSDATA_PREFIX = "$($tessdataPath.TrimEnd('\', '/'))/"
$environmentTarget = if ($TesseractInstallScope -eq 'System') { 'Machine' } else { 'User' }
if ([Environment]::GetEnvironmentVariable('TESSDATA_PREFIX', $environmentTarget) -ne $env:TESSDATA_PREFIX) {
    [Environment]::SetEnvironmentVariable('TESSDATA_PREFIX', $env:TESSDATA_PREFIX, $environmentTarget)
}

$savedPath = [Environment]::GetEnvironmentVariable('Path', $environmentTarget)
$savedPathParts = @($savedPath -split ';' | Where-Object { $_ })
if ($savedPathParts -notcontains $tesseractDir) {
    $newSavedPath = (@($savedPathParts) + $tesseractDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newSavedPath, $environmentTarget)
}
Write-Host "Tesseract: $tesseract"
Write-Host "TESSDATA_PREFIX: $env:TESSDATA_PREFIX"

Write-Step 'Creating the virtual environment'
$createdVenv = $false
if (-not (Test-Path -LiteralPath $venvPython)) {
    & $python -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the virtual environment.' }
    $createdVenv = $true
}

Write-Step 'Checking Docling in .venv'
& $venvPython -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)'
if ($LASTEXITCODE -ne 0) {
    throw 'The existing .venv uses a Python version other than 3.12. Remove it intentionally, then rerun this script.'
}

& $venvPython -c "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('docling') else 1)"
$doclingInstalled = $LASTEXITCODE -eq 0
if ($createdVenv -or -not $doclingInstalled) {
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upgrade pip.' }
    & $venvPython -m pip install docling
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Docling.' }
} elseif ($Upgrade) {
    & $venvPython -m pip install --upgrade pip docling
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upgrade Docling.' }
} else {
    Write-Host 'Docling is already installed; leaving the environment unchanged.'
}

& $venvPython -m pip check
if ($LASTEXITCODE -ne 0) { throw 'The virtual environment contains incompatible dependencies.' }

Write-Step 'Validating the installation'
& $tesseract --version | Select-Object -First 2
if ($LASTEXITCODE -ne 0) { throw 'Tesseract validation failed.' }
& $tesseract --list-langs
if ($LASTEXITCODE -ne 0) { throw 'Tesseract language-data validation failed.' }
& $venvDocling --version
if ($LASTEXITCODE -ne 0) { throw 'Docling validation failed.' }

if ($ProcessSamples) {
    & (Join-Path $repoRoot 'run-pdf-samples.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Sample conversion failed.' }
}

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host 'Activate the environment with: .\.venv\Scripts\Activate.ps1'
Write-Host 'Convert samples with:       .\setup-docling.ps1 -ProcessSamples'
