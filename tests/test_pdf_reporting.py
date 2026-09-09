"""Integration & Unit tests for PDF Reporting Engine & Idempotency verification."""

import asyncio
import hashlib
from pathlib import Path
from typing import Any

import pytest
from jinja2 import Environment, StrictUndefined, TemplateSyntaxError, UndefinedError
from playwright.async_api import async_playwright


class PDFReportEngine:
    """PDF Reporting engine utilizing Jinja2 templates and Playwright Headless Chromium."""

    def __init__(self) -> None:
        self.jinja_env = Environment(
            undefined=StrictUndefined,
            autoescape=True,
        )

    def render_template(self, template_str: str, context: dict[str, Any]) -> str:
        """Render HTML string using Jinja2 with strict variable validation."""
        template = self.jinja_env.from_string(template_str)
        return template.render(**context)

    async def generate_pdf_bytes(self, html_content: str) -> bytes:
        """Render HTML string to PDF bytes via Playwright Headless Chromium."""
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            try:
                page = await browser.new_page()
                await page.set_content(html_content, wait_until="networkidle")
                pdf_bytes = await page.pdf(
                    format="A4",
                    print_background=True,
                    margin={"top": "20mm", "bottom": "20mm", "left": "15mm", "right": "15mm"},
                )
                return pdf_bytes
            finally:
                await browser.close()

    async def generate_report_idempotent(
        self,
        report_id: str,
        template_str: str,
        context: dict[str, Any],
        output_dir: Path,
    ) -> tuple[Path, bool]:
        """Generate PDF report idempotently.

        Returns (file_path, generated_from_scratch: bool).
        If report for report_id already exists in output_dir, skips regeneration.
        """
        output_dir.mkdir(parents=True, exist_ok=True)
        pdf_filename = f"report_{report_id}.pdf"
        file_path = output_dir / pdf_filename

        if file_path.exists() and file_path.stat().st_size > 0:
            return file_path, False

        html_content = self.render_template(template_str, context)
        pdf_bytes = await self.generate_pdf_bytes(html_content)

        # Write atomically via temp file
        temp_path = output_dir / f".tmp_{pdf_filename}"
        temp_path.write_bytes(pdf_bytes)
        temp_path.replace(file_path)

        return file_path, True


@pytest.fixture
def engine() -> PDFReportEngine:
    return PDFReportEngine()


@pytest.fixture
def reports_dir(tmp_path: Path) -> Path:
    target = tmp_path / "reports"
    return target


def test_render_template_success(engine: PDFReportEngine) -> None:
    template = "<h1>Report for {{ name }}</h1><p>Total: ${{ total }}</p>"
    context = {"name": "Sanjeevani Health", "total": 1500}
    rendered = engine.render_template(template, context)
    assert "<h1>Report for Sanjeevani Health</h1>" in rendered
    assert "<p>Total: $1500</p>" in rendered


def test_render_template_syntax_error(engine: PDFReportEngine) -> None:
    invalid_template = "<h1>Report for {{ name </h1>"
    with pytest.raises(TemplateSyntaxError):
        engine.render_template(invalid_template, {"name": "Test"})


def test_render_template_missing_variable(engine: PDFReportEngine) -> None:
    template = "<h1>Report for {{ missing_var }}</h1>"
    with pytest.raises(UndefinedError):
        engine.render_template(template, {"name": "Test"})


def test_generate_pdf_bytes_header(engine: PDFReportEngine) -> None:
    async def run() -> None:
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                @media print {
                    h1 { color: #1e3a8a; font-family: sans-serif; }
                }
            </style>
        </head>
        <body>
            <h1>Diagnostic Summary Report</h1>
            <p>Patient ID: PAT-10029</p>
        </body>
        </html>
        """
        pdf_bytes = await engine.generate_pdf_bytes(html)
        assert isinstance(pdf_bytes, bytes)
        assert len(pdf_bytes) > 0
        assert pdf_bytes.startswith(b"%PDF-")

    asyncio.run(run())


def test_pdf_report_idempotency(engine: PDFReportEngine, reports_dir: Path) -> None:
    async def run() -> None:
        report_id = "REP-2026-001"
        template = "<h1>Medical Report {{ report_id }}</h1><p>Status: {{ status }}</p>"
        context = {"report_id": report_id, "status": "COMPLETED"}

        # First call: generates report from scratch
        path1, created1 = await engine.generate_report_idempotent(
            report_id, template, context, reports_dir
        )
        assert created1 is True
        assert path1.exists()
        assert path1.name == "report_REP-2026-001.pdf"

        content1 = path1.read_bytes()
        hash1 = hashlib.sha256(content1).hexdigest()

        # Second call with same report_id: idempotent (skips generation, reuses cached file)
        path2, created2 = await engine.generate_report_idempotent(
            report_id, template, context, reports_dir
        )
        assert created2 is False
        assert path2 == path1

        content2 = path2.read_bytes()
        hash2 = hashlib.sha256(content2).hexdigest()
        assert hash1 == hash2

    asyncio.run(run())


def test_pdf_report_different_ids(engine: PDFReportEngine, reports_dir: Path) -> None:
    async def run() -> None:
        template = "<h1>Report {{ id }}</h1>"
        path1, _ = await engine.generate_report_idempotent(
            "ID-1", template, {"id": 1}, reports_dir
        )
        path2, _ = await engine.generate_report_idempotent(
            "ID-2", template, {"id": 2}, reports_dir
        )

        assert path1 != path2
        assert path1.exists()
        assert path2.exists()

    asyncio.run(run())


def test_reports_dir_in_project_scope() -> None:
    """Verify that reports created in the actual reports/ folder are valid and clean."""

    async def run() -> None:
        project_reports_dir = Path("reports")
        engine = PDFReportEngine()

        path, _created = await engine.generate_report_idempotent(
            "TEST-SCOPED-001",
            "<h1>Scoped Report Test</h1>",
            {},
            project_reports_dir,
        )
        assert path.exists()
        assert path.read_bytes().startswith(b"%PDF-")

        # Clean up test artifact after assertion
        if path.exists():
            path.unlink()

    asyncio.run(run())
