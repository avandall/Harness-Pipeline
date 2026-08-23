# 📖 CẨM NANG HƯỚNG DẪN SỬ DỤNG ENTERPRISE AGENT PIPELINE

> **Tài liệu hướng dẫn dành cho Người dùng (Human Developer)**  
> Bộ khung làm việc tự động hóa dành cho AI Agent hoàn thành tác vụ theo phương pháp **Ralph Loop & Managed Agents**.

---

## 1. Tổng Quan Hệ Thống

Bộ khung này được quy hoạch gọn gàng trong **duy nhất 1 thư mục `pipeline/`**. Nó giúp bạn giao danh sách công việc cho AI, sau đó AI sẽ tự động:
1. Đọc bối cảnh và trích xuất task.
2. Lập kế hoạch (`PLAN.md`) và thực thi từng bước.
3. Chạy công cụ kiểm định chất lượng định tính Tier 1 (`verify.py` - Ruff/Mypy/Pytest).
4. Thực hiện phản biện nhận thức Tier 2 qua Git Diff (khi bật Dual-Model).
5. Tự động commit Git với message chuẩn khi hoàn thành task (`[TASK-001] feat(...)...`).
6. Tự động chuyển sang task tiếp theo cho tới khi hoàn thành toàn bộ backlog.

---

## 2. Hướng Dẫn Khởi Tạo Dự Án Mới (1-Click Setup)

Để áp dụng bộ khung này vào bất kỳ dự án mới nào (Backend, Frontend, Fullstack, CLI script...), bạn sử dụng **1 trong 2 cách** sau:

### Cách 1: Chạy script tự động (Khuyên dùng)
Đứng tại thư mục boilerplate hiện tại và gõ 1 lệnh duy nhất truyền đường dẫn tới dự án mới:
```bash
./pipeline/setup.sh /path/to/my-new-project
```

### Cách 2: Copy thủ công bằng tay
1. Copy duy nhất thư mục `pipeline/` sang thư mục dự án mới:
   ```bash
   cp -r pipeline /path/to/my-new-project/
   ```
2. Di chuyển sang dự án mới và chạy khởi tạo:
   ```bash
   cd /path/to/my-new-project/
   ./pipeline/setup.sh
   ```

*Script `setup.sh` sẽ tự động cấp quyền thực thi (`chmod +x`), tạo wrapper `./harness.sh` ở root, tự động khởi tạo `pyproject.toml` cơ bản (nếu dự án mới chưa có) và cấu hình `.gitignore`.*

---

## 3. Cấu Hình Dự Án Mới & Chọn Ngôn Ngữ (Preset Selector)

### A. Chọn Preset Ngôn Ngữ (Default: Python)
Hệ thống hỗ trợ sẵn các preset cho những ngôn ngữ phổ biến trong `pipeline/presets/`. Mặc định hệ thống dùng `python_backend`. Để đổi ngôn ngữ, mở file `pipeline/presets/active_preset.yaml`:

```yaml
# Chọn 1 trong các preset: python_backend | node_react | go_backend | generic_scripting | polyglot_multi | auto
active_preset: "python_backend"
```

* **`python_backend`**: Dành cho dự án Python (Ruff + Mypy + Bandit + Pytest).
* **`node_react`**: Dành cho dự án Node.js / TypeScript / React (ESLint + TSC + Vitest/Jest).
* **`go_backend`**: Dành cho dự án Go (golangci-lint + go vet + go test).
* **`generic_scripting`**: Dành cho dự án Shell Scripts (ShellCheck).
* **`polyglot_multi` hoặc `auto` (DỰ ÁN NHIỀU NGÔN NGỮ)**: AI sẽ **tự động phát hiện tất cả ngôn ngữ có trong dự án** (ví dụ: Python Backend + React Frontend + Go service) và chạy kiểm tra định tính đồng thời cho toàn bộ các ngôn ngữ!

---

### B. Các File Cấu Hình Dự Án Mới

Sau khi copy sang dự án mới, bạn chỉ cần mở thư mục `pipeline/docs/context/` và cập nhật các file:

| # | File cần sửa | Vai trò | Nội dung cần điền |
|---|---|---|---|
| 1 | `pipeline/docs/context/PROJECT_BRIEF.md` | Tổng quan dự án | Điền Tên dự án, mục tiêu kinh doanh, Tech Stack chính và Definition of Done (DoD). |
| 2 | `pipeline/docs/context/TECH_CONTEXT.md` | Bối cảnh kỹ thuật | Điền exact Python/Node/Go version, danh sách thư viện, DB local, và lệnh test. |
| 3 | `pipeline/docs/context/BOUNDARIES.md` | Giới hạn quyền hạn | Điền danh sách file được sửa (`src/**`, `tests/**`), cấm sửa (`.env`), quyền DB. |
| 4 | `pipeline/docs/context/Tasks_list.md` | Danh sách công việc | Xóa task cũ, điền danh sách task mới dạng `[ ] [TASK-001] Mô tả...` (P0/P1/P2). |
| 5 | `pyproject.toml` (hoặc `package.json`) | Package Dependencies | Tự sinh bởi `setup.sh` (nếu chưa có). Thêm các package phụ thuộc dự án mới nếu cần. |


> 🔒 **LƯU Ý:** Các thư mục `pipeline/docs/core/`, `pipeline/engine/`, `pipeline/.agents/` là bộ quy tắc bất biến và động cơ lõi — **KHÔNG CẦN SỬA**.

---

## 4. Quy Trình Vận Hành Hàng Ngày (Workflow Thực Tế)

### Bước 1: Khai báo Task Queue
Mở file `pipeline/docs/context/Tasks_list.md` và thêm các task bạn muốn AI làm:
```markdown
| TASK-001 | Thêm module đăng nhập JWT | Phase 1 | P0 | [ ] TODO | |
| TASK-002 | Xây dựng API Quota Limits  | Phase 1 | P1 | [ ] TODO | |
```

### Bước 2: Bắt đầu Vòng lặp Tự động
Tại root dự án, chạy lệnh duy nhất:
```bash
./harness.sh
```

**AI sẽ tự động làm toàn bộ các công việc sau:**
- Auto-pick task `TASK-001` từ `Tasks_list.md`.
- Tự động tạo bối cảnh tập trung `pipeline/docs/runtime/CURRENT_TASK.md`.
- Tự động viết code, kiểm thử bằng `verify.py`.
- Khi PASS 100%, tự động commit git: `[TASK-001] feat(auth): implement JWT login`.
- Đổi trạng thái `TASK-001` thành `[x] DONE` và nhảy sang `TASK-002`.

---

## 5. Tùy Chọn Nâng Cao

### A. Chọn Task Hoặc Dải Task Cần Chạy (`--tasks` / `-t`)
Khi bạn chỉ muốn AI chạy một số task chỉ định thay vì chạy toàn bộ backlog:
```bash
# Chạy dải task từ TASK-001 đến TASK-005
./harness.sh --tasks 1..5

# Chỉ chạy đúng task 6 và task 9
./harness.sh --tasks 6,9

# Kết hợp cả dải số và liệt kê
./harness.sh --tasks 1..5,8,10
```

### B. Chế độ Dual-Model Review (Phản biện chống bug ngầm)
Nếu task phức tạp và bạn muốn dùng 1 AI Model chuyên viết code (Executor) và 1 AI Model khác nhảy vào review phản biện qua `git diff`:
```bash
./harness.sh --review-model gemini-3.6-flash-low
```

### C. Giới hạn số lượng vòng lặp
```bash
./harness.sh --max-iter 20
```

### D. Chạy trực tiếp CLI Python (Dùng khi debug/test step lẻ)
```bash
python3 bin/agent-run
```

---

## 6. Tối Ưu Hiệu Năng & Tiết Kiệm Token (Task-Bound Session & Context Pruning)

Hệ thống tự động áp dụng các chuẩn tối ưu cao cấp:
1. **Task-Bound Session**: Tất cả bước nhỏ trong cùng 1 Task được chạy liên tục trong 1 phiên hội thoại. Tận dụng 100% Prompt Caching của LLM. Bộ nhớ phiên được làm sạch (Flush Memory) khi đổi Task.
2. **Context Pruning**: Script tự động trích xuất đúng nội dung Task Spec của task active từ `Tasks_list.md`, cắt bỏ 80% văn bản dư thừa không liên quan.
3. **Inline Constitution**: 10 Điều luật cốt lõi được nén trực tiếp trong `.agents/AGENTS.md` và prompt, loại bỏ các lượt gọi tool `view_file` mở lại các file docs trùng lặp ở mỗi lần khởi động.

---

## 7. Giải Quyết Khi AI Bị Kẹt (`BLOCKED.md`)

Khi AI gặp vấn đề vượt quá quyền hạn hoặc không thể tự khắc phục:
1. AI sẽ ghi lý do chi tiết vào file `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md` và đánh dấu dòng task trong `Tasks_list.md` thành `[!] BLOCKED`.
2. AI tự động chuyển sang task `[ ] TODO` tiếp theo mà không làm ngắt gián tiến trình (Overnight Mode).
3. **Cách con người gỡ kẹt:**
   - Đọc file blocker trong `BLOCKERS/` để biết lý do.
   - Giải đáp câu hỏi hoặc sửa lỗi cần thiết.
   - Xóa file blocker đó.
   - Đổi trạng thái task từ `[!] BLOCKED` thành `[ ] TODO` trong `Tasks_list.md`.
   - Gõ lại `./harness.sh` để AI tiếp tục làm task đó.

---

## 8. Bảng Tra Cứu Lệnh Nhanh (Cheatsheet)

| Nhu cầu | Lệnh chạy từ Terminal |
|---|---|
| **Cài pipeline vào dự án mới** | `./pipeline/setup.sh /path/to/du-an-moi` |
| **Bắt đầu chạy tự động toàn bộ task** | `./harness.sh` |
| **Chỉ chạy dải task chọn lọc (ví dụ 1..5)** | `./harness.sh --tasks 1..5` |
| **Chỉ chạy các task lẻ (ví dụ 6 và 9)** | `./harness.sh --tasks 6,9` |
| **Chạy tự động + Phản biện 2 model** | `./harness.sh --review-model gemini-3.6-flash-low` |
| **Kiểm tra chất lượng code Tier 1** | `python3 pipeline/scripts/verify.py` |
| **Chạy unit tests của Core Engine** | `python3 -m pytest pipeline/tests/test_engine.py` |

