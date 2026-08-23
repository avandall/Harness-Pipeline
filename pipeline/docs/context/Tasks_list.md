# TASKS LIST
# Danh sách tác vụ & Queue thực thi — [Tên Dự Án]

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** [YYYY-MM-DD]
>
> ✏️ **HUMAN FILLS THIS FILE.** Bạn có thể thêm 1 hoặc nhiều tasks vào danh sách này.
> 🤖 **AI EXECUTION RULE:** AI sẽ đọc danh sách này từ trên xuống dưới, tìm task đầu tiên có trạng thái `[ ] TODO` hoặc `[/] IN_PROGRESS` để thực thi. Khi hoàn thành task, AI đánh dấu `[x] DONE` và chuyển sang task tiếp theo.

---

## 1. Task Queue & Backlog Overview

| Task ID | Tên Task | Phase | Ưu tiên | Trạng thái | Ghi chú / Blocker |
|---------|----------|-------|---------|------------|-------------------|
| `TASK-001` | Fix Static Analysis & Type Checking Errors | Phase 1 | P0 | `[x] DONE` | Ruff & Mypy verification passed 100% |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: Fix Static Analysis & Type Checking Errors

#### Metadata
```
Task ID:         TASK-001
Task Name:       Fix Static Analysis & Type Checking Errors
Phase:           Phase 1 (Infrastructure & Quality)
Task Type:       fix / refactor
Priority:        P0-Critical
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-22
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Codebase backend có các lỗi lint (Ruff) và type check (Mypy) khiến Tier 1 verification suite thất bại.
- **What:** Sửa tất cả các lỗi static analysis trong `sanjeevani-backend-core` và `pipeline/` để `python3 pipeline/scripts/verify.py` trả về PASS 100%.

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [x] Ruff lint checks pass without errors.
- [x] Mypy type checks pass without errors.
- [x] Verification tests pass 100%.

#### Scope (Phạm vi)
- **Files được sửa/tạo:** `sanjeevani-backend-core/**`, `pipeline/engine/**`, `pipeline/scripts/verify.py`
- **Files cấm đụng:** `pipeline/docs/core/**`

#### Verification Commands
```bash
python3 pipeline/scripts/verify.py
```
