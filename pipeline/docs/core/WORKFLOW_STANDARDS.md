# WORKFLOW STANDARDS
# Tiêu chuẩn quy trình — Từng bước thực thi chuẩn

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0
>
> Pipeline chuẩn từ khi nhận task đến khi hoàn thành. Áp dụng cho mọi loại task, mọi loại project.

---

## Tổng quan Pipeline

```
PHASE 0: ORIENT     → Đọc context, hiểu rõ bức tranh toàn cục
PHASE 1: SPEC       → Viết spec cùng với AI trước khi code
PHASE 2: PLAN       → Chia nhỏ thành các atomic steps
PHASE 3: EXECUTE    → Thực thi từng step, một vòng một lần
PHASE 4: VERIFY     → Kiểm tra kết quả với bằng chứng cụ thể
PHASE 5: REVIEW     → Tự phản biện hoặc multi-agent review
PHASE 6: COMMIT     → Commit với message chuẩn
PHASE 7: REPORT     → Cập nhật tất cả runtime docs
```

---

## PHASE 0 — ORIENT (Định hướng & Nạp Ngữ cảnh JIT)

**Mục tiêu:** Nạp đúng và đủ bối cảnh cần thiết theo cơ chế Just-In-Time (JIT) & Prompt Caching.

**Quy tắc nạp bối cảnh:**
- 10 Điều luật Hiến pháp: Đã được nén sẵn inline trong `.agents/AGENTS.md` (không gọi tool mở file lẻ).
- Bối cảnh Task hiện tại: Trích xuất trực tiếp Task Spec từ `Tasks_list.md` vào Prompt Cache của phiên làm việc.
- Bối cảnh kỹ thuật: Nạp tóm tắt `TECH_CONTEXT.md` (Tech stack) và `BOUNDARIES.md` (Scope file được sửa) ở đầu task.
- Trạng thái runtime: Đọc `runtime/PLAN.md` (nếu đã có kế hoạch từ bước trước) hoặc `runtime/STATUS.md`.

**Output:** Hiểu rõ: Task này cần đạt được gì? Tech stack là gì? File nào được sửa/cấm sửa? Bước atomic tiếp theo là gì?


---

## PHASE 1 — SPEC (Xây dựng đặc tả)

**Mục tiêu:** Định nghĩa rõ ràng "done" trông như thế nào trước khi code.

**Actions:**
1. Xác định **Acceptance Criteria** — task được coi là xong khi nào?
2. Xác định **Edge Cases** — những trường hợp đặc biệt nào cần handle?
3. Xác định **Verification Method** — test gì, command gì, output gì để verify?
4. Xác định **Dependencies** — cần gì để bắt đầu?

**Output:** Ghi vào `pipeline/docs/runtime/PLAN.md` section "Spec"

**Nguyên tắc:** Nếu không thể định nghĩa "done", không bắt đầu. Tạo `BLOCKED.md`.

---

## PHASE 2 — PLAN (Lập kế hoạch)

**Mục tiêu:** Chia task thành atomic steps, mỗi step độc lập và verifiable.

**Template cho PLAN.md:**
```markdown
## Task: [Tên task từ CURRENT_TASK.md]
## Spec: [Acceptance criteria]
## Steps:
  - [ ] Step 1: [Mô tả cụ thể] → Exit: [Verification]
  - [ ] Step 2: [Mô tả cụ thể] → Exit: [Verification]
  - [ ] Step N: ...
## Risk Assessment:
  - [Risk] → [Mitigation]
## Estimated Iterations: N
```

**Quy tắc chia step:**
- Mỗi step: **≤ 30 phút** thực thi
- Mỗi step có **exit condition rõ ràng**
- Không step nào phụ thuộc vào kết quả chưa biết của step khác
- Nếu step quá lớn: chia nhỏ thêm

---

## PHASE 3 — EXECUTE (Thực thi)

**Mục tiêu:** Thực thi đúng một step từ PLAN.md.

**Rules:**
1. **One thing at a time**: Chỉ làm step hiện tại, không "tiện tay" sửa thêm
2. **Read before write**: Trước khi sửa file nào, đọc file đó trước
3. **Minimal footprint**: Chỉ thay đổi files liên quan trực tiếp đến step
4. **Comment your intent**: Trong code, comment tại sao — không chỉ cái gì
5. **No global state changes**: Không thay đổi config, env, schema mà không ghi vào PLAN.md trước

**Nếu phát hiện vấn đề ngoài scope trong khi execute:**
→ Ghi note vào PROGRESS_LOG.md → Hoàn thành step hiện tại → Thêm issue vào PLAN.md cho sau

---

## PHASE 4 — VERIFY (Kiểm tra Định tính Tier 1 & Runtime)

**Mục tiêu:** Chứng minh code hoạt động 100% bằng công cụ kiểm tra định tính (Deterministic CLI Tools) khách quan trước khi nhờ LLM review.

**Quy trình BẮT BUỘC:**
1. **Chạy Script kiểm tra định tính:**
   ```bash
   python3 pipeline/scripts/verify.py
   ```

   Script này sẽ tự động chạy Linter, Type Checker, Security Scan, và Unit Tests theo active preset (Python, Node/React, Go, Shell, Polyglot).

2. **Kiểm tra báo cáo `pipeline/docs/runtime/VERIFICATION_REPORT.md`:**
   - Nếu `Status: FAIL`: Đọc các dòng log Traceback được cắt tỉa gọn gàng trong file `VERIFICATION_REPORT.md`. Sửa ngay các lỗi này và chạy lại `verify.py`. **KHÔNG ĐƯỢC CHUYỂN SANG PHASE 5 KHI VẪN CÒN CƠ LỖI TIER 1!**
   - Nếu `Status: PASS`: Chuyển sang Phase 5.

3. **Capture Bằng Chứng:**
   - Ghi ngắn gọn kết quả Tier 1 Verification vào `pipeline/docs/runtime/PROOF_OF_SOLUTION.md`.

---

## PHASE 5 — REVIEW (Phản biện nhận thức Tier 2 - Cognitive LLM Review)

**Mục tiêu:** Tập trung AI Reviewer vào Logic ngầm, Edge Cases, Performance & Scalability (vì cú pháp, kiểu dữ liệu, formatting đã được Tier 1 CLI đảm bảo 100%).

Thực hiện checklist từ `pipeline/docs/core/REVIEW_PROTOCOL.md` dựa trên `git diff`.

**Tối thiểu phải kiểm tra:**
1. **Logic & Edge Cases:** Có trường hợp biên nào (null, empty, memory overflow, timeout) chưa xử lý không?
2. **Scalability & Performance:** Có thuật toán $O(N^2)$, N+1 query hay memory leak nào không?
3. **Clean Code & Modularity:** Code có tuân theo `CODE_STANDARDS.md`, dễ đọc và bảo trì không?
4. **Side Effects:** Code thay đổi có phá vỡ các chức năng cũ không?

Ghi kết quả review vào `pipeline/docs/runtime/DEBATE_LOG.md`. Cần đạt `APPROVED` trước khi sang Phase 6.

---

## PHASE 6 — COMMIT (Cam kết theo Task)

**Mục tiêu:** Tạo checkpoint an toàn, mạch lạc và có nghĩa trong git khi 1 TASK đã hoàn thành.

### Quy tắc commit:

> **"1 commit = 1 Task hoàn chỉnh đã được verify pass 100% [x] DONE."**

- **Khi nào commit?**: CHỈ commit khi task hiện tại đã được thực thi, kiểm tra (Phase 4 VERIFY) và phản biện (Phase 5 REVIEW) hoàn tất 100%, được đánh dấu `[x] DONE` trong `Tasks_list.md`.
- **Khi nào KHÔNG commit?**: Trong các iterations trung gian khi task chưa xong, KHÔNG tạo git commit lặt vặt (như `chore: iter-N complete` hay commit lắt nhắt mỗi lần sửa file).

### Commit message format

```
[TASK-ID] <type>(<scope>): <clear description of completed task>

Types: feat | fix | refactor | docs | test | chore
Example: [TASK-001] feat(auth): implement JWT login and session handler
```

---


## PHASE 7 — REPORT (Báo cáo Tiến độ ra Filesystem)

**Mục tiêu:** Cập nhật tất cả runtime docs trên filesystem sau mỗi iteration để phiên làm việc tiếp theo của Ralph Loop nắm đầy đủ context.

**Lưu ý quan trọng:**
- Cập nhật runtime docs trên filesystem là BẮT BUỘC sau mỗi iteration (dù chưa commit git) để các session fresh restart do script `harness.sh` tự mở luôn đọc được state mới nhất từ filesystem memory.
- **KHÔNG commit runtime docs** (STATUS.md, PROGRESS_LOG.md, PLAN.md) vào git — chỉ AI đọc, không cần lưu vào git history.
- **Thứ tự:** Phase 6 (COMMIT) phải được chạy TRƯỚC Phase 7 cho task đã done. Phase 7 update docs SAU khi đã commit xong.

**Checklist sau mỗi iteration:**
- [ ] Append entry mới vào `PROGRESS_LOG.md` trên filesystem.
- [ ] Update `STATUS.md` trên filesystem với trạng thái mới (`Phase: IN_PROGRESS` khi vẫn còn task, chỉ ghi `Phase: ALL_DONE` khi toàn bộ task queue trong `Tasks_list.md` đã DONE/BLOCKED).
- [ ] Cập nhật tiến độ các bước trong `PLAN.md` và `Tasks_list.md`.
- [ ] Tạo snapshot iteration tại `ITERATIONS/iter_NNN.md`.
- [ ] Nếu Task đã hoàn thành `[x] DONE`: Đã thực hiện Phase 6 (COMMIT) rồi — kiểm tra lại `git log --oneline -3` để confirm.

---

## Quick Reference Card

```
Nhận task mới?
  → Chạy PHASE 0: Đọc context/

Task chưa có PLAN.md?
  → PHASE 1 + 2: Viết spec và plan

Đang giữa chừng một task?
  → Đọc STATUS.md → Tiếp tục từ PHASE 3

Không biết bước tiếp theo?
  → Đọc PLAN.md → Check bước nào chưa xong

Output không verify được?
  → PHASE 5 → DEBATE_LOG.md → Retry hoặc BLOCKED.md

Task xong ([x] DONE)?
  → PHASE 6 (COMMIT): git add -A && git commit -m "[TASK-ID] <type>(<scope>): <mô tả>"
  → PHASE 7 (REPORT): Cập nhật PROGRESS_LOG.md, STATUS.md, Tasks_list.md
  → Kông bao giờ commit STATUS.md/PROGRESS_LOG.md riêng lẻ!

Tất cả tasks done?
  → PHASE 7 → Viết PROOF_OF_SOLUTION.md → STATUS.md: Phase: ALL_DONE
  → harness.sh tự động tạo git tag milestone
```
