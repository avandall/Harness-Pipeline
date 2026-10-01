# ORIGINAL TASKS & HUMAN INTENT
# Ý định gốc, Tôn chỉ kỹ thuật & Danh sách tác vụ ban đầu từ Con người

> **Trạng thái:** CONTEXT (Immutable Ground Truth Anchor) | **Cập nhật:** [YYYY-MM-DD]
>
> 👤 **HUMAN FILLS THIS FILE BEFORE RUNNING PLAN-REFINE.**
> Đây là "Mỏ neo ý định gốc" (Human Intent Anchor). File này đóng vai trò như Hiến pháp nền tảng.
> 🤖 **DUAL-MODEL INSTRUCTION (PLAN-REFINE):**
> Cả 2 model **Critic** và **Planner** trong `plan-refine.sh` BẮT BUỘC phải đọc file này đầu tiên. Mọi phản biện, chia nhỏ task, bổ sung test strategy và tối ưu hóa đều được phép NHƯNG **tuyệt đối không được phép làm lệch tôn chỉ, mục tiêu và ràng buộc cốt lõi** đã được con người nêu rõ tại đây.

---

## 1. Tôn chỉ Cốt lõi & Ý định Ban đầu (North Star & Human Intent)

- **Mục tiêu cao nhất (Primary Goal):**
  [Mô tả mục tiêu tối thượng mà hệ thống/tính năng này phải đạt được sau khi chạy xong]
- **Vấn đề cốt lõi cần giải quyết (Core Problem):**
  [Nêu rõ bài toán, nỗi đau hoặc yêu cầu nghiệp vụ bắt buộc phải xử lý]
- **Kỳ vọng đầu ra hoàn chỉnh (Target Outcome):**
  [Mô tả sản phẩm, endpoint, giao diện hoặc luồng xử lý hoạt động hoàn chỉnh ra sao]

---

## 2. Yêu cầu & Quyết định Kỹ thuật Bắt buộc (Non-Negotiable Technical Directives)

> ⚠️ Các quyết định kỹ thuật dưới đây là cố định từ con người. AI **không được tự ý thay thế** bằng framework/thư viện khác trừ khi phát hiện lỗi bảo mật nghiêm trọng.

- **Ngôn ngữ & Runtime:** [Ví dụ: Python 3.11+ / Node.js 20+ / Go 1.22...]
- **Frameworks & Thư viện chủ đạo:** [Ví dụ: FastAPI, Pydantic v2, SQLAlchemy, React, Tailwind...]
- **Mô hình Kiến trúc (Architecture Pattern):** [Ví dụ: Clean Architecture / Modular Monolith / Event-driven / CLI...]
- **Cơ chế Lưu trữ / Database:** [Ví dụ: PostgreSQL / SQLite / Redis / In-memory state...]
- **Giao thức & Giao tiếp (Protocols):** [Ví dụ: REST JSON API / gRPC / WebSocket / CLI args...]

---

## 3. Ranh giới Cấm kỵ & Điều kiện Không thỏa hiệp (Hard Guardrails & Forbiddens)

- 🚫 **Những gì TUYỆT ĐỐI KHÔNG làm (Out of Scope / Forbidden):**
  - [Điều cấm 1: Ví dụ - Không tự ý cài đặt thêm ORM nặng nề nếu chỉ cần raw SQL]
  - [Điều cấm 2: Ví dụ - Không sửa đổi cấu trúc bảng A khi đang làm tính năng B]
  - [Điều cấm 3: Ví dụ - Tuyệt đối không xóa bỏ các test contracts hiện có]
- 🛡️ **Ràng buộc về chi phí & tài nguyên (Resource & Token Budget):**
  - [Ví dụ: Giữ prompt ngắn gọn, không spam log, không gọi external API trả phí không cần thiết]

---

## 4. Danh sách Tác vụ Sơ bộ Ban đầu (Original Draft Tasks List)

> 💡 Đây là danh sách các bước ban đầu do con người định hình. Khi `plan-refine` chạy:
> - **ĐƯỢC PHÉP:** Tách nhỏ task nếu task chạm quá nhiều files (>5-8 files), sắp xếp lại thứ tự dependencies (Bottom-Up), bổ sung tiêu chí kiểm thử (TDD test cases).
> - **CẤM:** Tự ý xóa bỏ các chức năng/tasks đã được con người nêu dưới đây.

| STT | Tên Task Dự kiến | Mục tiêu & Phạm vi chính | Test Target sơ bộ | Ghi chú của Con người |
|:---:|------------------|--------------------------|-------------------|-----------------------|
| 1 | [Task 1: Ví dụ - Khởi tạo Project Scaffolding & Manifest] | [Mô tả ngắn phạm vi] | static_check | Bắt buộc chạy đầu tiên |
| 2 | [Task 2: Ví dụ - Xây dựng Data Models & DB Schemas] | [Mô tả ngắn phạm vi] | tests/unit/test_models.py | [Ghi chú kỹ thuật nếu có] |
| 3 | [Task 3: Ví dụ - Cài đặt Core Service Business Logic] | [Mô tả ngắn phạm vi] | tests/unit/test_service.py | [Ghi chú kỹ thuật nếu có] |
| 4 | [Task 4: Ví dụ - Xây dựng API Endpoints & Routers] | [Mô tả ngắn phạm vi] | tests/integration/test_api.py | [Ghi chú kỹ thuật nếu có] |

---

## 5. Tiêu chuẩn Nghiệm thu Thành công từ Con người (Human Definition of Done)

- [ ] [Tiêu chí 1: Ví dụ - Toàn bộ API endpoints hoạt động trả về đúng mã HTTP 200/201 kèm schema]
- [ ] [Tiêu chí 2: Ví dụ - Bộ kiểm thử tự động đạt 100% PASS không có bất kỳ test nào bị skip/mock giả]
- [ ] [Tiêu chí 3: Ví dụ - Kiểm tra Lint và Type Check pass tuyệt đối không có cảnh báo]
