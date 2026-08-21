# Enterprise Agent Pipeline System — README
# Điểm vào — Đọc trước khi làm bất cứ điều gì

> Đây là bộ docs chuẩn hoá theo triết lý **Harness Engineering / Ralph Loop** & **Managed Agents** — thiết kế để AI agent hoạt động tự trị, có thể kiểm soát, và luôn có đủ context để hoàn thành mọi task.

---

## 1. Cấu Trúc Độc Lập `pipeline/`

```
pipeline/
├── setup.sh                        # 🚀 Script 1-click install pipeline sang dự án mới
├── USER_GUIDE.md                   # 📖 Cẩm nang hướng dẫn sử dụng dành cho người dùng
├── scripts/                        # 🛠️ All Executables (harness.sh, verify.py, setup.sh, agent-run)
│   ├── harness.sh                  # ⚡ Main Ralph Loop Orchestrator Script
│   ├── verify.py                   # 🔍 Tier 1 Deterministic Verification Engine
│   ├── setup.sh                    # 🚀 Installer script
│   └── agent-run                   # 🧠 Core Engine CLI
├── engine/                         # 🧠 Core Python Engine (harness, session, security, observability)
├── docs/                           # 📝 Instruction Layer & Docs System
│   ├── core/                       # 🔒 FIXED: AGENT_CONSTITUTION.md, HARNESS_PROTOCOL.md, etc.
│   ├── context/                    # ✏️ MUTABLE: PROJECT_BRIEF.md, TECH_CONTEXT.md, Tasks_list.md, BOUNDARIES.md
│   └── runtime/                    # 🤖 AUTO-GENERATED: CURRENT_TASK.md, STATUS.md, VERIFICATION_REPORT.md
│       ├── sessions/               # 📊 Append-only JSONL Event Logs (session_*.jsonl)
│       ├── BLOCKERS/               # 🚫 Blocker reports
│       └── ITERATIONS/             # 📸 Iteration snapshots
├── presets/                        # 🔌 Domain Presets (python_backend, node_react, go, polyglot)
└── tests/                          # 🧪 Engine Unit Tests

# Root Wrappers (tự sinh bởi setup.sh ở root dự án):
├── harness.sh                      # -> trỏ tới ./pipeline/scripts/harness.sh
└── bin/agent-run                   # -> trỏ tới python3 ./pipeline/scripts/agent-run


```

---

## 2. Onboarding Dự Án Mới (1-Click Setup)

Chỉ cần 1 lệnh duy nhất để mang toàn bộ pipeline này sang một dự án mới:

```bash
# Đứng tại boilerplate và truyền đường dẫn sang dự án mới:
./pipeline/setup.sh /path/to/my-new-project
```

HOẶC copy thủ công duy nhất thư mục `pipeline/`:
```bash
cp -r pipeline /path/to/my-new-project/
cd /path/to/my-new-project/
./pipeline/setup.sh
```

---

## 3. Danh Sách Các File Cần Khai Báo Cho Dự Án Mới

Nằm hoàn toàn bên trong `pipeline/docs/context/`:

| # | Đường dẫn File | Vai trò | Chi tiết Cần Thay Đổi |
|---|---|---|---|
| 1 | `pipeline/docs/context/PROJECT_BRIEF.md` | Bức tranh tổng quan dự án | Tên dự án, mục tiêu kinh doanh, Tech Stack chính, Definition of Done (DoD) và Roadmap. |
| 2 | `pipeline/docs/context/TECH_CONTEXT.md` | Bối cảnh kỹ thuật & Môi trường | Phiên bản Python/Node/Go, thư viện phụ thuộc, DB local/test, lệnh run/build/test. |
| 3 | `pipeline/docs/context/BOUNDARIES.md` | Giới hạn quyền hạn cho AI | File paths được sửa (`src/**`, `tests/**`), cấm sửa (`.env`), database write/drop limits. |
| 4 | `pipeline/docs/context/Tasks_list.md` | Master Task Backlog | Thêm danh sách task cần làm dạng `[ ] [TASK-001] Mô tả task` (chia theo P0/P1/P2). |
| 5 | `pyproject.toml` (hoặc `package.json`) | Package Dependencies | Thêm các thư viện phụ thuộc của dự án mới. |
| 6 | `pipeline/presets/<domain>/preset.yaml` | Adapter kiểm tra tĩnh & Test | Chọn hoặc tạo preset tương ứng (`python_backend` hoặc `node_react`). |
| 7 | `pipeline/scripts/verify.py` | Engine kiểm định Tier 1 | Nếu dự án không dùng Python (dùng TS/Go), cập nhật lệnh CLI sang lint/test runner tương ứng. |

---

## 4. Cách Sử Dụng & Khởi Chạy Pipeline

### Bước 1: Khai báo Task Queue vào `Tasks_list.md`
Chỉ cần điền các task cần làm vào `pipeline/docs/context/Tasks_list.md` với trạng thái `[ ] TODO`.

### Bước 2: Khởi chạy Vòng lặp Tự động (Ralph Loop)
Ở root dự án, chạy lệnh duy nhất:
```bash
./harness.sh
```
*Script sẽ tự động pick task TODO đầu tiên, tự sinh `CURRENT_TASK.md`, thực thi, verify qua `verify.py`, commit Git khi pass, và chuyển sang task kế tiếp.*

### Tùy chọn khác:
```bash
# Bật chế độ Dual-Model Review (1 model code, 1 model review phản biện qua git diff):
./harness.sh --review-model gemini-3.6-flash-low

# Chạy trực tiếp qua Python Engine CLI (dùng khi test/debug step lẻ):
python3 bin/agent-run
```

---

## 5. Xử Lý Tình Huống Khi AI Bị Kẹt (`BLOCKED.md`)

Khi AI gặp vấn đề vượt giới hạn hoặc không tự giải quyết được ở Overnight Mode:
1. AI sẽ ghi chi tiết sự cố vào `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md` và đánh dấu `[!] BLOCKED` trong `Tasks_list.md`.
2. AI tự động bỏ qua task bị kẹt và chuyển sang task `[ ] TODO` tiếp theo.
3. Con người kiểm tra file blocker, giải đáp thắc mắc, xóa file blocker và đổi `[!] BLOCKED` thành `[ ] TODO`, sau đó chạy lại `./harness.sh`.

---

## 6. Những File KHÔNG BAO GIỜ SỬA (Cố Định)

* 🔒 **`AGENTS.md` & `.agents/AGENTS.md`**: Quy tắc tối cao hướng dẫn Agent trong workspace.
* 🔒 **`pipeline/docs/core/*`**: `AGENT_CONSTITUTION.md`, `HARNESS_PROTOCOL.md`, `WORKFLOW_STANDARDS.md`, `REVIEW_PROTOCOL.md`, `CODE_STANDARDS.md`, `TOOL_REGISTRY.md`.
* 🔒 **`pipeline/engine/*`**: Mã nguồn Python điều khiển loop, session JSONL logging, security vault, HITL gate, tracing và cost tracking.

---

## 7. Triết Lý Nền Tảng (Philosophy) & Versioning

> **"Filesystem là bộ nhớ. Git là lịch sử. BLOCKED.md là phanh khẩn cấp."**
>
> Toàn bộ state được lưu trữ trực tiếp ra filesystem. Mỗi iteration, AI bắt đầu với fresh context và đọc state từ files. Điều này đảm bảo:
> - **Reproducible**: Bất kỳ AI nào cũng có thể nối tiếp phiên làm việc mượt mà.
> - **Auditable**: Mọi quyết định và tool call đều có vết log chi tiết trong JSONL.
> - **Recoverable**: `git reset --hard` là cơ chế khôi phục trạng thái an toàn.
> - **Scalable**: Dễ dàng cắm rút Presets cho mọi loại dự án.

```text
Docs System Version: 2.0.0
Harness Protocol: 2.0 (Enterprise Engine Integrated)
Last Updated: 2026-08-19
```