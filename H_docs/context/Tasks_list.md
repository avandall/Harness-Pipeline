# TASKS LIST
# Danh sách tác vụ & Queue thực thi — Usage Metering & Billing Engine (Python Stack)

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** 2026-08-07 (Based on FlyRank Capstone Brief PDF - Python Stack)
>
> ✏️ **HUMAN FILLS THIS FILE.** Bạn có thể thêm 1 hoặc nhiều tasks vào danh sách này.
> 🤖 **AI EXECUTION RULE:** AI sẽ đọc danh sách này từ trên xuống dưới, tìm task đầu tiên có trạng thái `[ ] TODO` hoặc `[/] IN_PROGRESS` để thực thi. Khi hoàn thành task, AI đánh dấu `[x] DONE` và chuyển sang task tiếp theo.

---

## 1. Task Queue & Backlog Overview

| Task ID | Tên Task | Phase | Ưu tiên | Trạng thái | Ghi chú / Blocker |
|---------|----------|-------|---------|------------|-------------------|
| `TASK-001` | Infrastructure & DB Schema Setup (SQLAlchemy/PostgreSQL) | Phase 1 | P0 | `[x] DONE` | Setup FastAPI app, DB models & seeds |
| `TASK-002` | Idempotent Usage Metering (`POST /generate`) | Phase 2 | P0 | `[x] DONE` | MeterService & Idempotency Key |
| `TASK-003` | Quota Enforcement Engine (429 & 402 Handling) | Phase 2 | P0 | `[x] DONE` | Quota boundary checks |
| `TASK-004` | Stripe Webhook Signature Verification | Phase 3 | P1 | `[x] DONE` | Raw body & whsec_ signature check |
| `TASK-005` | Stripe Event Deduplication & Plan Sync (Free -> Pro) | Phase 3 | P1 | `[x] DONE` | ProcessedWebhook & plan flip |
| `TASK-006` | AI Token Pricing Math & Rollup (`GET /usage`) | Phase 4 | P1 | `[x] DONE` | Cost math & Pinned tests |
| `TASK-007` | Submission Pack & 5 Acceptance Probes Verification | Phase 4 | P1 | `[x] DONE` | capstone.yaml, EVIDENCE.md, tests |
| `TASK-008` | Demo Script Rehearsal & Failure Scenario Verification | Phase 5 | P2 | `[x] DONE` | Rehearse 6-min demo flow |
| `TASK-009` | Interactive Frontend Testing Dashboard | Phase 5 | P2 | `[x] DONE` | Glassmorphic dark UI dashboard for API & billing testing |

> **Trạng thái hợp lệ:**
> - `[ ] TODO`: Chưa làm, chờ AI chọn
> - `[/] IN_PROGRESS`: AI đang thực hiện
> - `[x] DONE`: Hoàn thành, đã verify & proof
> - `[!] BLOCKED`: Bị kẹt, cần human intervention

---

## 2. Chi tiết các Tasks (Task Specs)

---

### 📌 TASK-001: Infrastructure & DB Schema Setup (SQLAlchemy/PostgreSQL)

#### Metadata
```
Task ID:         TASK-001
Task Name:       Infrastructure & DB Schema Setup (SQLAlchemy/PostgreSQL)
Phase:           Phase 1 (Design)
Task Type:       feature
Priority:        P0-Critical
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Hệ thống cần cơ sở dữ liệu để lưu trữ thông tin Tenants, Plans, Subscriptions, UsageEvents, IdempotencyRecords và ProcessedWebhooks với dữ liệu được cô lập per Tenant.
- **What:** Tạo cấu trúc thư mục Python FastAPI, thiết lập `docker-compose.yml` cho PostgreSQL, định nghĩa SQLAlchemy 2.0 models, Alembic migrations và script seed DB cho Free & Pro plans.

#### Acceptance Criteria (Tiêu chí hoàn thành)
- [x] File `docker-compose.yml` khởi động được PostgreSQL 15.
- [x] File `app/db/models.py` có đầy đủ 6 models: `Tenant`, `Plan`, `Subscription`, `UsageEvent`, `IdempotencyRecord`, `ProcessedWebhook`.
- [x] Mối quan hệ Unique Constraint `UniqueConstraint("tenant_id", "idempotency_key")` trong `UsageEvent` và `IdempotencyRecord`.
- [x] Run `alembic upgrade head` và `python -m app.db.seed` thành công, tạo gói `Free` (1k API calls, 100k tokens) và gói `Pro` (50k API calls, 10M tokens).

#### Scope (Phạm vi)
- **Files được sửa/tạo:** `app/db/**`, `app/main.py`, `alembic.ini`, `docker-compose.yml`, `requirements.txt`, `.env.example`
- **Files cấm đụng:** H_docs/core/**

#### Verification Commands
```bash
docker-compose up -d
alembic upgrade head
python -m app.db.seed
```

---

### 📌 TASK-002: Idempotent Usage Metering (`POST /generate`)

#### Metadata
```
Task ID:         TASK-002
Task Name:       Idempotent Usage Metering (`POST /generate`)
Phase:           Phase 2 (Core Billing Logic)
Task Type:       feature
Priority:        P0-Critical
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Đảm bảo network retries không gây ra lỗi double-counting (overcharging khách hàng - PROBE 1).
- **What:** Tạo FastAPI middleware/dependency đọc `X-Tenant-ID` và `Idempotency-Key`. Tạo `meter_service.py` kiểm tra duplicate key trước khi ghi nhận event mới. Nếu trùng key -> Trả về cached response cũ, không tạo record mới.

#### Acceptance Criteria
- [x] Endpoint `POST /generate` nhận `X-Tenant-ID` và `Idempotency-Key`.
- [x] Request đầu tiên ghi nhận 1 record vào bảng `UsageEvent` và lưu response vào `IdempotencyRecord`.
- [x] Request thứ 2 gửi trùng `Idempotency-Key` trả về cùng response nhưng KHÔNG tăng thêm record trong `UsageEvent`.
- [x] Integration test pass cho PROBE 1.

#### Scope
- **Files được sửa/tạo:** `app/api/generate.py`, `app/services/meter_service.py`, `app/middlewares/idempotency.py`, `tests/test_idempotency.py`

#### Verification Commands
```bash
pytest tests/test_idempotency.py
```

---

### 📌 TASK-003: Quota Enforcement Engine (429 & 402 Handling)

#### Metadata
```
Task ID:         TASK-003
Task Name:       Quota Enforcement Engine (429 & 402 Handling)
Phase:           Phase 2 (Core Billing Logic)
Task Type:       feature
Priority:        P0-Critical
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Đảm bảo hệ thống từ chối chính xác các request vượt trần hạn ngạch của gói đăng ký (PROBE 2).
- **What:** Viết `quota_service.py` thực hiện kiểm tra `current_usage + requested_usage <= limit` TRƯỚC KHI thực hiện billable action. Trả về `429 Too Many Requests` khi quá hạn ngạch, hoặc `402 Payment Required` khi gói bị past_due/unpaid.

#### Acceptance Criteria
- [x] Request tại đúng mốc boundary (vd 1,000/1,000) được cho phép.
- [x] Request vượt trần boundary (vd 1,001/1,000) bị từ chối với HTTP `429 Too Many Requests` kèm message giải thích.
- [x] Subscription ở trạng thái unpaid/past_due bị từ chối với HTTP `402 Payment Required`.
- [x] Unit & boundary integration tests pass.

#### Scope
- **Files được sửa/tạo:** `app/services/quota_service.py`, `app/middlewares/error_handler.py`, `tests/test_boundary_quota.py`

#### Verification Commands
```bash
pytest tests/test_boundary_quota.py
```

---

### 📌 TASK-004: Stripe Webhook Signature Verification

#### Metadata
```
Task ID:         TASK-004
Task Name:       Stripe Webhook Signature Verification
Phase:           Phase 3 (Stripe Integration)
Task Type:       feature
Priority:        P1-High
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Ngăn chặn kẻ gian gửi webhook giả mạo để chiếm đoạt tài nguyên hoặc thay đổi trạng thái gói trái phép (PROBE 4).
- **What:** Lấy raw request body buffer trong FastAPI router `POST /webhooks/stripe`. Sử dụng `stripe.Webhook.construct_event()` để verify signature với secret `STRIPE_WEBHOOK_SECRET` (`whsec_...`).

#### Acceptance Criteria
- [ ] Endpoint `/webhooks/stripe` đọc đúng raw body bytes.
- [ ] Webhook có signature giả mạo (forged webhook) bị từ chối ngay với HTTP `400 Bad Request`.
- [ ] Webhook hợp lệ từ Stripe CLI pass qua khâu signature check.

#### Scope
- **Files được sửa/tạo:** `app/api/webhooks.py`, `app/services/stripe_service.py`, `tests/test_webhook.py`

#### Verification Commands
```bash
pytest tests/test_webhook.py
```

---

### 📌 TASK-005: Stripe Event Deduplication & Plan Sync (Free -> Pro)

#### Metadata
```
Task ID:         TASK-005
Task Name:       Stripe Event Deduplication & Plan Sync (Free -> Pro)
Phase:           Phase 3 (Stripe Integration)
Task Type:       feature
Priority:        P1-High
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Đảm bảo khi khách hàng thanh toán thành công trong Stripe Checkout test mode, Tenant lập tức được nâng cấp từ Free lên Pro (PROBE 3), và các webhook lặp lại không bị xử lý lại (PROBE 4).
- **What:** Viết logic kiểm tra `event.id` trong bảng `ProcessedWebhook`. Xử lý event `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted` để đồng bộ plan và trạng thái subscription.

#### Acceptance Criteria
- [x] Replay 1 webhook thật 2 lần: Lần 1 xử lý và nâng cấp Tenant, lần 2 bị bỏ qua (return HTTP 200 `already_processed`).
- [x] Event `checkout.session.completed` tự động nâng cấp Tenant từ `Free` -> `Pro`.
- [x] `GET /usage` (hoặc `/generate` quota check) sau nâng cấp lập tức phản ánh trần limit mới của gói Pro.

#### Scope
- **Files được sửa/tạo:** `app/services/stripe_service.py`, `app/api/webhooks.py`, `tests/test_webhook.py`

#### Verification Commands
```bash
pytest tests/test_webhook.py
```

---

### 📌 TASK-006: AI Token Pricing Math & Rollup (`GET /usage`)

#### Metadata
```
Task ID:         TASK-006
Task Name:       AI Token Pricing Math & Rollup (`GET /usage`)
Phase:           Phase 4 (Cost & Hardening)
Task Type:       feature
Priority:        P1-High
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Đảm bảo tính toán chi phí chính xác tuyệt đối theo các quy tắc giá token AI (cached input tokens giá rẻ hơn, reasoning tokens tính như output) và tổng hợp usage theo tháng (PROBE 5).
- **What:** Xây dựng `chat_pricing_config.py` và `cost_service.py`. Tính toán theo công thức micro-cents integer. Tạo endpoint `GET /usage` trả về tổng quan `used`, `limit`, `cost` theo format JSON.

#### Acceptance Criteria
- [x] Logic tính toán chi phí theo chuẩn: `input` ($2.50/1M), `cached_input` ($1.25/1M), `output` ($10.00/1M), `reasoning` ($10.00/1M).
- [x] Pinned pricing tests trong `tests/test_pricing.py` pass 100%.
- [x] API `GET /usage` trả về thông tin chi tiết được cộng dồn chính xác.

#### Scope
- **Files được sửa/tạo:** `app/config/chat_pricing_config.py`, `app/services/cost_service.py`, `app/api/usage.py`, `tests/test_pricing.py`

#### Verification Commands
```bash
pytest tests/test_pricing.py
```

---

### 📌 TASK-007: Submission Pack & 5 Acceptance Probes Verification

#### Metadata
```
Task ID:         TASK-007
Task Name:       Submission Pack & 5 Acceptance Probes Verification
Phase:           Phase 4 (Cost & Hardening)
Task Type:       feature
Priority:        P1-High
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Hoàn thiện toàn bộ submission pack theo quy định của Evaluator (§11) và đảm bảo 5 Acceptance Probes đều pass.
- **What:** Tạo các file `capstone.yaml`, `EVIDENCE.md`, `BUILDLOG.md`, `.env.example`, và `README.md` (kèm sơ đồ kiến trúc ASCII và hướng dẫn cài đặt). Chạy toàn bộ Pytest test suite.

#### Acceptance Criteria
- [x] Đủ 5 files submission pack: `README.md`, `capstone.yaml`, `EVIDENCE.md`, `BUILDLOG.md`, `.env.example`.
- [x] `capstone.yaml` có định dạng YAML hợp lệ với các lệnh `run: uvicorn app.main:app`, `seed: python -m app.db.seed`, `test: pytest`.
- [x] Tất cả 5 Probes test đều GREEN.
- [x] Copy evidence kết quả test vào `EVIDENCE.md`.

#### Scope
- **Files được sửa/tạo:** `capstone.yaml`, `EVIDENCE.md`, `BUILDLOG.md`, `.env.example`, `README.md`

#### Verification Commands
```bash
pytest
```

---

### 📌 TASK-008: Demo Script Rehearsal & Failure Scenario Verification

#### Metadata
```
Task ID:         TASK-008
Task Name:       Demo Script Rehearsal & Failure Scenario Verification
Phase:           Phase 5 (Demo Prep)
Task Type:       chore
Priority:        P2-Medium
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-07
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Chuẩn bị sẵn sàng cho buổi demo 6 phút với Evaluator/Mentor theo đúng kịch bản §13 từ Capstone PDF.
- **What:** Tạo script seed dữ liệu giả lập Tenant gần chạm mốc trần Quota, diễn tập 6 bước demo: trúng boundary 429, retry idempotency, nâng cấp gói Stripe Checkout, chặn forged webhook 400 và rollup GET /usage.

#### Acceptance Criteria
- [x] Kịch bản demo 6 phút diễn ra mượt mà theo đúng 6 bước trong §13.
- [x] Demo xử lý gracefully tình huống failure khi chạm trần limit.

#### Scope
- **Files được sửa/tạo:** `app/db/demo_seed.py`, `demo-rehearsal.sh`

#### Verification Commands
```bash
python -m app.db.demo_seed
```

---

### 📌 TASK-009: Interactive Frontend Testing Dashboard

#### Metadata
```
Task ID:         TASK-009
Task Name:       Interactive Frontend Testing Dashboard
Phase:           Phase 5 (Demo Prep)
Task Type:       feature
Priority:        P2-Medium
Trạng thái:      [x] DONE
Ngày tạo:        2026-08-08
```

#### Bối cảnh & Mục tiêu (Why & What)
- **Why:** Cung cấp giao diện Web trực quan (frontend) để người dùng và evaluator test trực tiếp các tính năng Usage Metering, Quota Enforcement (429/402), Idempotency Retry và Stripe Plan Rollup.
- **What:** Tạo `app/static/index.html` tích hợp CSS Glassmorphism dark mode & Vanilla JS, cập nhật `app/main.py` thêm CORSMiddleware và static mount/route `/`.

#### Acceptance Criteria
- [x] Giao diện Web hiển thị đẹp mắt, dark mode, responsive, có Google Fonts (Inter).
- [x] Đổi Tenant (`tenant_demo_01`, `tenant_free_01`, `tenant_pro_01`) và tải dữ liệu rollup `/usage` hiển thị progress bar & chi phí.
- [x] Gửi request `POST /generate` với Prompt, Token breakdown, và Idempotency Key.
- [x] Thử lại chính Idempotency Key đó hiển thị Cached Response (đảm bảo không bị double counting).
- [x] Presets nhanh cho test Boundary (#1,000 call) và Quota Exceeded (#1,001 call trả về 429).

