# PLAN
# Kế hoạch thực thi — TASK-001: Fix Static Analysis & Type Checking Errors

> **Trạng thái:** RUNTIME (Auto-generated) | **Tạo bởi:** AI

---

## Task Reference

```
Task ID:    TASK-001
Task Name:  Fix Static Analysis & Type Checking Errors
Spec:       Fix all Ruff linting and Mypy type checking errors in sanjeevani-backend-core and pipeline
```

---

## Spec (Đặc tả)

### Acceptance Criteria
- [x] Ruff lint checks pass without errors.
- [x] Mypy type checks pass without errors.
- [x] All verification commands pass 100%.

### Verification Commands
```bash
python3 pipeline/scripts/verify.py
```

---

## Execution Steps

### Step 1: Fix Ruff B008 and import sorting in auth.py
- **Mục tiêu:** Use `Annotated[OAuth2PasswordRequestForm, Depends()]` instead of function call default.
- **Files tạo/sửa:** `sanjeevani-backend-core/app/api/v1/auth.py`
- **Exit condition:** Ruff no longer reports B008.

### Step 2: Fix datetime.UTC compatibility for Python 3.10
- **Mục tiêu:** Replace `from datetime import UTC` with `from datetime import timezone` and `timezone.utc`.
- **Files tạo/sửa:** `sanjeevani-backend-core/app/models/base.py`, `sanjeevani-backend-core/app/core/security.py`
- **Exit condition:** Mypy no longer reports attr-defined error for UTC.

### Step 3: Fix Mypy type annotations and return types
- **Mục tiêu:** Add default for SECRET_KEY, prop-decorator ignore, cast return types in security.py, model_validate in users.py, init return annotation in cost_tracker.py, main return annotation in verify.py, and alembic attr-defined ignores.
- **Files tạo/sửa:** `app/core/config.py`, `app/core/security.py`, `app/api/v1/users.py`, `alembic/env.py`, `alembic/versions/202406270001_create_users_table.py`, `cost_tracker.py`, `verify.py`
- **Exit condition:** Mypy check passes with zero errors.

### Step 4: Verify Tier 1 Verification Suite
- **Mục tiêu:** Run `python3 pipeline/scripts/verify.py` and ensure status is PASS.
- **Files tạo/sửa:** None
- **Exit condition:** `Status: PASS` in `VERIFICATION_REPORT.md`.

---

## Iteration Budget

```
Estimated iterations: 1
Maximum allowed:      3
Context refresh at:   Iteration 3
```

---

## Plan Revision History

| Revision | Ngày | Lý do thay đổi |
|----------|------|----------------|
| v1 | 2026-08-22 | Khởi tạo plan cho TASK-001 |
| v2 | 2026-08-22 | Đã hoàn thành tất cả các bước và verify PASS 100% |
