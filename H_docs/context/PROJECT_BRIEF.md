# PROJECT BRIEF
# Tóm tắt dự án — Usage Metering & Billing Engine

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** 2026-08-07 (Based on FlyRank Capstone Brief PDF - 12 Pages)

---

## 1. Tên & Mô tả Dự án

```
Tên dự án:        Usage Metering & Billing Engine
Mô tả ngắn:      Backend service đo lường mức độ sử dụng (usage metering), thực thi hạn ngạch gói dịch vụ (quota enforcement), tính toán chi phí token AI chính xác (AI-token cost math) và đồng bộ trạng thái đăng ký qua Stripe Webhooks (test mode).
Repo Name:        flyrank-capstone-metering-billing
Track:            FlyRank Internship - Backend Track (Capstone Brief)
Độ khó:           Medium (Tập trung vào độ chính xác - Correctness & Precision)
Thời gian ước tính: 30 - 45 focused hours
Tech Stack:       $0 Stack (Python 3.11+ / FastAPI, PostgreSQL Docker, Stripe Test Mode + Stripe CLI)
```

---

## 2. Mục tiêu Kinh doanh (Business Goals) & Vấn đề Cốt lõi

### Vấn đề hiện tại trong các hệ thống SaaS Billing
Mọi sản phẩm SaaS đều phải trả lời 3 câu hỏi cốt lõi:
1. **Khách hàng đã dùng bao nhiêu tài nguyên?** (*How much has this customer used?*)
2. **Khách hàng phải trả bao nhiêu tiền?** (*How much should they pay?*)
3. **Khách hàng đã chạm trần hạn ngạch chưa?** (*Have they reached their plan limits?*)

Nhiều hệ thống SaaS gặp phải các lỗi nghiêm trọng như:
- **Double-charging**: Khi network retries từ client khiến request bị lặp lại và ghi nhận usage trùng lặp.
- **Thiếu Idempotency-Key**: Không nhận biết được request đã được xử lý thành công trước đó.
- **Duplicate Webhook Events**: Xử lý lặp lại webhook từ Stripe dẫn đến cập nhật trạng thái sai lệch.
- **Chạm mốc Boundary không chính xác**: Không xử lý đúng tại mốc giới hạn (ví dụ: request thứ 1,000 trên limit 1,000).
- **Tính sai chi phí AI tokens**: Không phân biệt giữa `input_tokens`, `cached_input_tokens` (giá rẻ hơn), `output_tokens` và `reasoning_tokens` (tính theo giá `output_tokens`).
- **Sai HTTP Status Codes**: Trả về 500 Server Error thay vì `429 Too Many Requests` (vượt quota) hoặc `402 Payment Required` (cần nâng cấp/gói quá hạn).

### Giải pháp
Xây dựng một **Billing & Metering Engine** an toàn, chính xác và có bằng chứng xác minh (verifiable guarantees):
- **Idempotent Usage Metering**: Đảm bảo mỗi billable request retried chỉ ghi nhận đúng 1 usage event duy nhất nhờ `Idempotency-Key`.
- **Honest Quota Enforcement**: Kiểm tra quota trước khi thực thi action. Trả về đúng HTTP `429 Too Many Requests` (vượt limit) hoặc `402 Payment Required` (cần upgrade plan).
- **Accurate Cost Calculation**: Tính toán chi phí chính xác theo loại token (input tokens, cached input tokens giá rẻ hơn, output tokens, và reasoning tokens tính như output tokens). Lưu trữ tiền tệ dưới dạng số nguyên (cents/micro-units).
- **Stripe Subscription Sync**: Tích hợp Stripe Checkout test mode & Webhook handler có verify cryptographic signature + event deduplication để đồng bộ plan (Free/Pro).

---

## 3. Ground Rules & Constraints (§3 từ Capstone PDF)

| Quy tắc | Chi tiết bắt buộc |
|---------|-------------------|
| **1. Dedicated Public Repo** | Repository công khai từ ngày đầu: `flyrank-capstone-metering-billing`. Không dùng repo chung assignment. |
| **2. $0 Stack (No Credit Card)** | 100% sử dụng công cụ miễn phí, không yêu cầu thẻ tín dụng (Python/FastAPI, Docker PostgreSQL, Stripe Test Mode). |
| **3. Stripe Test Mode Only** | Chỉ dùng Stripe Test Mode (`sk_test_...`, test card `4242 4242 4242 4242`). Không bao giờ chuyển sang Live mode. |
| **4. Secrets in `.env` Only** | Mọi API key & Webhook secret (`whsec_...`) nằm trong `.env` (được `.gitignore`). Commit secret là lỗi repo-hygiene nghiêm trọng. |
| **5. Money Stored as Integers** | Lưu trữ tiền dưới dạng số nguyên (cents hoặc micro-units), KHÔNG DÙNG float/double để tránh sai số IEEE 754. |
| **6. Local Webhook via Stripe CLI** | Dùng Stripe CLI (`stripe listen --forward-to localhost:3000/webhooks/stripe`, `stripe trigger`) để replay event locally, không cần ngrok/public tunnel. |
| **7. AI-Assisted & Owned** | Được phép dùng AI nhưng phải duy trì `BUILDLOG.md` trung thực và có khả năng giải thích code khi được hỏi. |

---

## 4. Phạm vi Dự án (Project Scope) & 4 Key Concerns

### Gói dịch vụ & Hạn ngạch (Plans & Quotas)
- **Tenant**: Mỗi khách hàng thuộc về 1 Tenant (Multi-tenant data isolation).
- **Free Plan**: 1,000 API calls / tháng, 100,000 AI tokens / tháng.
- **Pro Plan**: 50,000 API calls / tháng, 10,000,000 AI tokens / tháng (Higher limits).

### 4 Key Concerns của Hệ thống
1. **Usage Metering (Đo lường mức độ sử dụng)**:
   - Mọi billable action (`POST /generate`) ghi nhận 1 usage event thuộc về Tenant.
   - Cơ chế Idempotency: `Idempotency-Key` header + unique DB constraint `(tenant_id, idempotency_key)` đảm bảo cùng request retry chỉ tạo đúng 1 event.
2. **Quota Enforcement (Thực thi hạn ngạch trung thực)**:
   - Kiểm tra: `current_usage + requested_usage <= plan_limit` TRƯỚC KHI cho phép action.
   - `429 Too Many Requests`: Khi quá số lượng usage cho phép của gói hiện tại.
   - `402 Payment Required`: Khi gói cần nâng cấp hoặc bị hết hạn / chưa thanh toán.
3. **Cost Calculation (Tính toán chi phí token AI)**:
   - API calls: Tính chi phí cố định/gói.
   - AI Tokens breakdown:
     - `input_tokens`: Đơn giá chuẩn.
     - `cached_input_tokens`: Đơn giá giảm (discounted cached rate).
     - `output_tokens`: Đơn giá output.
     - `reasoning_tokens`: Bắt buộc đếm và tính theo đơn giá `output_tokens`.
   - Các category token KHÔNG ĐƯỢC cộng dồn trực tiếp rồi nhân 1 giá chung. Pricing constants được định nghĩa cứng trong config và test bằng pinned tests (`chat_pricing_config.py`).
4. **Stripe Subscription Integration (Đồng bộ Stripe Test Mode)**:
   - Flow: Tenant chọn Pro ➔ Stripe Checkout Session ➔ Subscription created.
   - Webhook endpoint (`/webhooks/stripe`): Lắng nghe `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`.
   - Bắt buộc: Verify chữ ký Webhook (`whsec_`), chống duplicate processing bằng `event.id`, cập nhật trạng thái Tenant plan (Free ↔ Pro).

---

## 5. Kiến trúc Hệ thống (Architecture Overview)

```
                       [ Client / Billable Request ]
                                     │
                                     ▼
                ┌──────────────────────────────────────┐
                │        Billable API Endpoint         │
                │         (POST /generate)             │
                └───────────────────┬──────────────────┘
                                     │ Header: X-Tenant-ID, Idempotency-Key
                                     ▼
                ┌──────────────────────────────────────┐
                │            MeterService              │
                │ 1. Check duplicate idempotency key   │
                │    ├── Duplicate? -> Return cached   │
                │ 2. Perform Quota Check               │
                │    ├── Exceeded? -> Return 429 / 402  │
                │    └── Allowed?  -> Store event      │
                └───────────────────┬──────────────────┘
                                     │
                                     ▼
                      ┌───────────────────────────┐
                      │    PostgreSQL Database    │
                      │  - tenants                │
                      │  - plans                  │
                      │  - subscriptions          │
                      │  - usage_events           │
                      │  - processed_webhooks     │
                      └───────────────────────────┘
                                     ▲
                                     │
   GET /usage ──► [ Usage Rollup Service ] ──► { used, limit, cost }
                                     ▲
                                     │
   [ Stripe Test Checkout ] ──► [ /webhooks/stripe ]
                                 ├─ Verify signature (Forged -> 400)
                                 ├─ Deduplicate event (Replay -> ignored)
                                 └─ Update tenant plan / status
```

---

## 6. Definition of Done Checklist (§6 từ Capstone PDF)

Hệ thống được coi là **DONE** khi tất cả các checkbox sau được tick và có minh chứng trong `EVIDENCE.md`:

### METERING
- [ ] Billable action tạo ra chính xác 1 usage event, ngay cả khi retries — deduplicated bằng idempotency key.
- [ ] Test suite chứng minh lỗi double-counting không thể xảy ra.

### QUOTAS
- [ ] Usage được kiểm tra với plan limits của tenant; requests vượt limit bị từ chối.
- [ ] Responses trả về đúng status code (`429` / `402`) kèm message giải thích lý do rõ ràng.

### COST CALCULATION
- [ ] Usage hàng tháng được tổng hợp (rollup) thành số tiền chi phí per tenant.
- [ ] Logic tính giá token AI xử lý đúng `cached_input_tokens`, `reasoning_tokens` (tính như output), và `output_tokens`.
- [ ] Pricing constants được ghim (pinned) trong config và có unit test bảo vệ.

### STRIPE INTEGRATION
- [ ] Subscription checkout hoạt động end-to-end trong Stripe test mode.
- [ ] Webhook verify chữ ký (`whsec_`), bỏ qua duplicate events, và cập nhật tenant plan/status.

### DATA MODEL, TESTS & DOCUMENTATION
- [ ] Database bao gồm: tenants, plans, subscriptions, usage events; dữ liệu khách hàng được cô lập per tenant.
- [ ] Tests bao phủ: duplicate usage prevention, quota boundary cases (at / just under / over limit), cost calculations, forged webhook rejection (400), duplicate webhook handling.
- [ ] README + architecture diagram + setup instructions + bộ 5 files submission pack đầy đủ.

---

## 7. Các Giai đoạn Phát triển (Phase-by-Phase Roadmap - §8)

```
Phase 1: Design (4-6h)
 Gate: Design doc signed off (DB schema: tenants, plans, subscriptions, usage_events; plans + quotas; API contracts & idempotency strategy).

Phase 2: Core Billing Logic (9-13h)
 Gate: Double-count test passes; boundary returns 429/402.

Phase 3: Stripe Integration (8-12h)
 Gate: Test Checkout flips tenant Free -> Pro via verified webhook.

Phase 4: Cost & Finalization (7-10h)
 Gate: /usage numbers match pinned tests; all tests green; README, capstone.yaml, EVIDENCE.md complete.

Phase 5: Demo Prep (2-3h)
 Gate: 6-minute demo rehearsed twice; forged-webhook failure moment ready.
```

---

## 8. Đánh giá & 5 Acceptance Probes (§12 từ Capstone PDF)

### Layer 1: Submission Pack (Machine-Checkable)
Yêu cầu 5 files bắt buộc: `README.md`, `capstone.yaml`, `EVIDENCE.md`, `BUILDLOG.md`, `.env.example`. Lệnh `run` khởi động được server và `test` chạy pass 100%.

### Layer 2: Acceptance Probes (Pass/Fail Behavioral)
- **PROBE 1**: Gửi cùng 1 billable request 2 lần với cùng `Idempotency-Key` ➔ Chỉ tạo 1 usage event; response thứ 2 giống hệt response thứ 1.
- **PROBE 2**: Gọi API đến đúng mốc limit (vd 1,000/1,000) ➔ Request tại boundary xử lý đúng rule; request thứ 1,001 bị từ chối với `429` / `402` kèm message rõ ràng.
- **PROBE 3**: Hoàn thành Stripe Test Checkout ➔ Webhook nâng cấp Tenant từ Free ➔ Pro; `GET /usage` phản ánh limit mới.
- **PROBE 4**: Gửi forged webhook (chữ ký sai) ➔ Trả về `400 Bad Request`. Replay webhook hợp lệ 2 lần ➔ Xử lý đúng 1 lần, lần 2 bị bỏ qua.
- **PROBE 5**: Chạy pinned pricing unit tests ➔ Logic cached input & reasoning tokens ra số tiền chính xác 100%; `GET /usage` khớp số tiền.

### Layer 3: Evaluation Rubric
- **Architecture (x3)**: Clean layers (data / logic / HTTP separated).
- **Correctness (x3)**: Happy path & edge cases handled; all 5 probes pass.
- **Resilience (x3)**: Chịu đựng bad input, duplicate requests, network retries.
- **Security (x2)**: Real tenant auth context, validated payload, secrets encrypted/in env.
- **AI Cost & Grounding (x2)**: Token usage tracked & capped, correct pricing rules.
- **Testing (x2)**: Edge cases tested deterministically.
- **Communication (x2)**: README & diagram rõ ràng, minh minh về giới hạn.

---

## 9. Script Kịch bản Demo 6 Phút (§13 từ Capstone PDF)

1. Thực hiện billable API calls cho đến khi Tenant chạm mốc Quota limit ➔ Hiển thị response `429 Too Many Requests` có giải thích.
2. Retry lại chính request đó với cùng `Idempotency-Key` ➔ Chứng minh usage event KHÔNG bị tăng thêm (No double counting).
3. Thực hiện Stripe Test-Mode Checkout ➔ Webhook bắn về server ➔ Tenant chuyển từ Free sang Pro thành công.
4. Gửi một forged webhook (chữ ký giả) ➔ Trả về `400 Bad Request`. Replay lại webhook thật ➔ Bị bỏ qua do duplicate.
5. Kiểm tra `GET /usage` ➔ Cho thấy used / limit / cost được cộng dồn chính xác khớp với pinned cost tests.
6. Closing statement: *"Usage, money, and customer access stay correct under retries, failures, and real-world conditions."*

---

## 10. External Dependencies

| Service/System | Vai trò | Contact/Docs |
|----------------|---------|-------------|
| **Stripe API (Test Mode)** | Quản lý Checkout Session & Subscriptions | https://stripe.com/docs/api |
| **Stripe CLI** | Forward & Replay webhooks locally (`stripe listen`, `stripe trigger`) | https://stripe.com/docs/stripe-cli |
| **PostgreSQL (Docker/Local)** | Cơ sở dữ liệu lưu trữ Tenants, Plans, Subscriptions, Usage Events | https://www.postgresql.org/docs/ |

---

## 11. Ghi chú thêm

- **Zero-Dollar Promise**: Toàn bộ dự án được thực hiện bằng công cụ miễn phí, không yêu cầu thẻ tín dụng.
- **Evidence-Driven**: Mọi checkbox trong Definition of Done cần đi kèm log / test output được paste vào `EVIDENCE.md`.


