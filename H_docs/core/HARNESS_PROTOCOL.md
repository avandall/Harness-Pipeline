# HARNESS PROTOCOL
# Giao thức Harness — Ralph Loop & Vòng lặp tự trị

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0
>
> Đây là "hệ điều hành" của agent. Định nghĩa cách agent hoạt động như một vòng lặp tự trị thay vì một cuộc hội thoại tuyến tính.

---

## 1. Ralph Loop là gì?

Ralph Loop (đặt theo nhân vật Ralph Wiggum trong The Simpsons — kiên trì dù thường xuyên thất bại) là triết lý:

> **"Mỗi iteration = một fresh context. Filesystem = bộ nhớ dài hạn. Git = lịch sử. BLOCKED.md = phanh khẩn cấp."**

**Thay vì:**
```
User → [Long conversation → context rot → hallucination → wrong output]
```

**Ralph Loop làm:**
```
┌─────────────────────────────────────────────────┐
│  LOOP:                                          │
│  1. Fresh agent start                           │
│  2. Read filesystem state (H_docs/runtime/)       │
│  3. Execute ONE atomic unit of work             │
│  4. Verify output (pass/fail)                   │
│  5. Write results to filesystem                 │
│  6. Git commit                                  │
│  7. Check exit condition                        │
│     ├── DONE → Exit loop ✅                     │
│     ├── BLOCKED → Create BLOCKED.md → Stop 🛑  │
│     └── CONTINUE → Go to step 1 🔄             │
└─────────────────────────────────────────────────┘
```

---

## 2. State Machine

Mọi task đều đi qua các trạng thái sau (lưu trong `H_docs/runtime/STATUS.md`):

```
INIT → PLANNING → EXECUTING → REVIEWING → COMMITTING → [IN_PROGRESS | BLOCKED | ALL_DONE]
```

| Trạng thái | Ý nghĩa | File liên quan |
|-----------|---------|----------------|
| `INIT` | Task mới bắt đầu, chưa có plan | runtime/PLAN.md (chưa tồn tại) |
| `PLANNING` | AI đang viết PLAN.md | runtime/PLAN.md |
| `EXECUTING` | AI đang thực thi step | runtime/STATUS.md, PROGRESS_LOG.md |
| `REVIEWING` | AI đang tự review/phản biện kết quả | runtime/DEBATE_LOG.md |
| `COMMITTING` | AI đang commit lên git | git log |
| `IN_PROGRESS` | Dự án vẫn còn các task `[ ] TODO` hoặc `[/] IN_PROGRESS` | runtime/STATUS.md |
| `BLOCKED` | AI bị kẹt ở task hiện tại (chuyển task ở Overnight Mode) | runtime/BLOCKERS/<TASK_ID>.md |
| `ALL_DONE` | **TOÀN BỘ** tasks trong `Tasks_list.md` đã pass, phản biện xong và marked `[x] DONE` (hoặc `[!] BLOCKED`) | runtime/PROOF_OF_SOLUTION.md |

> ⚠️ **QUY TẮC BẤT BIẾN CHO STATUS.MD:**
> AI **CHỈ ĐƯỢC PHÉP** ghi `Phase: ALL_DONE` vào `H_docs/runtime/STATUS.md` KHI VÀ CHỈ KHI tất cả các tasks trong `Tasks_list.md` đã được thực thi, phản biện, xác minh pass 100% và đánh dấu `[x] DONE` (hoặc `[!] BLOCKED`). Không bao giờ ghi `Phase: DONE` hay `Phase: DONE (TASK-xxx)` khi dự án chưa hoàn tất 100% queue.

---

## 3. Exit Codes & Task Transition

Mỗi iteration kết thúc với một trong các exit codes/trạng thái sau:

| Code / Action | Ý nghĩa | Hành động tiếp theo |
|---------------|---------|---------------------|
| `EXIT_DONE` (`Phase: ALL_DONE`) | Tất cả tasks trong queue đã xử lý xong và verified | Cập nhật PROOF_OF_SOLUTION.md, kết thúc loop |
| `EXIT_CONTINUE` | Iteration xong, còn task tiếp theo | Cập nhật PROGRESS_LOG.md, commit, tiếp tục iteration |
| `TASK_BLOCKED` (Overnight) | 1 task bị kẹt, không dừng harness.sh | Ghi `BLOCKERS/<TASK_ID>.md`, đổi status `[!] BLOCKED`, chuyển sang task TODO tiếp |
| `EXIT_BLOCKED` (Strict Mode) | Dừng toàn bộ script khẩn cấp | Tạo `BLOCKED.md` ở root (chỉ dùng khi dùng cờ --stop-on-block) |
| `EXIT_RETRY` | Iteration thất bại, retry | Append DEBATE_LOG.md, cập nhật PLAN.md, retry |

---

## 4. Context Management

### Quy tắc "Context Budget"
- Mỗi fresh context, đọc tối đa **5 files** từ filesystem trước khi bắt đầu làm
- Ưu tiên đọc: Constitution → Status → Tasks_list → Plan → Last Progress Log entry
- KHÔNG đọc toàn bộ codebase — chỉ đọc files liên quan đến bước hiện tại

### Chống "Context Rot"
Context rot xảy ra khi một agent chạy quá lâu và bắt đầu lẫn lộn hoặc hallucinate. Phòng tránh bằng:
1. **Fresh restart** sau mỗi N iterations (N được định nghĩa trong CURRENT_TASK.md)
2. **State externalization**: Không bao giờ giữ state trong conversation — luôn write ra file
3. **Atomic commits**: Mỗi commit là một checkpoint an toàn để reset về

---

## 5. Backpressure Mechanism (Overnight Non-Blocking)

Khi gặp vấn đề không thể tự giải quyết:

```
Nếu gặp ≥ 2 lần liên tiếp:
  - Kết quả không verify được
  - Kết quả contradicts với spec
  - Cần thông tin không có trong docs

→ NẾU Ở OVERNIGHT MODE (Mặc định):
  1. Ghi chi tiết sự cố vào: H_docs/runtime/BLOCKERS/<TASK_ID>.md
  2. Đánh dấu dòng task trong Tasks_list.md thành: [!] BLOCKED
  3. Bỏ qua task kẹt và tự động chọn Task [ ] TODO tiếp theo!

→ NẾU Ở STRICT MODE (--stop-on-block):
  DỪNG LẠI. Tạo BLOCKED.md ở root. Không tự ý tiếp tục.
```

---

## 6. Dual-Model Mode (`--review-model`)

Để khắc phục **confirmation bias** (cùng model vừa viết code vừa tự review), harness hỗ trợ chế độ 2 model:

```bash
# Kích hoạt Dual-Model Review
./H_docs/harness.sh --review-model gemini-3.6-flash-low

# Dual-Model với reviewer cao cấp hơn
./H_docs/harness.sh --review-model claude-sonnet-4-6 --review-timeout 8m0s
```

> ⚠️ **Bắt buộc chỉ định tên model:** Không có model mặc định. Bỏ qua `--review-model` = single-model mode.

### Flow mỗi iteration khi Dual-Model active

```
┌─ EXECUTOR (default model) ──────────────────────────────────┐
│  Prompt A: ORIENT → SPEC → PLAN → EXECUTE → VERIFY        │
│  Chạy: python3 H_docs/scripts/verify.py                   │
│  ⚠️ DỪNG sau PHASE 4 — KHÔNG tự chạy Phase 5, 6, 7       │
└─────────────────────────────────────────────────────────────┘
                │ VERIFY PASS
                ▼
┌─ REVIEWER (--review-model) ─────────────────────────────────┐
│  Prompt B: đọc từ REVIEWER_PROMPT_TEMPLATE.md             │
│  Nhận: git diff (≤400 dòng) + verify.py --summary         │
│  Ghi kết quả vào: H_docs/runtime/DEBATE_LOG.md            │
│  Output: "Review Result: APPROVED" / "Review Result: REJECTED: ..." │
│  Đây là cuộc hội thoại agy MỚI HOÀN TOÀN (fresh context) │
└─────────────────────────────────────────────────────────────┘
                │
      ┌─────────┴──────────────┐
      ▼ APPROVED               ▼ REJECTED
   Executor chạy            Executor đọc DEBATE_LOG → fix → re-VERIFY
   Phase 6+7 (Commit+Report) Reviewer kiểm tra lại
                             (tối đa REVIEW_MAX_RETRIES lần)
                                      │
                             Vẫn REJECTED sau max retries?
                                      ▼
                             Executor ghi BLOCKERS/<TASK_ID>.md
                             Task → [!] BLOCKED
                             Tự động chuyển sang task TODO tiếp theo
```

### Tùy chỉnh Reviewer Prompt

Reviewer prompt được đọc từ `H_docs/core/REVIEWER_PROMPT_TEMPLATE.md` — **không hardcode trong harness.sh**.
Thay đổi template để tùy chỉnh mà không cần sửa harness.sh.

Template hỗ trợ:
- Checklist review tùy chỉnh
- Project-specific rules (inject tự động vào cuối prompt)
- Placeholders được harness thay thế tự động: `{{TIER1_SUMMARY}}`, `{{GIT_DIFF}}`, `{{ITERATION}}`, `{{DEBATE_LOG_PATH}}`

### Giá trị model hợp lệ

Chạy `agy models` để xem danh sách. Ví dụ:
- `gemini-3.6-flash-low` — rẻ nhất, đủ để review logic (khuyến nghị mặc định)
- `gemini-3.5-flash-medium` — cân bằng cost/quality
- `claude-sonnet-4-6` — reviewer chất lượng cao nhất cho task phức tạp

### State machine khi Dual-Model

| Trạng thái | Model | Action |
|-----------|-------|--------|
| `EXECUTING` | Executor | PHASE 0-4 (ORIENT→VERIFY), chạy verify.py |
| `REVIEWING` | Reviewer (khác) | PHASE 5, đọc git diff + tier1 summary. Fresh agy conversation. |
| `REVIEW_REJECTED` | Executor | Fix dựa trên DEBATE_LOG, re-verify. Max REVIEW_MAX_RETRIES cycles. |
| `REVIEW_BLOCKED` | Executor | Hết retries → ghi BLOCKERS/<TASK_ID>.md, chuyển task tiếp |
| `COMMITTING` | Executor | PHASE 6-7, atomic git commits + update runtime docs |

> ⚠️ **Khi không có `--review-model`:** harness hoạt động hoàn toàn như cũ (single-model, backward compatible). Executor tự thực hiện đủ Phase 0-7. retries → ghi BLOCKERS/<TASK_ID>.md, chuyển task tiếp |
| `COMMITTING` | Executor | PHASE 6-7, atomic git commits + update runtime docs |
           │
│  Ghi kết quả vào: H_docs/runtime/DEBATE_LOG.md            │
│  Output: "Review Result: APPROVED" / "Review Result: REJECTED: ..." │
└──────────────────────────────────────────────────────────────┘
                │
      ┌─────────┴───────────┐
      ▼ APPROVED            ▼ REJECTED
   Commit + next iter    Executor đọc DEBATE_LOG → fix → re-VERIFY
                          (tối đa 2 lần retry/iter, sau đó continue)
```

### Giá trị model hợp lệ

Chạy `agy models` để xem danh sách. Ví dụ:
- `gemini-3.6-flash-low` — rẻ nhất, đủ để review logic (khuyến nghị mặc định)
- `gemini-3.5-flash-medium` — cân bằng cost/quality
- `claude-sonnet-4-6` — reviewer chất lượng cao nhất cho task phức tạp

### State machine khi Dual-Model

| Trạng thái | Model | Action |
|-----------|-------|--------|
| `EXECUTING` | Executor | PHASE 0-4, runs verify.py |
| `REVIEWING` | Reviewer (khác) | PHASE 5, reads git diff only |
| `REVIEW_REJECTED` | Executor | Fix based on DEBATE_LOG, re-verify |
| `COMMITTING` | Executor | Atomic git commits |

> ⚠️ **Khi không có `--review-model`:** harness hoạt động hoàn toàn như cũ (single-model, backward compatible). Phase 5 do executor tự thực hiện.

---

## 7. Recovery Protocol

Khi mọi thứ sai:
```bash
# Xem lịch sử
git log --oneline -20

# Reset về commit cuối an toàn
git reset --hard HEAD

# Reset về N commits trước
git reset --hard HEAD~N

# Xem diff trước khi reset
git diff HEAD~1
```

Sau recovery: cập nhật `PROGRESS_LOG.md` với entry "Recovery: <lý do>"

---

## 8. Iteration Template

Mỗi iteration trong `H_docs/runtime/ITERATIONS/iter_NNN.md` phải có:
```markdown
# Iteration NNN
- Date: YYYY-MM-DD HH:MM
- State In: <trạng thái đầu iteration>
- Goal: <mục tiêu cụ thể của iteration này>
- Actions Taken: <danh sách hành động>
- Result: PASS | FAIL | PARTIAL
- Evidence: <link/snippet bằng chứng>
- State Out: <trạng thái cuối iteration>
- Next Action: <bước tiếp theo>
```
