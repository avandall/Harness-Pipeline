# CURRENT TASK
# Task hiện tại đang thực thi — Context cho AI agent

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** Mỗi khi chuyển sang task mới
>
> ✏️ **HUMAN FILLS THIS FILE.** Ghi chi tiết task đang được giao cho AI.
> Dùng file này để cung cấp context cụ thể cho task hiện tại mà không cần sửa `Tasks_list.md`.

---

## Task đang thực hiện

```
Task ID:      [TASK-001]
Task Name:    Fix Static Analysis & Type Checking Errors
Phase:        Phase 1 (Infrastructure & Quality)
Priority:     P0-Critical
Started:      2026-08-22
```

---

## Mục tiêu (Why & What)

**Tại sao cần làm task này?**
- Codebase backend gặp một số lỗi lint (Ruff B008, import sorting) và type checking (Mypy UTC attribute, missing default arguments, return type mismatch).
- Đảm bảo Tier 1 verification suite `python3 pipeline/scripts/verify.py` pass 100%.

**Cụ thể cần làm gì?**
- Sửa lỗi Ruff B008 trong `auth.py` và sắp xếp import.
- Thay thế `datetime.UTC` bằng `timezone.utc` cho Python 3.10 compatibility.
- Bổ sung type annotations & type casting cho functions trong `security.py`, `config.py`, `users.py`, `cost_tracker.py`, `verify.py`, `env.py`.

---

## Acceptance Criteria (Tiêu chí hoàn thành)

Task được coi là DONE khi:
- [x] Ruff linting checks pass 100%.
- [x] Mypy type checks pass 100%.
- [x] Tất cả verification commands chạy PASS 100%.

---

## Context bổ sung

### Input / Dependencies
- `pipeline/scripts/verify.py`

### Known Constraints
- Tuân thủ Python 3.10 compatibility.

### References
- `pipeline/docs/core/CODE_STANDARDS.md`

---

## Verification Commands

```bash
python3 pipeline/scripts/verify.py
```

---

## Notes từ Human

> Đã hoàn thành sửa toàn bộ lỗi static analysis.

---

## Lịch sử (History)

| Ngày | Task ID | Trạng thái | Ghi chú |
|------|---------|------------|---------|
| 2026-08-22 | TASK-001 | [x] DONE | Sửa toàn bộ lỗi Ruff & Mypy, Tier 1 verification PASS 100% |
