# 📋 INTERVIEW PLAN & BLUEPRINT SPECIFICATION
# Kế hoạch Nghiệp vụ & Bản thiết kế sau Phỏng vấn với LLM

> **Trạng thái:** DRAFT / PENDING_CRITIQUE | **Cập nhật:** [YYYY-MM-DD]
>
> 👤 **DÀNH CHO NGƯỜI DÙNG (HUMAN WORKFLOW):**
> File này dùng để lưu lại toàn bộ kế hoạch, giải pháp và kiến trúc sau khi bạn đã **phỏng vấn (interview) 1 bài toán/tính năng với LLM**.
> Thay vì phải mở 2 cửa sổ chat để 2 LLM tự tranh cãi thủ công, bạn chỉ cần đưa nội dung buổi phỏng vấn vào file này và chạy:
> ```bash
> ./pipeline/scripts/plan-refine.sh
> ```
> 🤖 **CƠ CHẾ PHẢN BIỆN 2 GIAI ĐOẠN CỦA PLAN-REFINE:**
> 1. **Giai đoạn 1 (Ưu tiên số 1 — Bắt buộc làm trước):** Critic sẽ đọc trực tiếp file `INTERVIEW_PLAN.md` này để **phản biện toàn diện kế hoạch của user** (tìm lỗ hổng logic, thiếu sót nghiệp vụ, giả định sai, kịch bản lỗi chưa tính tới, đánh giá tính khả thi). Planner sẽ điều chỉnh lại kế hoạch cho đến khi không còn lỗ hổng.
> 2. **Giai đoạn 2 (Thực hiện sau):** Sau khi kế hoạch nghiệp vụ đã vững chắc, Critic mới chuyển sang **phản biện các chi tiết kỹ thuật** (kích thước task atomic <= 5-8 files, thứ tự phụ thuộc bottom-up, test strategy TDD Red-Green, cấu trúc `Tasks_list.md`).

---

## 💡 HƯỚNG DẪN QUY TRÌNH PHỎNG VẤN & GHI KẾ HOẠCH

### Bước 1: Phỏng vấn bài toán với LLM (Prompt Mẫu)
Mở cửa sổ chat với bất kỳ LLM nào (ChatGPT / Claude / Gemini), sao chép và dán prompt sau:

```markdown
Tôi đang muốn lên kế hoạch giải quyết bài toán / phát triển tính năng: "[MÔ TẢ BÀI TOÁN HOẶC TÍNH NĂNG CỦA BẠN]".

Hãy đóng vai trò là một Principal Solution Architect và phỏng vấn tôi theo quy trình sau:
1. Đặt ra từ 3-5 câu hỏi sắc bén nhất để làm rõ:
   - Bản chất bài toán nghiệp vụ và các ràng buộc cốt lõi.
   - Các trường hợp lỗi tiềm ẩn (failure modes), edge cases và tác động phụ (side effects).
   - Phương án kiến trúc đề xuất và các phương án thay thế.
   - Ranh giới phạm vi: Những gì NÊN LÀM và những gì TUYỆT ĐỐI KHÔNG LÀM.
2. Sau khi tôi trả lời, hãy tổng hợp lại thành một Bản Kế Hoạch Đầy Đủ (Blueprint) bao gồm:
   - Bài toán & Mục tiêu.
   - Phương án giải pháp đã chọn (kèm lý do).
   - Luồng nghiệp vụ chuẩn (Happy path) và các luồng ngoại lệ (Edge cases).
   - Phân rã các giai đoạn triển khai sơ bộ.
   - Những giả định ngầm hoặc điểm rủi ro cần rà soát kỹ.
   - Tiêu chí nghiệm thu thành công.
Hãy bắt đầu đặt câu hỏi phỏng vấn tôi ngay bây giờ!
```

### Bước 2: Điền nội dung sau phỏng vấn vào các mục bên dưới
Sau khi kết thúc buổi phỏng vấn, sao chép kết quả đã thống nhất vào **Mục 1 đến Mục 6** trong file này. Hãy giữ nguyên các nghi vấn hoặc giả định ngầm nếu bạn chưa hoàn toàn chắc chắn — `plan-refine.sh` sẽ dùng Lead Architect Critic để mổ xẻ và hoàn thiện chúng.

### Bước 3: Khởi chạy phản biện tự động 2 giai đoạn
Chạy lệnh trên terminal (WSL/Linux):
```bash
./pipeline/scripts/plan-refine.sh
# Hoặc: ./pipeline/scripts/plan.sh refine
```
Script sẽ tự động đọc `INTERVIEW_PLAN.md`, phản biện kế hoạch trước, sau đó tự động phân rã vào `pipeline/docs/context/Tasks_list.md` và các docs liên quan, rồi tự niêm phong plan sẵn sàng cho `harness.sh` chạy qua đêm.

---

## 1. Bối Cảnh & Bài Toán Cốt Lõi (Context & Problem Statement)

- **Vấn đề / Nỗi đau hiện tại (Core Problem & Pain Point):**
  [Mô tả bài toán cần giải quyết, lỗi đang gặp, hoặc nhu cầu phát sinh từ thực tế]
- **Mục tiêu tối thượng (Primary Objective):**
  [Kết quả cụ thể mà hệ thống cần đạt được sau khi hoàn thành kế hoạch này]
- **Đối tượng thụ hưởng & Hệ thống liên quan (Impacted Users & Systems):**
  [Ai hoặc module nào sẽ trực tiếp sử dụng / bị ảnh hưởng bởi thay đổi này]

---

## 2. Phương Án & Ý Tưởng Giải Pháp Đã Thống Nhất (Proposed Solution & Strategy)

- **Phương án giải pháp cốt lõi được chọn (Chosen Strategy):**
  [Mô tả giải pháp kỹ thuật/nghiệp vụ chính đã thống nhất trong buổi interview với LLM]
- **Các phương án thay thế đã xem xét & Lý do loại bỏ (Alternatives & Trade-offs):**
  - *Phương án A:* [Mô tả ngắn] ➔ *Lý do loại bỏ:* [Vì sao không chọn]
  - *Phương án B:* [Mô tả ngắn] ➔ *Lý do loại bỏ:* [Vì sao không chọn]
- **Kiến trúc tổng thể & Luồng dữ liệu đề xuất (Proposed Architecture & Data Flow):**
  [Mô tả cách các thành phần tương tác với nhau, luồng request/response hoặc xử lý dữ liệu]

---

## 3. Phạm Vi Nghiệp Vụ & Các Kịch Bản Xử Lý (Scope & Functional Scenarios)

### A. Luồng Chuẩn Thành Công (Happy Path)
1. [Bước 1: Khởi đầu luồng xử lý]
2. [Bước 2: Xử lý dữ liệu / logic chính]
3. [Bước 3: Kết quả trả về thành công]

### B. Các Kịch Bản Ngoại Lệ & Lỗi Tiềm Ẩn (Unhappy Path & Edge Cases)
- **Edge Case 1:** [Tình huống bất thường, ví dụ: Dữ liệu null, mạng timeout, race condition] ➔ *Cách xử lý:* [Mô tả giải pháp xử lý]
- **Edge Case 2:** [Tình huống lỗi nhập liệu / validation thất bại] ➔ *Cách xử lý:* [Mô tả giải pháp xử lý]
- **Edge Case 3:** [Tình huống hệ thống phụ thuộc sập / trả về 5xx] ➔ *Cách xử lý:* [Mô tả giải pháp xử lý]

### C. Ranh Giới Nằm Ngoài (Explicit Out of Scope / Non-Goals)
- ❌ [Những gì rõ ràng KHÔNG làm trong đợt này để tránh scope creep]
- ❌ [Những file hoặc modules nhạy cảm tuyệt đối không được chạm vào]

---

## 4. Lộ Trình Triển Khai Sơ Bộ Từ Buổi Phỏng Vấn (Phased Implementation Plan)

> 💡 Đây là các giai đoạn logic sơ bộ từ buổi phỏng vấn. `plan-refine.sh` sẽ dựa vào đây để phân rã thành các task atomic cụ thể (tối đa 5-8 files/task, bottom-up) vào `Tasks_list.md`.

- **Giai đoạn 1 (Nền tảng / Models / Schemas):**
  [Mô tả các thành phần cấu trúc dữ liệu, migrations, types, constants cần làm trước]
- **Giai đoạn 2 (Core Business Logic / Services):**
  [Mô tả các dịch vụ, hàm xử lý nghiệp vụ chính]
- **Giai đoạn 3 (API Endpoints / Controllers / UI):**
  [Mô tả các cổng giao tiếp ngoài, routing, màn hình hiển thị]
- **Giai đoạn 4 (Kiểm thử mở rộng & Hoàn thiện):**
  [Mô tả tích hợp, regression test, hardening]

---

## 5. Các Giả Định Ngầm, Vùng Nghi Ngờ & Điểm Cần Phản Biện (Assumptions & Critique Hotspots)

> ⚠️ **MỤC NÀY RẤT QUAN TRỌNG:** Hãy liệt kê tất cả các điểm mà bạn hoặc LLM trong buổi phỏng vấn **chưa hoàn toàn chắc chắn**. Critic trong `plan-refine.sh` sẽ tập trung phản biện sâu vào các điểm này.

- **Các giả định ngầm (Implicit Assumptions):**
  - [Ví dụ: Giả định rằng database hiện tại đã hỗ trợ transaction an toàn trên bảng X]
  - [Ví dụ: Giả định rằng third-party API có rate limit đủ lớn]
- **Những vùng nghi ngờ / Câu hỏi mở (Open Questions & Unknowns):**
  - [Câu hỏi 1: Chưa chắc chắn giải pháp này có gây chậm khi lượng dữ liệu lớn không?]
  - [Câu hỏi 2: Có nguy cơ phát sinh circular dependency giữa module A và module B không?]
- **Tác động phụ tiềm ẩn lên hệ thống hiện tại (Side Effects & Breaking Changes):**
  - [Cảnh báo về các thành phần hiện có có thể bị ảnh hưởng ngoài ý muốn]

---

## 6. Tiêu Chuẩn Nghiệm Thu Nghiệp Vụ & Chất Lượng (Success Criteria & Definition of Done)

- [ ] [Tiêu chí nghiệm thu nghiệp vụ 1: Kết quả trả về đúng theo yêu cầu]
- [ ] [Tiêu chí nghiệm thu nghiệp vụ 2: Xử lý an toàn toàn bộ edge cases đã nêu ở Mục 3]
- [ ] Toàn bộ bộ test tự động (Unit & Integration) đạt 100% PASS không có lỗi hồi quy.
- [ ] Tuân thủ đầy đủ các ranh giới trong `BOUNDARIES.md` và tiêu chuẩn trong `pipeline/docs/core/`.
