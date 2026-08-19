# Harness Engineering Docs System — README
# Điểm vào — Đọc trước khi làm bất cứ điều gì

> Đây là bộ docs chuẩn hoá theo triết lý **Harness Engineering / Ralph Loop** — thiết kế để AI agent hoạt động tự trị, có thể kiểm soát, và luôn có đủ context để thực hiện bất kỳ task nào.

---

## Cấu trúc

```
H_docs/
├── core/                      🔒 FIXED — Không thay đổi theo task
│   ├── AGENT_CONSTITUTION.md  Luật nền tảng (đọc đầu tiên)
│   ├── HARNESS_PROTOCOL.md    Ralph Loop + State machine
│   ├── WORKFLOW_STANDARDS.md  Pipeline 7 phases (Hybrid Verification)
│   ├── CODE_STANDARDS.md      Tiêu chuẩn code universal
│   ├── REVIEW_PROTOCOL.md     Tự phản biện 2 lớp (Tier 1 & Tier 2)
│   ├── TOOL_REGISTRY.md       Danh sách tools được phép dùng
│   └── GLOSSARY.md            Từ điển thuật ngữ
│
├── context/                   ✏️ MUTABLE — Bạn cập nhật theo từng task
│   ├── PROJECT_BRIEF.md       Mô tả dự án (cập nhật khi bắt đầu project)
│   ├── TECH_CONTEXT.md        Tech stack và môi trường
│   ├── Tasks_list.md        ← CẦN CẬP NHẬT TRƯỚC MỖI TASK MỚI
│   └── BOUNDARIES.md          Giới hạn quyền của AI
│
├── scripts/                   🛠️ HARNESS TOOLING — Công cụ hỗ trợ AI
│   └── verify.py              Kiểm định định tính (Ruff/Mypy/Bandit/Pytest) + Log Truncator
│
└── runtime/                   🤖 AUTO-GENERATED — AI tự tạo khi chạy
    ├── PLAN.md                Kế hoạch thực thi (AI tạo)
    ├── STATUS.md              Trạng thái real-time
    ├── VERIFICATION_REPORT.md Kết quả kiểm định định tính Tier 1
    ├── PROGRESS_LOG.md        Nhật ký chi tiết mỗi iteration
    ├── PROOF_OF_SOLUTION.md   Bằng chứng hoàn thành
    ├── DEBATE_LOG.md          Lịch sử tự phản biện Tier 2
    ├── BLOCKED.md             ← Xuất hiện khi AI cần help
    └── ITERATIONS/            Snapshot từng vòng lặp
```

---

## Cách dùng cho task mới

### Bước 1: Cập nhật context (2-5 phút)

Chỉ cần sửa **2 files** tối thiểu:

```bash
# File QUAN TRỌNG NHẤT — mô tả task cho AI
nano H_docs/context/Tasks_list.md

# Nếu task liên quan đến giới hạn đặc biệt
nano H_docs/context/BOUNDARIES.md
```

### Bước 2: Clear runtime (nếu task mới hoàn toàn)

```bash
# Xóa runtime docs từ task trước (nếu muốn fresh start)
rm -rf H_docs/runtime/*.md H_docs/runtime/ITERATIONS/
# Hoặc commit chúng trước: git add H_docs/runtime/ && git commit -m "archive: prev task runtime"
```

### Bước 3: Giao task cho AI

Chỉ cần nói với AI:
```
Hãy đọc H_docs/ và thực hiện task trong Tasks_list.md theo Harness Protocol.
```

AI sẽ tự:
- Đọc tất cả docs cần thiết
- Tạo `PLAN.md`
- Thực thi theo Ralph Loop
- Tạo `PROOF_OF_SOLUTION.md` khi xong

### Bước 4: Chạy tự động (optional)

```bash
# Cấp quyền thực thi
chmod +x ./H_docs/harness.sh

# Chạy harness
./H_docs/harness.sh --task "TASK-001"

# Xem options
./H_docs/harness.sh --help
```

---

## Khi AI tạo BLOCKED.md

```bash
# Đọc file để biết vấn đề
cat H_docs/runtime/BLOCKED.md

# Sau khi giải quyết, xóa file để AI tiếp tục
rm H_docs/runtime/BLOCKED.md

# Chạy lại harness
./H_docs/harness.sh
```

---

## Philosophy

> **"Filesystem là bộ nhớ. Git là lịch sử. BLOCKED.md là phanh khẩn cấp."**
>
> Thay vì giữ context trong conversation (dễ bị "context rot"), toàn bộ state được externalise ra filesystem. Mỗi iteration, AI bắt đầu với fresh context và đọc state từ files. Điều này giúp:
>
> - **Reproducible**: Bất kỳ AI nào cũng có thể tiếp tục từ điểm dừng
> - **Auditable**: Mọi quyết định đều được log
> - **Recoverable**: `git reset --hard` là recovery mechanism
> - **Scalable**: Có thể song song nhiều agents mà không conflict context

---

## Files bạn cần quan tâm nhất

| File | Tần suất cập nhật | Ai cập nhật |
|------|------------------|------------|
| `context/Tasks_list.md` | Mỗi task mới | **Bạn** |
| `context/PROJECT_BRIEF.md` | Mỗi project mới | **Bạn** |
| `context/BOUNDARIES.md` | Khi scope thay đổi | **Bạn** |
| `runtime/BLOCKED.md` | Khi AI cần help | AI tạo, **Bạn** giải quyết |
| `runtime/PROOF_OF_SOLUTION.md` | Khi task done | AI |

---

## Versioning

```
Docs System Version: 1.0.0
Harness Protocol: 1.0
Last Updated: 2026-08-07
```



## 8. Hướng dẫn Sử dụng & Onboarding Dự án Mới

Tài liệu này hướng dẫn chi tiết cách copy bộ khung (boilerplate) sang một repository/dự án mới và các file bắt buộc phải cấu hình lại.

---

### 8.1 Quy trình 4 Bước Khi Chuyển Sang Dự Án Mới

```
Step 1: Copy Boilerplate  ──►  Step 2: Cấu hình H_docs/context/  ──►  Step 3: Chọn Domain Preset  ──►  Step 4: Khởi chạy Task 1
(Copy code & engine)            (Khai báo mục tiêu & boundaries)       (Gắn ruff/eslint/pytest)              (agent-run --task TASK-001)
```

1. **Clone / Copy Boilerplate:** Copy toàn bộ thư mục project (loại bỏ thư mục `.git/`, `.venv/`, `.pytest_cache/`, `H_docs/runtime/session_*.jsonl`).
2. **Khai báo Bối cảnh Dự án:** Sửa các file trong `H_docs/context/` để mô tả dự án mới.
3. **Cấu hình Preset & Dependencies:** Cập nhật `pyproject.toml` và chọn/tạo file `presets/<domain>/preset.yaml`.
4. **Khởi động AI Loop:** Điền task đầu tiên vào `H_docs/runtime/CURRENT_TASK.md` và chạy `python3 bin/agent-run --task TASK-001`.

---

### 8.2 Danh Sách Các File CẦN THAY ĐỔI Khi Sang Dự Án Mới

| # | Đường dẫn File | Vai trò | Chi tiết Cần Thay Đổi & Cách Thay Đổi |
|---|---|---|---|
| 1 | `H_docs/context/PROJECT_BRIEF.md` | Bức tranh tổng quan dự án | **Thay đổi:** Tên dự án, mô tả mục tiêu kinh doanh, Tech Stack chính, Definition of Done (DoD) và Roadmap các Phase.<br>**Cách làm:** Thay các đoạn placeholder `[Tên dự án]`, `[Module 1]` bằng yêu cầu thật của dự án. |
| 2 | `H_docs/context/TECH_CONTEXT.md` | Bối cảnh kỹ thuật & Môi trường | **Thay đổi:** Phiên bản Python/Node/Go, danh sách thư viện (libraries), DB connections local/test, và các lệnh run/build/test.<br>**Cách làm:** Khai báo chính xác môi trường dự án mới cần để AI không dùng nhầm thư viện. |
| 3 | `H_docs/context/BOUNDARIES.md` | Giới hạn quyền hạn cho AI | **Thay đổi:** Khai báo danh sách file/folder AI được phép sửa (ví dụ: `src/**`, `tests/**`) và cấm sửa (ví dụ: `.env`, `production config`), giới hạn database permissions.<br>**Cách làm:** Cập nhật mục 1 (File Scope) và mục 2 (Database Permissions) theo dự án mới. |
| 4 | `H_docs/context/Tasks_list.md` | Master Backlog dự án | **Thay đổi:** Danh sách công việc cần làm.<br>**Cách làm:** Xóa toàn bộ task cũ của boilerplate. Thêm danh sách task mới dạng `[ ] [TASK-001] Mô tả task` chia theo các Phase P0, P1, P2. |
| 5 | `H_docs/runtime/CURRENT_TASK.md` | Task hiện tại AI đang thực thi | **Thay đổi:** Chi tiết công việc duy nhất mà AI đang xử lý ở lượt chạy hiện tại.<br>**Cách làm:** Ghi `Task ID: TASK-001`, mô tả chi tiết Why/What, Acceptance Criteria và lệnh verification command (ví dụ: `pytest tests/test_auth.py`). |
| 6 | `pyproject.toml` (hoặc `package.json`) | Package Dependencies | **Thay đổi:** Thư viện phụ thuộc của dự án.<br>**Cách làm:** Giữ nguyên các core engine dependencies (`pydantic`, `httpx`, `ruff`, `mypy`, `pytest`), thêm các package mới mà dự án cần (ví dụ: `fastapi`, `sqlalchemy`). |
| 7 | `presets/<domain>/preset.yaml` | Adapter kiểm tra tĩnh & Test | **Thay đổi:** Cấu hình linter, type checker và test runner phù hợp với dự án.<br>**Cách làm:** Nếu là dự án Python, chọn `presets/python_backend/preset.yaml`. Nếu là Node/React, tạo `presets/node_react/preset.yaml` chứa `eslint`, `tsc`, `vitest`. |
| 8 | `H_docs/scripts/verify.py` | Engine kiểm định Tier 1 | **Thay đổi:** Lệnh chạy static analysis & test runner.<br>**Cách làm:** Nếu dự án không dùng Python (ví dụ: TypeScript/Go), cập nhật hàm `run_python_checks()` sang gọi `npm run lint`, `npx tsc`, `npm test` hoặc `go test`. |

---

### 8.3 Những File KHÔNG BAO GIỜ SỬA (Cố Định Cho Mọi Dự Án)

Các file này chứa **Quy luật bất biến và Động cơ cốt lõi (Core Engine)**, được giữ nguyên 100% để đảm bảo AI hoạt động đúng chuẩn Enterprise Pipeline:

* 🔒 **`AGENTS.md` & `.agents/AGENTS.md`**: Quy tắc tối cao hướng dẫn Agent cách làm việc trong workspace.
* 🔒 **`H_docs/core/*`**: 
  - `AGENT_CONSTITUTION.md` (10 Điều luật bất biến)
  - `HARNESS_PROTOCOL.md` (Giao thức Ralph Loop & State machine)
  - `WORKFLOW_STANDARDS.md` (Pipeline 7 Phase chuẩn)
  - `REVIEW_PROTOCOL.md` (Quy trình 2-tier review & debate)
  - `CODE_STANDARDS.md` (Chuẩn code & formatting)
  - `TOOL_REGISTRY.md` (Danh mục tools được phép dùng)
* 🔒 **`engine/*`**: Bộ mã nguồn Python điều khiển loop, session event logging, security vault, HITL gate, tracing và cost tracking.

---

### 8.4 Lệnh Khởi Chạy Pipeline Dự Án Mới

Sau khi cấu hình xong các file ở mục 8.2, bạn sử dụng lệnh sau để bắt đầu:

```bash
# 1. Chạy Tier 1 Verification kiểm tra môi trường ban đầu
python3 H_docs/scripts/verify.py

# 2. KHUYẾN NGHỊ: Khởi chạy Vòng lặp Tự động (Ralph Loop Orchestrator)
# (Tự động đọc Tasks_list.md, pick task TODO, sinh CURRENT_TASK.md, verify & commit cho đến khi xong hết backlog)
./H_docs/harness.sh

# (Tùy chọn) Khởi chạy với chế độ Dual-Model Review (1 model code, 1 model review phản biện):
./H_docs/harness.sh --review-model gemini-3.6-flash-low

# (Tùy chọn) Chạy trực tiếp qua Python Core Engine CLI (dùng khi test step lẻ hoặc debug engine):
python3 bin/agent-run
```