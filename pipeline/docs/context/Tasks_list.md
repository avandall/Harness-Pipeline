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
| `TASK-001` | [Tên Task Mẫu 1] | Phase 1 | P0 | `[ ] TODO` | Khởi tạo module mẫu |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: [Tên Task Mẫu 1]

#### Metadata
```
Task ID:         TASK-001
Task Name:       [Tên Task Mẫu 1]
Phase:           Phase 1
Task Type:       feat / fix / refactor
Priority:        P0-Critical
Trạng thái:      [ ] TODO
Ngày tạo:        [YYYY-MM-DD]
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** [Lý do cần làm task này]
- **What:** [Mô tả chi tiết việc cần thực hiện]

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [ ] Tiêu chí nghiệm thu 1
- [ ] Tiêu chí nghiệm thu 2
- [ ] Tier 1 verification checks pass 100%.

#### Scope (Phạm vi)
- **Files được sửa/tạo:** `src/**`, `tests/**`
- **Files cấm đụng:** `.env`, `pipeline/docs/core/**`

#### Verification Commands
```bash
python3 pipeline/scripts/verify.py
```
