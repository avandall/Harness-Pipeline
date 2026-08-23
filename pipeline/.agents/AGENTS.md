# AGENTS — Harness Engineering Rules
# AI đọc file này tự động khi làm việc trong workspace này

> File này được load tự động bởi Antigravity và các AI agents tương thích.
> Đây là entry point ngắn gọn — chi tiết xem trong `pipeline/docs/`.

---

## ⚡ Quick Reference & Inline Constitution (Token-Optimized)

> ⚠️ **TỐI ƯU HÓA BỘ NHỚ AI:**
> Tất cả 10 Điều luật cốt lõi đã được ghi trực tiếp dưới đây.
> **KHÔNG** tự ý gọi tool `view_file` để mở đọc lại các file tài liệu trong `pipeline/docs/core/` (`AGENT_CONSTITUTION.md`, `WORKFLOW_STANDARDS.md`, `HARNESS_PROTOCOL.md`) trừ khi người dùng yêu cầu hoặc khi gặp lỗi phức tạp cần tra cứu sâu.

### 📜 10 Điều Luật Bất Biến (Inline Constitution)
1. **Memory on Disk**: Lưu state ra filesystem (`STATUS.md`, `PLAN.md`, `PROGRESS_LOG.md`), KHÔNG giữ trong chat conversation.
2. **Atomic Steps**: Chỉ thực hiện 1 bước atomic nhỏ mỗi lần.
3. **Deterministic Verification**: Bắt buộc chạy `python3 pipeline/scripts/verify.py` trước khi báo hoàn thành.
4. **Proof Over Promise**: Không bao giờ claim "đã xong" nếu chưa verify PASS 100%.
5. **No Blind Edits**: Xem file trước khi sửa, giữ nguyên comments/docstrings cũ.
6. **No Phantom Tools**: Chỉ dùng tools có sẵn trong môi trường.
7. **Strict Scope**: Không sửa các file ngoài phạm vi chỉ định trong `BOUNDARIES.md`.
8. **1 Task = 1 Commit**: CHỈ GIT COMMIT KHI TASK ĐÃ HOÀN THÀNH (`[x] DONE`). Không commit trung gian.
9. **Never Block Overnight**: Gặp blocker $\rightarrow$ ghi `BLOCKERS/<TASK_ID>.md`, đổi task thành `[!] BLOCKED`, chuyển sang task TODO tiếp theo.
10. **Clean Working Tree**: Dọn sạch scratch files và để working tree sạch sẽ.

### 🔄 Quy Trình 7 Phase Thực Thi Chuẩn (Tóm Tắt)
- **Phase 0: ORIENT** $\rightarrow$ Nạp Task Spec từ `Tasks_list.md` + Tech Context & Boundaries (JIT, không đọc core docs lẻ).
- **Phase 1: SPEC** $\rightarrow$ Xác định Acceptance Criteria & Verification Method trước khi code.
- **Phase 2: PLAN** $\rightarrow$ Tạo/cập nhật `runtime/PLAN.md` chia nhỏ thành 2–4 atomic steps.
- **Phase 3: EXECUTE** $\rightarrow$ Thực thi từng step, đọc file trước khi sửa, cập nhật state ra disk.
- **Phase 4: VERIFY** $\rightarrow$ Chạy `python3 pipeline/scripts/verify.py` (Tier 1 CLI), sửa lỗi đến khi PASS 100%.
- **Phase 5: REVIEW** $\rightarrow$ Phản biện nhận thức Tier 2 qua Git Diff (`DEBATE_LOG.md`).
- **Phase 6: COMMIT** $\rightarrow$ Commit Git khi task `[x] DONE` (Format: `[TASK-ID] <type>(<scope>): <mô tả>`).
- **Phase 7: REPORT** $\rightarrow$ Ghi kết quả vào `runtime/STATUS.md` & `runtime/PROGRESS_LOG.md`.

---

## Rules Tóm Tắt (Quick Reference)

### Những điều LUÔN làm
- Dùng `pipeline/docs/runtime/` để lưu state — không bao giờ dựa vào conversation history
- **Cập nhật runtime docs (`STATUS.md`, `PROGRESS_LOG.md`, `PLAN.md`) ra filesystem liên tục sau mỗi iteration** để lưu progression context khi Ralph loop reset phiên.
- **CHỈ GIT COMMIT KHI HOÀN THÀNH 1 TASK (`[x] DONE`)** — KHÔNG commit vụn vặt lặp đi lặp lại từng iteration, từng file lẻ hay mỗi lần cập nhật runtime docs.
- **Commit message rõ ràng, mạch lạc, đúng thứ tự**: Dùng format `[TASK-ID] <type>(<scope>): <mô tả task đã hoàn thành>` (ví dụ: `[TASK-001] feat(auth): implement JWT authentication`).
- Verify output với evidence cụ thể, không chỉ claim "nó hoạt động"
- Append vào `PROGRESS_LOG.md` sau mỗi iteration
- Cập nhật `STATUS.md` sau mỗi hành động quan trọng
- Chạy self-review checklist từ `REVIEW_PROTOCOL.md` trước khi commit
- Luôn dùng Python nếu có thể.
- **Luôn khai báo và cập nhật mọi dependency mới vào file `pyproject.toml`** (dưới mảng `dependencies`) đồng thời giữ `requirements.txt` đồng bộ.

### Những điều KHÔNG BAO GIỜ làm
- Tự ý sửa files ngoài scope trong `pipeline/docs/context/BOUNDARIES.md`
- Commit credentials, secrets, hoặc API keys
- Claim task DONE mà không có verification evidence
- Tiếp tục khi đã gặp blocker — tạo `BLOCKED.md` thay vào đó
- Giữ state trong conversation — write ra file
- **Commit với format `[iter-N]`** hoặc commit runtime docs (STATUS.md, PROGRESS_LOG.md, PLAN.md)

### Khi bị kẹt (Overnight Non-Blocking Mode)
1. Ghi lý do kẹt và câu hỏi chi tiết vào file `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md`
2. Cập nhật trạng thái dòng task tương ứng trong `pipeline/docs/context/Tasks_list.md` thành `[!] BLOCKED`
3. Cập nhật `pipeline/docs/runtime/STATUS.md` giải phóng task hiện tại
4. Tự động chuyển sang task `[ ] TODO` tiếp theo trong `Tasks_list.md` (không tạo `BLOCKED.md` ở root ngoại trừ khi khẩn cấp)

---

## Cấu trúc Docs

```
pipeline/docs/
├── core/       # 🔒 Fixed — Đọc, không sửa
├── context/    # ✏️ Human fills — Đọc, sửa chỉ khi được chỉ định
└── runtime/    # 🤖 AI fills — Tự do tạo và cập nhật
```

---

## Git Convention

```
[TASK-ID] <type>(<scope>): <mô tả ngắn task đã hoàn thành>

Types: feat | fix | refactor | docs | test | chore
Example: [TASK-001] feat(auth): implement JWT authentication handler
Example: [TASK-002] fix(quota): resolve boundary edge cases
```

> ⚠️ **ANTI-PATTERN cần tránh tuyệt đối:**
> - `[iter-3] fix(auth): ...` — SAI, không bao giờ dùng prefix [iter-N]
> - `chore: update status.md` — SAI, không commit runtime docs
> - Commit giữa chừng khi task chưa `[x] DONE` — SAI

---

## Harness Engineering Philosophy

> "Build the systems that build software.
>  The filesystem is memory. Git is history. BLOCKED.md is the brake.
>  One loop, one scope. Fresh context every iteration."
>  — Ralph Loop Methodology
