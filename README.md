# Docling PDF conversion on Windows

This repository sets up [Docling](https://github.com/docling-project/docling) with Tesseract OCR on Windows and converts the PDFs in `pdf-samples` to Markdown. Extracted diagrams are written as referenced PNG files so both the text and visuals are convenient for AI agents.

The scripts also support machines where Hugging Face is blocked. Models can be downloaded on a connected machine, packed into a ZIP, transferred, and restored into the standard Hugging Face cache.

## Repository layout

| Path | Purpose |
| --- | --- |
| `pdf-samples/` | Input PDF files |
| `output/` | Generated Markdown and image artifacts; ignored by Git |
| `setup-docling.ps1` | Installs Python, Tesseract, and Docling |
| `run-pdf-samples.ps1` | Converts PDFs with Tesseract and local Docling models |
| `pack-huggingface-models.ps1` | Creates a portable model-cache archive |
| `unpack-huggingface-models.ps1` | Restores that archive on another machine |

PDF files under `pdf-samples` are intentionally ignored by Git. This prevents source documents and their metadata from being published accidentally; add or copy input PDFs locally after cloning.

## Requirements

- Windows 10 or Windows 11, x64
- PowerShell 5.1 or PowerShell 7
- WinGet (`App Installer`)
- Internet access to PyPI and GitHub during initial setup
- Administrator approval for the Tesseract installer
- Approximately 2 GB of free space for Python packages, models, and working output

The setup script installs Python 3.12 and the UB Mannheim Tesseract build when they are missing. It creates an isolated `.venv` and installs Docling from PyPI.

## Initial setup

From PowerShell in the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-docling.ps1
```

The script is idempotent. Subsequent runs validate the existing installation without reinstalling or upgrading it. To intentionally update pip and Docling:

```powershell
.\setup-docling.ps1 -Upgrade
```

## Connected-machine workflow

On a machine that can reach Hugging Face, allow the first conversion to download the required models:

```powershell
.\run-pdf-samples.ps1 -AllowHuggingFaceNetwork
```

Once the conversion succeeds, package the cached Docling models:

```powershell
.\pack-huggingface-models.ps1
```

This creates `docling-huggingface-models.zip` in the repository root. The archive is ignored by Git because it is large; transfer it separately with the repository or installation media.

The bundle contains the complete Hugging Face cache structure for the matching `docling-project` repositories, including blobs, snapshots, and revision references.

## Hugging-Face-blocked machine

Copy the repository and `docling-huggingface-models.zip` to the target machine, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-docling.ps1
.\unpack-huggingface-models.ps1
.\run-pdf-samples.ps1
```

The unpacker restores models to `%USERPROFILE%\.cache\huggingface` by default. It is safe to run repeatedly. The conversion runner enables `HF_HUB_OFFLINE` and `TRANSFORMERS_OFFLINE` by default, so it does not attempt to contact Hugging Face.

Custom archive and cache locations are supported:

```powershell
.\pack-huggingface-models.ps1 `
    -ArchivePath D:\transfer\docling-models.zip `
    -HuggingFaceHome D:\hf-cache

.\unpack-huggingface-models.ps1 `
    -ArchivePath D:\transfer\docling-models.zip `
    -HuggingFaceHome D:\hf-cache
```

When using a custom cache on the target machine, set `HF_HOME` before conversion:

```powershell
$env:HF_HOME = 'D:\hf-cache'
.\run-pdf-samples.ps1
```

## Converting PDFs

Convert every PDF in `pdf-samples`:

```powershell
.\run-pdf-samples.ps1
```

Convert one matching file:

```powershell
.\run-pdf-samples.ps1 -FileName 'USBTMC_1_00.pdf'
```

Select another installed Tesseract language or output directory:

```powershell
.\run-pdf-samples.ps1 `
    -OcrLanguage eng `
    -OutputDirectory .\results
```

Useful advanced parameters:

| Parameter | Default | Description |
| --- | --- | --- |
| `FileName` | `*.pdf` | Input filename or wildcard within `pdf-samples` |
| `OcrLanguage` | `eng` | Tesseract language code |
| `ImageExportMode` | `referenced` | `referenced` PNGs, base64 `embedded`, or `placeholder` |
| `PdfBackend` | `pypdfium2` | PDF parser used by Docling |
| `PageBatchSize` | `1` | Pages processed per batch |
| `NumThreads` | `1` | Docling worker threads |
| `AllowHuggingFaceNetwork` | off | Permit model downloads from Hugging Face |

The conservative page batch and thread defaults reduce memory usage on 16 GB Windows systems. `pypdfium2` is used because Docling's default native parser produced `std::bad_alloc` on later pages of `USBTMC_1_00.pdf`.

## Output

For a source named `example.pdf`, referenced-image mode produces:

```text
output/
|-- example.md
`-- example_artifacts/
    |-- image_000000_....png
    `-- image_000001_....png
```

Keep the Markdown file and its `_artifacts` directory together. Markdown links use relative paths.

## Known limitations

Docling recognizes and serializes tables page-by-page. It does not currently merge a logical table that spans multiple PDF pages. During validation, a two-page table in a USBTMC specification was emitted as two Markdown tables, and the continuation had a different inferred column structure.

Reliable cross-page table merging requires post-processing Docling's structured output using page provenance, table geometry, column compatibility, and repeated-header detection. The `accurate` table mode improves individual table extraction but does not join tables across page boundaries.

## Troubleshooting

### Models are missing in offline mode

If conversion reports that a Hugging Face model cannot be found, unpack the model archive for the same Windows user that runs Docling:

```powershell
.\unpack-huggingface-models.ps1
```

On a connected machine, use `-AllowHuggingFaceNetwork` once before packing the cache.

### Tesseract language is missing

List installed languages:

```powershell
tesseract --list-langs
```

The default installation includes `eng` and `osd`. Additional language data must be installed into the Tesseract `tessdata` directory before using another `-OcrLanguage` value.

### `std::bad_alloc` during PDF preprocessing

Use the runner defaults (`pypdfium2`, one-page batches, and one thread). To explicitly restore them:

```powershell
.\run-pdf-samples.ps1 `
    -PdfBackend pypdfium2 `
    -PageBatchSize 1 `
    -NumThreads 1
```

### Hugging Face symlink warning

The cache still works without Windows Developer Mode, but may use more disk space. The runner suppresses this warning. Enabling Windows Developer Mode permits the Hugging Face cache to use symlinks efficiently but is not required.
