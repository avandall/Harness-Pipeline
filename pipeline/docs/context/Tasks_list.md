# TASKS LIST
# Danh sách tác vụ & Queue thực thi — [Tên Dự Án]

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** [YYYY-MM-DD]
>
> ✏️ **HUMAN OR INTERVIEW AGENT FILLS THIS FILE.** Bạn hoặc AI Agent sau khi phỏng vấn có thể thêm 1 hoặc nhiều tasks vào danh sách này.
> 🤖 **AI EXECUTION RULE:** AI sẽ đọc danh sách này từ trên xuống dưới, tìm task đầu tiên có trạng thái `[ ] TODO` hoặc `[/] IN_PROGRESS` để thực thi. Khi hoàn thành task, AI đánh dấu `[x] DONE` và chuyển sang task tiếp theo.

---

## 1. Task Queue & Backlog Overview

| Task ID | Domain/Scope | Target Files / Dirs | Test Target | Ưu tiên | Trạng thái | Ghi chú / Blocker |
|---------|--------------|---------------------|-------------|---------|------------|-------------------|
| `TASK-001` | Project Scaffolding | `src/*`, `pyproject.toml` | static_check | P0 | `[ ] TODO` | Dựng khung xương thư mục, __init__.py & manifest |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

> **Quy định Task Type & Test Strategy:**
> - `feature`: Bắt buộc tạo Test Contract trước (Red ➔ Green).
> - `refactor`: Không duplicate tests; dùng test suite hiện có làm Regression Guard (tất cả test cũ phải giữ nguyên PASS).
> - `scaffold` / `setup`: Kiểm tra cấu trúc files, manifest và lint/typecheck.

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: Project Scaffolding, Package Layout & Manifest Initialization

#### Metadata
```
Task ID:         TASK-001
Task Name:       Project Scaffolding, Package Layout & Manifest Initialization
Phase:           Phase 1
Task Type:       scaffold
Priority:        P0-Critical
Trạng thái:      [ ] TODO
Ngày tạo:        [YYYY-MM-DD]
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Dự án mới cần cấu trúc thư mục rõ ràng và cố định ngay từ đầu để ngăn chặn AI tự ý ném thư mục tràn lan ra root và tránh lỗi import.
- **What:** Khởi tạo toàn bộ cây thư mục chuẩn theo `TECH_CONTEXT.md`, tạo tất cả file `__init__.py` cho các package, khởi tạo dependency manifest (`pyproject.toml` hoặc `package.json`), và tạo các mỏ neo cốt lõi (`config`, `constants`, `types`).

#### Test Strategy & Hàng rào kiểm thử
- **Strategy:** Scaffold verification (Verify file layout & manifest syntax).
- **Test Gate Files:** Không áp dụng unit test cho task scaffold; kiểm tra tính hợp lệ qua static checks.

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
# Trong lúc dựng thư mục & files:
python3 pipeline/scripts/verify.py --tier 0

# Khi hoàn thành nghiệm thu task:
python3 pipeline/scripts/verify.py --tier 2
```

---

### 📌 TASK-TEMPLATE: [Mẫu Task Chuẩn Cho Feature Hoặc Refactor]

#### Metadata
```
Task ID:         TASK-XXX
Task Name:       [Tên Task ngắn gọn]
Phase:           Phase X
Task Type:       feature | refactor | scaffold
Priority:        P0 | P1 | P2
Trạng thái:      [ ] TODO
Ngày tạo:        [YYYY-MM-DD]
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** [Lý do kỹ thuật hoặc business cần thực hiện task này]
- **What:** [Mô tả chi tiết những gì cần cài đặt/thay đổi]

#### Test Strategy & Hàng rào kiểm thử
- **Strategy:** 
  - Nếu `feature`: Viết/Cập nhật file test trước trong `tests/` (Red ➔ Green).
  - Nếu `refactor`: Regression Guard (đảm bảo 100% tests hiện có tiếp tục PASS, không duplicate test file).
- **Test Gate Files:** `tests/test_xxx.py`

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [ ] [Tiêu chuẩn chức năng 1]
- [ ] [Xử lý edge case 1]
- [ ] Tier 1 (targeted test) pass 100%.
- [ ] Tier 2 (full regression suite) pass 100%.

#### Scope (Phạm vi)
- **Files được sửa/tạo:** `app/services/xxx.py`, `tests/test_xxx.py` (tối đa 5-8 files)
- **Files cấm đụng:** `.env`, các files ngoài task scope

#### Verification Commands
```bash
# Vòng lặp vi mô từng file (Lint & Type):
python3 pipeline/scripts/verify.py --tier 0

# Vòng lặp test targeted (<10s):
python3 pipeline/scripts/verify.py --tier 1 --test-target tests/test_xxx.py

# Nghiệm thu hoàn tất task (Full suite & Security):
python3 pipeline/scripts/verify.py --tier 2
```
