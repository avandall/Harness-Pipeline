# TASK EXECUTION PLAN: TASK-005
# Test Suite Tích hợp & Deterministic Verification

> **Trạng thái:** IN_PROGRESS | **Task ID:** TASK-005 | **Ngày:** 2026-09-07

## Mục tiêu
Viết đầy đủ unit & integration tests trong `tests/test_pdf_reporting.py` và `tests/test_background_jobs.py`, cấu hình `.gitignore` chuẩn và đảm bảo `python3 pipeline/scripts/verify.py` pass 100%.

## Phân rã Các bước (Atomic Steps)

### Step 1: Cấu hình .gitignore chuẩn
- Thêm `reports/`, `*.pdf`, `*.db`, `*.sqlite*` vào `.gitignore`.
- Đảm bảo git status không theo dõi file database tạm và pdf reports generated.

### Step 2: Implement `tests/test_pdf_reporting.py`
- Test PDF generation engine (Playwright Chromium + Jinja2 HTML rendering + Print CSS).
- Test PDF reporting idempotency (gọi lại cùng payload không gây xung đột/lặp side-effect).
- Test handling output paths, directory creation, PDF header validation (`%PDF-`), and invalid template/data errors.

### Step 3: Implement `tests/test_background_jobs.py`
- Test Async Background Tasks (FastAPI BackgroundTasks & Async IO / Inngest integration).
- Test Job execution idempotency (tránh chạy trùng lặp background task với idempotency key/status).
- Test task retries and exception handling in background tasks.
- Test Cron Cleanup task (dọn dẹp temporary files, old pdf reports, expired db records).

### Step 4: Verification & Git Status Check
- Chạy `python3 pipeline/scripts/verify.py` (Ruff, Mypy, Bandit, Pytest).
- Kiểm tra `git status` đảm bảo làm sạch working tree và không lọt `reports/*.pdf` hay DB tạm.
