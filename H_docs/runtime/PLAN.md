# PLAN
# Kế hoạch thực thi — TASK-008: Demo Script Rehearsal & Failure Scenario Verification

> **Trạng thái:** RUNTIME (Auto-generated) | **Tạo bởi:** AI | **Ngày tạo:** 2026-08-07 23:16

---

## Task Reference

```
Task ID:    TASK-008
Task Name:  Demo Script Rehearsal & Failure Scenario Verification
Spec:       Chuẩn bị sẵn sàng cho buổi demo 6 phút với Evaluator/Mentor theo kịch bản §13 Capstone PDF. Tạo script seed demo_seed.py và script demo-rehearsal.sh diễn tập 6 bước demo chính xác.
```

---

## Spec (Đặc tả)

### Acceptance Criteria
- [ ] File `app/db/demo_seed.py` được tạo để seed tenant demo (`tenant_demo_01`) với gói Free đã dùng 999/1,000 API calls (sẵn sàng cho boundary test).
- [ ] File `demo-rehearsal.sh` (hoặc test runner rehearsal) thực hiện mượt mà 6 bước demo §13:
  1. **Step 1 (Quota Boundary Exceeded)**: Gọi billable API `POST /generate` đến mốc 1,000 (cho phép) và request 1,001 (trả về HTTP `429 Too Many Requests` với message rõ ràng).
  2. **Step 2 (Idempotency Retries)**: Retry lại request thứ 1,001 với cùng `Idempotency-Key` ➔ Trả về cached response cũ, không tăng `UsageEvent` count (Double counting prevention).
  3. **Step 3 (Stripe Test-Mode Upgrade)**: Giả lập Stripe Checkout webhook `checkout.session.completed` ➔ Tenant `tenant_demo_01` nâng cấp lên gói Pro ➔ Request tiếp theo thành công (HTTP 200 OK với limit 50,000 calls).
  4. **Step 4 (Forged Webhook & Deduplication)**: Gửi forged webhook signature ➔ Trả về HTTP `400 Bad Request`. Replay webhook hợp lệ lần 2 ➔ Trả về `already_processed` (Deduplication).
  5. **Step 5 (Usage & Cost Rollup)**: Gọi `GET /usage` ➔ Trả về JSON chứa `used`, `limit`, `cost` (cents & formatted) khớp chính xác với pinned pricing rules.
  6. **Step 6 (Closing Statement Verification)**: In thông điệp tổng kết kiểm thử mượt mà.
- [ ] Run `python -m app.db.demo_seed` và `bash demo-rehearsal.sh` pass 100%.

### Verification Commands
```bash
python -m app.db.demo_seed
bash demo-rehearsal.sh
```

---

## Execution Steps

### Step 1: Demo Seed Script (`app/db/demo_seed.py`)
- **Mục tiêu:** Tạo script `app/db/demo_seed.py` thiết lập trạng thái tenant demo `tenant_demo_01` gần chạm trần Quota (999/1,000 calls).
- **Files tạo:** `app/db/demo_seed.py`
- **Exit condition:** Script chạy không lỗi, log xác nhận `tenant_demo_01` đã seeded.

### Step 2: Interactive 6-Step Rehearsal Script (`demo-rehearsal.sh`)
- **Mục tiêu:** Xây dựng script `demo-rehearsal.sh` tự động hóa diễn tập 6 bước demo với output màu sắc rõ ràng và kiểm tra HTTP status/response logic.
- **Files tạo:** `demo-rehearsal.sh`
- **Exit condition:** Script kết thúc thành công với return code 0.

### Step 3: Rehearsal Execution & Verification
- **Mục tiêu:** Chạy thử `demo-rehearsal.sh` và `pytest` để đảm bảo 100% test suite và demo rehearsal xanh.
- **Exit condition:** 6/6 demo steps green, pytest 100% pass.

---

## Iteration Budget

```
Estimated iterations: 1
Maximum allowed:      2
Context refresh at:   Iteration 2
```

---

## Plan Revision History

| Revision | Ngày | Lý do thay đổi |
|----------|------|----------------|
| v1 | 2026-08-07 | Tạo plan cho TASK-008 |
