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
| `TASK-001` | Project Scaffolding, Package Layout & Manifest Initialization | Phase 1 | P0 | `[ ] TODO` | Dựng khung xương thư mục, __init__.py & manifest |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: Project Scaffolding, Package Layout & Manifest Initialization

#### Metadata
```
Task ID:         TASK-001
Task Name:       Project Scaffolding, Package Layout & Manifest Initialization
Phase:           Phase 1
Task Type:       scaffold / setup
Priority:        P0-Critical
Trạng thái:      [ ] TODO
Ngày tạo:        [YYYY-MM-DD]
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Dự án mới cần cấu trúc thư mục rõ ràng và cố định ngay từ đầu để ngăn chặn AI tự ý ném thư mục tràn lan ra root và tránh lỗi import.
- **What:** Khởi tạo toàn bộ cây thư mục chuẩn theo `TECH_CONTEXT.md`, tạo tất cả file `__init__.py` cho các package, khởi tạo dependency manifest (`pyproject.toml` hoặc `package.json`), và tạo các mỏ neo cốt lõi (`config`, `constants`, `types`).

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [ ] Cấu trúc thư mục được tạo đầy đủ theo kiến trúc quy định trong `TECH_CONTEXT.md`.
- [ ] Tất cả các package directories đều có file `__init__.py`.
- [ ] File manifest (`pyproject.toml` / `requirements.txt` / `package.json`) khai báo đúng dependencies.
- [ ] Tier 1 verification checks pass 100%.

#### Scope (Phạm vi)
- **Files được sửa/tạo:** Thư mục mã nguồn theo kiến trúc (`app/**` hoặc `src/**` hoặc packages quy định), `pyproject.toml`, `package.json`, `tests/**`
- **Files cấm đụng:** `.env`, `pipeline/docs/core/**`

#### Verification Commands
```bash
python3 pipeline/scripts/verify.py
```
