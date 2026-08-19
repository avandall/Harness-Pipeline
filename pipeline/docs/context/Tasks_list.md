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
| `TASK-001` | [Tên task ví dụ: Infrastructure & Setup] | Phase 1 | P0 | `[ ] TODO` | [Ghi chú khởi tạo] |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: [Tên task]

#### Metadata
```
Task ID:         TASK-001
Task Name:       [Tên task]
Phase:           Phase 1 (Setup)
Task Type:       feature / fix / refactor / setup
Priority:        P0-Critical / P1-High / P2-Medium
Trạng thái:      [ ] TODO
Ngày tạo:        [YYYY-MM-DD]
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** [Tại sao cần làm task này?]
- **What:** [Cụ thể những công việc cần làm là gì?]

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [ ] [Tiêu chí 1]
- [ ] [Tiêu chí 2]
- [ ] Verification tests pass 100%.

#### Scope (Phạm vi)
- **Files được sửa/tạo:** `[thư mục/files liên quan]`
- **Files cấm đụng:** `pipeline/docs/core/**`, `[files ngoài scope]`

#### Verification Commands
```bash
[Command chạy để verify, e.g. pytest hoac npm test]
```
