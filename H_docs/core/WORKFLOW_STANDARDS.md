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

## PHASE 0 — ORIENT (Định hướng)

**Mục tiêu:** Hiểu đầy đủ context trước khi làm bất cứ điều gì.

**Checklist:**
- [ ] Đọc `H_docs/core/AGENT_CONSTITUTION.md`
- [ ] Đọc `H_docs/context/PROJECT_BRIEF.md` → hiểu mục tiêu dài hạn
- [ ] Đọc `H_docs/context/CURRENT_TASK.md` → hiểu task ngay bây giờ
- [ ] Đọc `H_docs/context/BOUNDARIES.md` → biết giới hạn
- [ ] Đọc `H_docs/runtime/STATUS.md` nếu tồn tại → biết đang ở đâu
- [ ] Đọc entry cuối của `H_docs/runtime/PROGRESS_LOG.md` nếu tồn tại

**Output:** Hiểu rõ: Tôi đang làm gì? Cho ai? Với những giới hạn nào? Đang ở bước nào?

**Thời gian tối đa:** Không bắt đầu làm gì cho đến khi trả lời được 3 câu hỏi trên.

---

## PHASE 1 — SPEC (Xây dựng đặc tả)

**Mục tiêu:** Định nghĩa rõ ràng "done" trông như thế nào trước khi code.

**Actions:**
1. Xác định **Acceptance Criteria** — task được coi là xong khi nào?
2. Xác định **Edge Cases** — những trường hợp đặc biệt nào cần handle?
3. Xác định **Verification Method** — test gì, command gì, output gì để verify?
4. Xác định **Dependencies** — cần gì để bắt đầu?

**Output:** Ghi vào `H_docs/runtime/PLAN.md` section "Spec"

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
   python3 H_docs/scripts/verify.py
   ```
   Script này sẽ tự động chạy: Linter (Ruff), Type Checker (Mypy), Security Scan (Bandit), và Unit Tests (Pytest).

2. **Kiểm tra báo cáo `H_docs/runtime/VERIFICATION_REPORT.md`:**
   - Nếu `Status: FAIL`: Đọc các dòng log Traceback được cắt tỉa gọn gàng trong file `VERIFICATION_REPORT.md`. Sửa ngay các lỗi này và chạy lại `verify.py`. **KHÔNG ĐƯỢC CHUYỂN SANG PHASE 5 KHI VẪN CÒN CƠ LỖI TIER 1!**
   - Nếu `Status: PASS`: Chuyển sang Phase 5.

3. **Capture Bằng Chứng:**
   - Ghi ngắn gọn kết quả Tier 1 Verification vào `H_docs/runtime/PROOF_OF_SOLUTION.md`.

---

## PHASE 5 — REVIEW (Phản biện nhận thức Tier 2 - Cognitive LLM Review)

**Mục tiêu:** Tập trung AI Reviewer vào Logic ngầm, Edge Cases, Performance & Scalability (vì cú pháp, kiểu dữ liệu, formatting đã được Tier 1 CLI đảm bảo 100%).

Thực hiện checklist từ `H_docs/core/REVIEW_PROTOCOL.md` dựa trên `git diff`.

**Tối thiểu phải kiểm tra:**
1. **Logic & Edge Cases:** Có trường hợp biên nào (null, empty, memory overflow, timeout) chưa xử lý không?
2. **Scalability & Performance:** Có thuật toán $O(N^2)$, N+1 query hay memory leak nào không?
3. **Clean Code & Modularity:** Code có tuân theo `CODE_STANDARDS.md`, dễ đọc và bảo trì không?
4. **Side Effects:** Code thay đổi có phá vỡ các chức năng cũ không?

Ghi kết quả review vào `H_docs/runtime/DEBATE_LOG.md`. Cần đạt `APPROVED` trước khi sang Phase 6.

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

**Lưu ý quan trọng:** Cập nhật runtime docs trên filesystem là BẮT BUỘC sau mỗi iteration (dù chưa commit git) để các session fresh restart do script `harness.sh` tự mở luôn đọc được state mới nhất từ filesystem memory.

**Checklist sau mỗi iteration:**
- [ ] Append entry mới vào `PROGRESS_LOG.md` trên filesystem.
- [ ] Update `STATUS.md` trên filesystem với trạng thái mới (`Phase: IN_PROGRESS` khi vẫn còn task, chỉ ghi `Phase: ALL_DONE` khi toàn bộ task queue trong `Tasks_list.md` đã DONE/BLOCKED).
- [ ] Cập nhật tiến độ các bước trong `PLAN.md` và `Tasks_list.md`.
- [ ] Tạo snapshot iteration tại `ITERATIONS/iter_NNN.md`.
- [ ] Nếu Task đã hoàn thành `[x] DONE`: Thực hiện Phase 6 (COMMIT) cho task đó.

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

Mọi thứ xong?
  → PHASE 7 → Cập nhật tất cả runtime docs → Git tag
```
