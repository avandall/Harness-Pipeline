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

## PHASE 6 — COMMIT (Cam kết)

**Mục tiêu:** Tạo checkpoint an toàn, nhỏ, và reviewable trong git.

### Nguyên tắc cốt lõi: Commit như Senior Dev

> **"1 commit = 1 chức năng có thể review độc lập bởi người khác."**

Không bao giờ gom nhiều changes không liên quan vào một commit chỉ vì "tiện". Mỗi commit phải có thể được đọc, hiểu, và approve mà không cần đọc commit nào khác.

### Khi nào commit?

| Sự kiện | Action |
|---------|--------|
| Viết xong 1 function / feature | → commit 1 lần cho function/feature đó |
| Viết xong 1 bộ test/docs của 1 task | → commit 1 lần cho cả khối test/docs của task |
| Fix xong 1 bug | → commit riêng cho bug fix |
| Refactor xong 1 module | → commit riêng (không mix với feature changes) |

*Lưu ý:* Tránh commit vụn vặt từng file đơn lẻ khi chúng thuộc cùng 1 mục tiêu/task logic chung (ví dụ: cập nhật bộ 4 file docs context thì gom commit 1 lần sau khi hoàn thành cả bộ).

### Ví dụ đúng ✅

```bash
# Implement auth feature → nhiều commit nhỏ
git commit -m "[iter-2] feat(auth): add password hashing with bcrypt"
git commit -m "[iter-2] feat(auth): add JWT token generation service"
git commit -m "[iter-2] feat(auth): add JWT validation middleware"
git commit -m "[iter-2] test(auth): unit tests for password hashing"
git commit -m "[iter-2] test(auth): unit tests for JWT service"
git commit -m "[iter-2] docs(auth): add /login /register to API docs"
```

### Ví dụ sai ❌

```bash
# Gom tất cả vào 1 commit khổng lồ — KHÔNG được phép
git commit -m "[iter-2] feat: implement auth with JWT, add tests, fix bug, update docs"
```

### Commit message format

```
[iter-N] <type>(<scope>): <short description>

<optional body: what và why — bắt buộc nếu change không tự giải thích>

Refs: #<issue-number nếu có>
```

**Types:**
- `feat` — tính năng mới
- `fix` — sửa lỗi
- `refactor` — tái cấu trúc không thay đổi behavior
- `docs` — thay đổi docs
- `test` — thêm/sửa tests
- `chore` — build, config, dependency

### Commit size limits (hướng dẫn)
- **Ideal:** < 200 lines changed per commit
- **Acceptable:** < 400 lines nếu là boilerplate/generated code
- **Red flag:** > 500 lines → tách nhỏ hơn trước khi commit

---


## PHASE 7 — REPORT (Báo cáo)

**Mục tiêu:** Cập nhật tất cả runtime docs để iteration tiếp theo có đủ context.

**Checklist:**
- [ ] Append entry vào `PROGRESS_LOG.md`
- [ ] Update `STATUS.md` với trạng thái mới và next action (`Phase: IN_PROGRESS` khi vẫn còn tasks, chỉ được ghi `Phase: ALL_DONE` khi tất cả tasks trong `Tasks_list.md` đã pass 100%, phản biện xong và marked DONE)
- [ ] Mark step đã xong trong `PLAN.md` và `Tasks_list.md`
- [ ] Nếu tất cả tasks đã hoàn thành (`Phase: ALL_DONE`): hoàn thiện `PROOF_OF_SOLUTION.md`
- [ ] Nếu BLOCKED: tạo `BLOCKERS/<TASK_ID>.md` (Overnight Mode)
- [ ] Tạo `ITERATIONS/iter_NNN.md` với đầy đủ thông tin iteration

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
