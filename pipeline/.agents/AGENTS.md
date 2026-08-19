# AGENTS — Harness Engineering Rules
# AI đọc file này tự động khi làm việc trong workspace này

> File này được load tự động bởi Antigravity và các AI agents tương thích.
> Đây là entry point ngắn gọn — chi tiết xem trong `pipeline/docs/`.

---

## Bắt buộc đọc trước khi làm bất cứ điều gì

Khi bắt đầu bất kỳ task nào trong workspace này, bạn PHẢI đọc các files sau theo thứ tự (trong `pipeline/docs/` hoặc `pipeline/docs/`):

1. `pipeline/docs/core/AGENT_CONSTITUTION.md` — 10 điều luật bất biến
2. `pipeline/docs/core/HARNESS_PROTOCOL.md` — Ralph Loop và state machine
3. `pipeline/docs/core/WORKFLOW_STANDARDS.md` — Pipeline 7 phases
4. `pipeline/docs/context/PROJECT_BRIEF.md` — Mô tả dự án
5. `pipeline/docs/runtime/CURRENT_TASK.md` — Task đang làm
6. `pipeline/docs/context/BOUNDARIES.md` — Giới hạn quyền hạn
7. `pipeline/docs/runtime/STATUS.md` — Trạng thái hiện tại (nếu tồn tại)

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
