"""Start Docling MCP with the PDF settings validated by this repository."""

import os
import shutil
from pathlib import Path

from docling.backend.pypdfium2_backend import PyPdfiumDocumentBackend
from docling.datamodel.accelerator_options import AcceleratorDevice, AcceleratorOptions
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import (
    OcrMode,
    PdfPipelineOptions,
    TableFormerMode,
    TesseractCliOcrOptions,
)
from docling.document_converter import DocumentConverter, ImageFormatOption, PdfFormatOption
from docling_mcp.servers.mcp_server import TransportType, main
from docling_mcp.settings.service_client import settings
from docling_mcp.tools.converters.local import LocalDocumentConverter


def _find_tesseract() -> str:
    configured = os.environ.get("TESSERACT_CMD")
    candidates = [
        configured,
        shutil.which("tesseract"),
        r"C:\Tools\Tesseract-OCR\tesseract.exe",
        str(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Tesseract-OCR" / "tesseract.exe"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise RuntimeError(
        "Tesseract was not found. Run setup-docling.ps1 or set TESSERACT_CMD."
    )


def _get_tuned_converter(self: LocalDocumentConverter) -> DocumentConverter:
    """Create the local converter once with the repository's stable settings."""
    if self._converter is not None:
        return self._converter

    pipeline_options = PdfPipelineOptions(
        do_ocr=settings.do_ocr,
        do_table_structure=settings.do_table_structure,
        generate_page_images=settings.keep_images,
        generate_picture_images=settings.keep_images,
        images_scale=settings.images_scale,
        accelerator_options=AcceleratorOptions(
            num_threads=1,
            device=AcceleratorDevice.CPU,
        ),
    )
    pipeline_options.ocr_options = TesseractCliOcrOptions(
        lang=["eng"],
        mode=OcrMode.PDF_AWARE_LAYOUT_REGIONS,
        tesseract_cmd=_find_tesseract(),
    )
    pipeline_options.table_structure_options.mode = TableFormerMode.ACCURATE
    pipeline_options.table_structure_options.do_cell_matching = True

    self._converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(
                backend=PyPdfiumDocumentBackend,
                pipeline_options=pipeline_options,
            ),
            InputFormat.IMAGE: ImageFormatOption(
                pipeline_options=pipeline_options,
            ),
        }
    )
    return self._converter


LocalDocumentConverter._get_converter = _get_tuned_converter

if __name__ == "__main__":
    main(transport=TransportType.STDIO)
