# GLOSSARY
# Từ điển thuật ngữ — Định nghĩa các khái niệm trong hệ thống Harness

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0
>
> Khi gặp thuật ngữ không quen trong bất kỳ doc nào, tìm ở đây trước.

---

## A

**Acceptance Criteria (Tiêu chí chấp nhận)**
Định nghĩa rõ ràng những gì phải đúng để một task được coi là hoàn thành. Phải đo lường được và verify được.

**Adversarial Review (Review đối lập)**
Phương pháp review trong đó reviewer chủ động tìm cách phá vỡ giải pháp thay vì chỉ confirm những gì hoạt động. Xem `REVIEW_PROTOCOL.md`.

**Atomic (Nguyên tử)**
Một đơn vị công việc không thể chia nhỏ hơn: hoặc hoàn thành hoàn toàn, hoặc rollback hoàn toàn. Không có trạng thái "nửa vời".

---

## B

**Backpressure (Áp lực ngược)**
Cơ chế kiểm soát khi hệ thống bị overload: AI dừng lại thay vì tiếp tục làm những việc có thể sai. Trigger bởi ≥2 failures liên tiếp.

**BLOCKED State (Trạng thái bị chặn)**
Trạng thái khi AI không thể tiến tiếp mà không có quyết định từ human. Được signal bằng file `BLOCKED.md`.

**Boundaries (Giới hạn)**
Phạm vi quyền hạn của AI trong một task cụ thể. Được định nghĩa trong `H_docs/context/BOUNDARIES.md`.

---

## C

**Context Budget (Ngân sách context)**
Giới hạn số lượng files/thông tin AI đọc trước mỗi iteration để tránh context overflow. Mặc định: 5 files ưu tiên.

**Context Rot (Mục nát context)**
Hiện tượng AI bắt đầu hallucinate hoặc nhầm lẫn sau khi conversation quá dài. Ralph Loop giải quyết bằng cách restart agent mỗi iteration.

---

## E

**Exit Code (Mã thoát)**
Kết quả của mỗi iteration: `EXIT_DONE`, `EXIT_CONTINUE`, `EXIT_BLOCKED`, `EXIT_RETRY`. Xem `HARNESS_PROTOCOL.md`.

---

## F

**Fresh Context (Context mới)**
Trạng thái bắt đầu mỗi iteration: AI không nhớ conversation trước, chỉ đọc từ filesystem. Đây là thiết kế cố ý, không phải hạn chế.

---

## H

**Harness (Bộ khai thác)**
Hệ thống kiểm soát, định hướng và giám sát AI agent. Bao gồm: docs, scripts, protocols, và quy trình. Tương tự "test harness" nhưng cho AI workflow.

**Harness Engineering (Kỹ thuật khai thác)**
Ngành kỹ thuật chuyên thiết kế và xây dựng hệ thống để AI agent hoạt động tự trị, đáng tin cậy, và có thể kiểm soát.

---

## I

**Inter-Agent Review (Review liên AI)**
Phương pháp dùng 2 AI agents: một xây dựng, một phê bình. Xem `REVIEW_PROTOCOL.md` phần 3.

**Iteration (Vòng lặp)**
Một chu kỳ đầy đủ của Ralph Loop: bắt đầu với fresh context, thực thi một unit of work, verify, update runtime docs trên filesystem. Commit git chỉ xảy ra khi task `[x] DONE`, không phải sau mỗi iteration.

---

## M

**MCP (Model Context Protocol)**
Giao thức chuẩn để AI model kết nối với external tools và services. Xem danh sách MCPs được phép trong `TOOL_REGISTRY.md`.

**Minimal Footprint (Dấu chân tối thiểu)**
Nguyên tắc: chỉ thay đổi những gì cần thiết cho task hiện tại. Không "tiện tay" sửa thêm.

---

## R

**Ralph Loop**
Vòng lặp tự trị lấy cảm hứng từ nhân vật Ralph Wiggum (The Simpsons): kiên trì qua nhiều iterations, mỗi lần bắt đầu fresh, dùng filesystem làm memory, git làm safety net.

**Runtime Docs (Tài liệu chạy)**
Các docs được AI tự tạo trong `H_docs/runtime/` trong quá trình thực thi task. Bao gồm PLAN.md, STATUS.md, PROGRESS_LOG.md, v.v.

---

## S

**State Machine (Máy trạng thái)**
Mô hình quản lý trạng thái của task: `INIT → PLANNING → EXECUTING → REVIEWING → COMMITTING → DONE/BLOCKED`. Xem `HARNESS_PROTOCOL.md`.

**Spec (Đặc tả)**
Định nghĩa chính xác input, output, và behavior mong đợi của một feature/task. Phải được viết TRƯỚC khi code.

---

## V

**Verification (Kiểm chứng)**
Quá trình prove một giải pháp hoạt động đúng với bằng chứng cụ thể (test output, API response, screenshot). Không phải chỉ "nhìn có vẻ đúng".

---

## W

**Work Board (Bảng công việc)**
Danh sách các task được track, tương tự Kanban board nhưng dưới dạng markdown file (`PLAN.md`). Giúp AI luôn biết đang ở đâu và bước tiếp theo là gì.
