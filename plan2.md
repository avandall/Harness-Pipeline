# SPEC & ARCHITECTURE: Enterprise Agent Pipeline Framework
### Chuyển đổi Boilerplate từ "Doc-Only Framework" sang "Hybrid Executable Agent Engine"
> **Tài liệu chiến lược và thiết kế kỹ thuật (Production-Grade)**  
> *Tổng hợp & Nâng cấp từ Anthropic Engineering Blog (Building Effective Agents & Managed Agents) + Thực tế Vận hành AI Loop 2026*

---

## 1. Trả lời trực tiếp: Tính khả thi khi áp dụng cho MỌI trường hợp

### ❓ Nâng cấp bộ khung này lên production-grade áp dụng cho mọi trường hợp có khả thi không?

**CÂU TRẢ LỜI KHẮC NGHIỆT:**  
- **KHÔNG THỂ** nếu bạn cố tạo ra **một kịch bản (script) cứng duy nhất** hoặc **chỉ dùng một bộ prompt/doc tĩnh** cho tất cả các loại project. Sử dụng prompt tĩnh cho AI tự đọc/tự chạy là nguyên nhân khiến agent bị "lost in context", không có checkpoint phục hồi khi crash, và dễ bị rò rỉ credential.
- **HOÀN TOÀN KHẢ THI** nếu bạn xây dựng theo kiến trúc **Core Engine + Pluggable Adapters (Động cơ lõi + Các đầu cắm mở rộng)**. 

### Mô hình "Pluggable Enterprise Architecture":
Một Enterprise Agent Pipeline chuẩn sản xuất sẽ chia làm 2 phần rõ rệt:
1. **Core Engine (Phần Cố Định - 80%):** Quản lý vòng lặp (Harness Loop), Lưu trữ nhật ký sự kiện (Append-only Event Log), Bảo mật & Ủy quyền (Vault/Proxy Gateway), Tracing/Observability (OpenTelemetry), và Giao thức Tool chuẩn (MCP). Phần này **độc lập với domain** và dùng chung 100% cho mọi project.
2. **Domain Presets & Adapters (Phần Linh Hoạt - 20%):** Định nghĩa Sandbox (Docker/Local venv), bộ Tools cụ thể (Static Linter, Database CLI, API Clients), và Bộ tiêu chí đánh giá (Eval/DoD) riêng cho từng loại project (Backend Python, Frontend React, Data Pipeline, DevOps Infrastructure...).

---

## 2. Một Enterprise Agent Pipeline gồm những thành phần & file gì?

Một Agent Pipeline thực sự **không chỉ là thư mục chứa file markdown**. Nó là một **Hệ điều hành thu nhỏ dành cho AI (AI Operating Environment)** bao gồm Code thực thi (Python/CLI) + Docs quy tắc + Hạ tầng Sandbox + Cơ sở dữ liệu Session.

### 📊 Sơ đồ Kiến trúc 6 Lớp (6-Layer Architecture Overview)

```
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 1 — INSTRUCTION & TEMPLATE LAYER (Docs & Prompts)                │
│  • System Prompts  • Rules (AGENTS.md)  • Task Specs  • Tool Manuals   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 2 — HARNESS & BRAIN ENGINE (Executable Python CLI)                │
│  • Main Loop (Wake/Resume)  • LLM Connector  • State Machine Router    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 3 — SESSION & DURABLE EVENT LOG (State Storage)                   │
│  • events.jsonl (Ground Truth) • Context Compactor • Vector Index     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 4 — HANDS, TOOLS & SANDBOX (Isolation Layer)                      │
│  • MCP Gateway  • Code Executor  • Dynamic Sandbox Provisioner         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 5 — SECURITY, GOVERNANCE & HITL (Safety Gate)                     │
│  • Secret Vault Proxy  • Action Guardrails  • Human Approval Breakpoint│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  LỚP 6 — EVAL, TRACING & OBSERVABILITY (Quality Control)              │
│  • OpenTelemetry Tracer • Cost Tracker • Automated Eval Suite (Pytest) │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Cấu trúc thư mục Chi tiết (Target File Tree)

Dưới đây là cấu trúc hoàn chỉnh của repository `boilerplate` sau khi được refactor thành Enterprise Pipeline:

```
boilerplate/
├── .agents/                        # Dynamic Skills & Custom Rules
│   └── AGENTS.md                   # Rule tối cao cho AI Agent trong workspace
│
├── bin/                            # Command Line Interfaces (CLI entrypoints)
│   ├── agent-run                   # Shell wrapper khởi tạo / resume agent loop
│   ├── agent-eval                  # CLI chạy suite kiểm thử đánh giá agent
│   └── agent-clean                 # Cleanup sandbox & reset transient state
│
├── engine/                         # 🧠 CORE ENGINE (Code thực thi Python - Zero background overhead)
│   ├── __init__.py
│   ├── harness/                    # [Lớp 2] Vòng lặp điều khiển chính (Brain Loop)
│   │   ├── __init__.py
│   │   ├── loop.py                 # Core Ralph Loop (LLM call -> Tool call -> Eval -> Repeat)
│   │   ├── state_machine.py        # Quản lý trạng thái: ORIENT -> PLAN -> EXEC -> REVIEW -> DONE
│   │   └── llm_provider.py         # Connector trừu tượng (Anthropic, Gemini, OpenAI, Ollama)
│   │
│   ├── session/                    # [Lớp 3] Quản lý Session & Lưu vết trạng thái bền vững
│   │   ├── __init__.py
│   │   ├── event_log.py            # Append-only jsonl event logger (Ground Truth)
│   │   ├── compactor.py            # Cắt tỉa ngữ cảnh & log rác (Token optimizer)
│   │   └── memory_index.py         # Semantic search trong lịch sử log dài (FAISS / Vector Lite)
│   │
│   ├── tools/                      # [Lớp 4] Hands & Tool Integrations
│   │   ├── __init__.py
│   │   ├── registry.py             # Tool Manager (Đăng ký, kiểm tra schema, routing)
│   │   ├── mcp_client.py           # Client giao tiếp với các MCP Servers
│   │   ├── builtin/                # Tools tích hợp sẵn (File I/O, Git, Search)
│   │   │   ├── file_ops.py
│   │   │   └── git_ops.py
│   │   └── adapters/               # Tools theo từng Preset (Static Analysis, Test Runners)
│   │       ├── ruff_adapter.py
│   │       ├── mypy_adapter.py
│   │       └── pytest_adapter.py
│   │
│   ├── sandbox/                    # [Lớp 4] Môi trường thực thi cô lập
│   │   ├── __init__.py
│   │   ├── base.py                 # Abstract Sandbox Interface (provision, execute, destroy)
│   │   ├── local_env.py            # Isolated Virtualenv Execution (Dành cho dev / light task)
│   │   └── docker_env.py           # Containerized Sandbox Execution (Dành cho production)
│   │
│   ├── security/                   # [Lớp 5] Bảo mật, Scoping & Human-in-the-loop
│   │   ├── __init__.py
│   │   ├── vault_proxy.py          # Proxy injecting secrets (Credential không chạm vào Sandbox)
│   │   ├── guardrails.py           # Lọc lệnh nguy hiểm (rm -rf, SQL drop, secret leak)
│   │   └── hitl_gate.py            # Interrupt & chờ con người duyệt cho hành động High-Risk
│   │
│   └── observability/              # [Lớp 6] Monitoring, Tracing & Cost Accounting
│       ├── __init__.py
│       ├── tracer.py               # OpenTelemetry trace từng tool call / LLM latency
│       ├── cost_tracker.py         # Đếm số token tiêu thụ & tính chi phí $ realtime
│       └── metrics.py              # Export TTFT (Time-to-First-Token) & Success Rate
│
├── H_docs/                         # 📝 INSTRUCTION LAYER (Docs chuẩn hóa cho Agent & Human)
│   ├── README.md                   # Hướng dẫn tổ chức H_docs
│   ├── core/                       # 🔒 Fixed Rules & Protocols (Chỉ sửa khi đổi architecture)
│   │   ├── AGENT_CONSTITUTION.md   # 10 Điều luật bất biến
│   │   ├── HARNESS_PROTOCOL.md     # Định nghĩa State Machine & Loop Specs
│   │   ├── WORKFLOW_STANDARDS.md   # Quy trình 7 giai đoạn thực hiện task
│   │   ├── CODE_STANDARDS.md       # Chuẩn code & linting
│   │   └── REVIEW_PROTOCOL.md      # Quy trình tự review & kiểm tra lỗi
│   │
│   ├── context/                    # ✏️ Human Fills (Context cụ thể của project target)
│   │   ├── PROJECT_BRIEF.md        # Mục tiêu, phạm vi & Definition of Done
│   │   ├── TECH_CONTEXT.md         # Tech stack & môi trường
│   │   ├── BOUNDARIES.md           # Giới hạn file được phép / không được phép sửa
│   │   └── Tasks_list.md           # Master Task Backlog ([ ] TODO, [/] IN_PROGRESS, [x] DONE)
│   │
│   └── runtime/                    # 🤖 AI Fills (Trạng thái động được sync từ Engine)
│       ├── CURRENT_TASK.md         # Task đang chạy
│       ├── STATUS.md               # Snapshot trạng thái tức thời
│       ├── PLAN.md                 # Kế hoạch chi tiết của task hiện tại
│       ├── PROGRESS_LOG.md         # Nhật ký tiến độ chi tiết
│       ├── PROOF_OF_SOLUTION.md    # Bằng chứng verification
│       └── BLOCKERS/               # Nơi chứa thông tin khi bị kẹt (Overnight mode)
│
├── presets/                        # 🔌 DOMAIN PRESETS (Mẫu thiết lập sẵn cho các loại project)
│   ├── python_backend/             # Ruff + Mypy + Pytest + Bandit
│   │   ├── preset.yaml
│   │   └── tools.py
│   ├── node_react/                 # ESLint + TSC + Vitest + Playwright
│   │   ├── preset.yaml
│   │   └── tools.py
│   └── generic_scripting/          # Bash + Shellcheck + Python
│       └── preset.yaml
│
├── evals/                          # 🧪 EVALUATION SUITE (Bộ test case đánh giá năng lực agent)
│   ├── test_cases/                 # Các bài test mẫu từ dễ đến khó
│   │   ├── task_01_bugfix.json
│   │   └── task_02_refactor.json
│   └── run_eval.py                 # Runner tính tỷ lệ thành công & benchmark AI
│
├── pyproject.toml                  # Khai báo dependency chính (Ruff, Mypy, Pytest, Pydantic, etc.)
├── requirements.txt                # Lock file cho môi trường Python
└── README.md                       # Hướng dẫn sử dụng boilerplate & clone sang project mới
```

---

## 4. Chi tiết Chức năng từng Thành phần

### A. Lớp Engine (`engine/`) - Phần Mới Cần Xây Dựng
* **`harness/loop.py`**: Chạy vòng lặp tự động (Ralph Loop). Nó gửi prompt tới LLM API, nhận kết quả tool call, gọi `sandbox` để chạy, lấy stdout/stderr đi qua `compactor` để cắt tỉa log (chỉ giữ 15-20 dòng Traceback quan trọng), sau đó cập nhật `events.jsonl` và quay lại lượt gọi tiếp theo.
* **`session/event_log.py`**: Lưu toàn bộ lịch sử dạng JSON Lines (`.jsonl`). Mọi hành động của Agent đều được ghi thành một Event chuẩn: `USER_INPUT`, `MODEL_THOUGHT`, `TOOL_CALL`, `TOOL_RESULT`, `HUMAN_INTERVENTION`. Khi tiến trình bị killed/crash, `event_log.py` cho phép phát lại (replay) và khôi phục trạng thái chính xác đến từng millisecond.
* **`security/vault_proxy.py`**: API Keys (OpenAI, Anthropic, AWS, DB credentials) nằm hoàn toàn trong môi trường của EngineHost. Khi Agent gọi một tool cần credential (ví dụ: query database), tool gọi qua `vault_proxy`, proxy chèn token/password vào header rồi mới gửi đi. Agent và Sandbox không bao giờ nhìn thấy raw API key.
* **`security/hitl_gate.py`**: Đánh dấu các lệnh nhạy cảm (như `git push origin main`, `rm -rf`, `DROP TABLE`). Khi Agent yêu cầu tool này, Engine tạm dừng (PAUSED), gửi notification cho con người (qua CLI/Slack/UI), chờ bấm Approval mới tiếp tục.

### B. Lớp Instructions (`H_docs/`) - Tối ưu hóa từ Boilerplate hiện tại
* Giữ nguyên mô hình phân tách 3 tầng: `core/` (luật cứng), `context/` (human khai báo), `runtime/` (AI cập nhật).
* **Đổi mới quan trọng**: File `H_docs/runtime/STATUS.md` và `PROGRESS_LOG.md` sẽ được **Engine tự động sync/write ra disk** sau mỗi tool execution, thay vì phụ thuộc 100% vào việc Agent tự nhớ viết bằng tool write_file.

---

## 5. Phương án & Lộ trình Refactor Repo (Step-by-Step Execution Plan)

### Giai đoạn 1: Chuẩn hóa & Dọn dẹp Workspace hiện tại (Ngày 1)
1. **Dọn dẹp code thừa**: Đóng gói hoặc di chuyển `sanjeevani-backend-core` ra khỏi repository khung mẫu này.
2. **Cập nhật `pyproject.toml`**: Khai báo đầy đủ các thư viện nền tảng:
   - `pydantic` (Validate tool schemas & event logs)
   - `ruff`, `mypy`, `bandit`, `pytest` (Code quality & testing engine)
   - `opentelemetry-api`, `opentelemetry-sdk` (Tracing & Observability)
   - `httpx`, `mcp` (Giao tiếp API & MCP Protocol)

### Giai đoạn 2: Phát triển Core Engine Python (`engine/`) (Ngày 2 - Ngày 3)
1. Xây dựng **`engine/session/event_log.py`**: Đảm bảo đọc/ghi event stream append-only bền vững.
2. Xây dựng **`engine/tools/`**: Port logic cắt tỉa log từ `lean_python_ai_loop_plan.md` vào `compactor.py` (cắt tỉa log rác, tiết kiệm >90% token).
3. Xây dựng **`engine/harness/loop.py`**: Viết vòng lặp CLI có khả năng chạy offline/online, tích hợp state machine `ORIENT -> PLAN -> EXEC -> REVIEW -> DONE`.

### Giai đoạn 3: Tích hợp Security Gateway & Presets (Ngày 4)
1. Xây dựng **`engine/security/hitl_gate.py`** & **`vault_proxy.py`**.
2. Đóng gói Preset đầu tiên: `presets/python_backend/` (dùng Ruff + Pytest + Mypy).

### Giai đoạn 4: Đánh giá & Đóng gói CLI (`bin/`) (Ngày 5)
1. Tạo CLI `bin/agent-run` hỗ trợ lệnh:
   - `agent-run --task TASK-001` (Chạy task mới)
   - `agent-run --resume` (Khôi phục task bị gãy)
   - `agent-run --eval` (Chạy bộ test suite đánh giá)
2. Viết tài liệu `README.md` hướng dẫn cách nhân bản (clone) repo này sang một project bất kỳ và khởi chạy trong 1 phút.

---

## 6. Hướng dẫn bàn giao cho AI Code Generator triển khai ngay

Dưới đây là prompt mẫu để bạn sử dụng cho AI Agent (Claude Code / Antigravity) ở lượt làm việc tiếp theo để bắt đầu code từng module của Engine:

```markdown
Hãy đọc file plan2.md trong workspace. 
Bắt đầu Phase 1 & Phase 2:
1. Tạo cấu trúc thư mục `engine/` với các submodules `harness`, `session`, `tools`, `sandbox`, `security`, `observability`.
2. Khai báo dependencies trong `pyproject.toml` (pydantic, ruff, mypy, pytest, httpx).
3. Triển khai `engine/session/event_log.py` và `engine/tools/compactor.py` để xử lý việc lưu trữ Event Log append-only và cắt tỉa log lỗi Python.
4. Tuân thủ strict rules trong `AGENTS.md`.
```

---

## 7. Trạng thái Triển khai Hiện tại (Implementation Status)

> Cập nhật: 2026-08-19. Trạng thái này phản ánh sau đợt refactor đầu tiên.

| Module | File | Trạng thái | Ghi chú |
|--------|------|-----------|---------|
| **Session - Event Log** | `engine/session/event_log.py` | ✅ Production-ready | Append-only JSONL, Pydantic schema |
| **Session - Compactor** | `engine/session/compactor.py` | ✅ Production-ready | Single source of truth (verify.py import từ đây) |
| **Security - Vault Proxy** | `engine/security/vault_proxy.py` | ✅ Production-ready | Redact credentials khỏi output |
| **Security - HITL Gate** | `engine/security/hitl_gate.py` | ✅ Production-ready | Pattern-matching, extensible |
| **Observability - Cost Tracker** | `engine/observability/cost_tracker.py` | ✅ Production-ready | Multi-model pricing table |
| **Observability - Tracer** | `engine/observability/tracer.py` | ✅ Production-ready | Span timing |
| **Harness - State Machine** | `engine/harness/state_machine.py` | ✅ Production-ready | Valid transitions, history |
| **Harness - Loop** | `engine/harness/loop.py` | ⚠️ **Skeleton** | Event logging OK, nhưng chưa có LLM call thực sự |
| **CLI** | `bin/agent-run` | ⚠️ **Skeleton** | Gọi harness nhưng không chạy subprocess thực |
| **LLM Provider** | `engine/harness/llm_provider.py` | ❌ **Chưa có** | Cần implement để loop thực sự gọi được model |
| **Tool Executor** | `engine/tools/` | ❌ **Chưa có** | Registry + MCP Client chưa được implement |
| **Sandbox** | `engine/sandbox/` | ❌ **Chưa có** | Local venv / Docker executor |
| **Preset Loader** | `presets/python_backend/` | ⚠️ **YAML only** | Chưa có code đọc và apply preset |
| **Eval Suite** | `evals/` | ❌ **Chưa có** | Cần benchmark test cases |

### Bước tiếp theo ưu tiên

1. `engine/harness/llm_provider.py` — Abstract connector (Anthropic / Gemini / OpenAI)
2. Hoàn thiện `engine/harness/loop.py` — Thêm `while` loop thực sự gọi LLM → parse tool call → execute
3. `engine/tools/registry.py` — Tool registry và subprocess executor
4. Tích hợp `bin/agent-run` với `verify.py` — Chạy Tier 1 check tự động trước commit

---

## 8. Hướng dẫn Sử dụng & Onboarding Dự án Mới

---

## 8. Quy Hoạch 1 Thư Mục Duy Nhất (`pipeline/`) & Onboarding Dự Án Mới

Toàn bộ hạ tầng Enterprise Pipeline (Docs, Engine, CLI, Presets, Tests) đã được **quy hoạch gọn gàng vào duy nhất 1 thư mục `pipeline/`**. Khi sang dự án mới, bạn chỉ cần copy hoặc chạy lệnh install 1 dòng duy nhất.

### 8.1 Cấu Trúc Độc Lập Gọn Gàng Của `pipeline/`

```
pipeline/
├── setup.sh                        # 🚀 Script 1-click install pipeline vào bất kỳ dự án nào
├── bin/                            # CLI executables (agent-run, agent-eval)
├── engine/                         # 🧠 Core Python Engine (harness, session, security, observability)
├── docs/                           # 📝 Instruction Layer & Docs
│   ├── core/                       # AGENT_CONSTITUTION.md, HARNESS_PROTOCOL.md, etc.
│   ├── context/                    # PROJECT_BRIEF.md, TECH_CONTEXT.md, BOUNDARIES.md, Tasks_list.md
│   ├── runtime/                    # CURRENT_TASK.md, STATUS.md, VERIFICATION_REPORT.md
│   ├── scripts/                    # verify.py
│   └── harness.sh                  # Main Ralph Loop Orchestrator
├── presets/                        # 🔌 Domain Presets (python_backend, node_react)
└── tests/                          # 🧪 Test suite kiểm thử engine

# Các Wrapper ngắn gọn ở root dự án (tự sinh bởi setup.sh):
├── harness.sh                      # -> trỏ tới ./pipeline/docs/harness.sh
└── bin/agent-run                   # -> trỏ tới ./pipeline/bin/agent-run
```

---

### 8.2 Lệnh Copy / Install Sang Dự Án Mới (Chỉ 1 Lệnh)

**Cách 1: Chạy script install tự động (Khuyên dùng)**
```bash
# Đứng tại thư mục boilerplate và truyền đường dẫn sang dự án mới:
./pipeline/setup.sh /path/to/my-new-project
```

**Cách 2: Copy bằng tay thủ công:**
```bash
# Chỉ cần copy đúng 1 thư mục pipeline/ sang dự án mới:
cp -r pipeline /path/to/my-new-project/
cd /path/to/my-new-project/
./pipeline/setup.sh
```

---

### 8.3 Danh Sách Các File CẦN THAY ĐỔI Khi Sang Dự Án Mới

Nằm hoàn toàn bên trong `pipeline/docs/context/`:

| # | Đường dẫn File | Vai trò | Chi tiết Cần Thay Đổi & Cách Thay Đổi |
|---|---|---|---|
| 1 | `pipeline/docs/context/PROJECT_BRIEF.md` | Bức tranh tổng quan dự án | Sửa tên dự án, mục tiêu kinh doanh, Tech Stack chính, Definition of Done (DoD) và Roadmap các Phase. |
| 2 | `pipeline/docs/context/TECH_CONTEXT.md` | Bối cảnh kỹ thuật & Môi trường | Cấu hình chính xác phiên bản Python/Node/Go, danh sách libraries, DB local, và các lệnh run/build/test. |
| 3 | `pipeline/docs/context/BOUNDARIES.md` | Giới hạn quyền hạn cho AI | Khai báo file paths được sửa (`src/**`, `tests/**`), cấm sửa (`.env`), và database write/drop permissions. |
| 4 | `pipeline/docs/context/Tasks_list.md` | Master Task Backlog | Xóa toàn bộ task cũ, viết danh sách task mới dạng `[ ] [TASK-001] Mô tả task` (P0/P1/P2). |
| 5 | `pyproject.toml` (hoặc `package.json`) | Package Dependencies | Thêm các thư viện phụ thuộc của dự án mới bên cạnh các core dependencies. |
| 6 | `pipeline/presets/<domain>/preset.yaml` | Adapter kiểm tra tĩnh & Test | Chọn hoặc tạo preset tương ứng (`python_backend` hoặc `node_react`) chứa lệnh `ruff`, `eslint`, `pytest`, `vitest`. |
| 7 | `pipeline/docs/scripts/verify.py` | Engine kiểm định Tier 1 | Nếu dự án dùng ngôn ngữ khác Python (như TypeScript/Go), cập nhật lệnh CLI trong `run_python_checks()` sang test/lint runner tương ứng. |

---

### 8.4 Lệnh Khởi Chạy Pipeline Dự Án Mới

Sau khi cấu hình xong, bạn sử dụng lệnh sau ở root dự án để khởi chạy:

```bash
# 1. Chạy Tier 1 Verification kiểm tra môi trường ban đầu
python3 pipeline/docs/scripts/verify.py

# 2. KHUYẾN NGHỊ: Khởi chạy Vòng lặp Tự động (Ralph Loop Orchestrator)
# (Tự động đọc Tasks_list.md, pick task TODO, sinh CURRENT_TASK.md, verify & commit cho đến khi xong hết backlog)
./harness.sh

# (Tùy chọn) Khởi chạy với chế độ Dual-Model Review (1 model code, 1 model review phản biện):
./harness.sh --review-model gemini-3.6-flash-low
```





