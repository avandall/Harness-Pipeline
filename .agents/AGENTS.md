# AGENTS — Harness Engineering Rules
# AI đọc file này tự động khi làm việc trong workspace này

> File này được load tự động bởi Antigravity và các AI agents tương thích.
> Đây là entry point ngắn gọn — chi tiết xem trong `H_docs/`.

---

## Bắt buộc đọc trước khi làm bất cứ điều gì

Khi bắt đầu bất kỳ task nào trong workspace này, bạn PHẢI đọc các files sau theo thứ tự:

1. `H_docs/core/AGENT_CONSTITUTION.md` — 10 điều luật bất biến
2. `H_docs/core/HARNESS_PROTOCOL.md` — Ralph Loop và state machine
3. `H_docs/core/WORKFLOW_STANDARDS.md` — Pipeline 7 phases
4. `H_docs/context/PROJECT_BRIEF.md` — Mô tả dự án
5. `H_docs/context/CURRENT_TASK.md` — Task đang làm
6. `H_docs/context/BOUNDARIES.md` — Giới hạn quyền hạn
7. `H_docs/runtime/STATUS.md` — Trạng thái hiện tại (nếu tồn tại)

---

## Rules Tóm Tắt (Quick Reference)

### Những điều LUÔN làm
- Dùng `H_docs/runtime/` để lưu state — không bao giờ dựa vào conversation history
- **Commit khi hoàn thành 1 function, 1 feature, hoặc 1 task logic hoàn chỉnh** — không commit liên tục vụn vặt từng file đơn lẻ nếu chúng thuộc cùng một công việc (ví dụ: gom commit toàn bộ bộ docs context sau khi cập nhật xong, không chia nhỏ thành 4 commits riêng).
- Verify output với evidence cụ thể, không chỉ claim "nó hoạt động"
- Append vào `PROGRESS_LOG.md` sau mỗi iteration
- Cập nhật `STATUS.md` sau mỗi hành động quan trọng
- Chạy self-review checklist từ `REVIEW_PROTOCOL.md` trước khi commit
- Luôn dùng Python nếu có thể.
- **Luôn khai báo và cập nhật mọi dependency mới vào file `pyproject.toml`** (dưới mảng `dependencies`) đồng thời giữ `requirements.txt` đồng bộ.

### Những điều KHÔNG BAO GIỜ làm
- Tự ý sửa files ngoài scope trong `H_docs/context/BOUNDARIES.md`
- Commit credentials, secrets, hoặc API keys
- Claim task DONE mà không có verification evidence
- Tiếp tục khi đã gặp blocker — tạo `BLOCKED.md` thay vào đó
- Giữ state trong conversation — write ra file

### Khi bị kẹt (Overnight Non-Blocking Mode)
1. Ghi lý do kẹt và câu hỏi chi tiết vào file `H_docs/runtime/BLOCKERS/<TASK_ID>.md`
2. Cập nhật trạng thái dòng task tương ứng trong `H_docs/context/Tasks_list.md` thành `[!] BLOCKED`
3. Cập nhật `H_docs/runtime/STATUS.md` giải phóng task hiện tại
4. Tự động chuyển sang task `[ ] TODO` tiếp theo trong `Tasks_list.md` (không tạo `BLOCKED.md` ở root ngoại trừ khi khẩn cấp)

---

## Cấu trúc Docs

```
H_docs/
├── core/       # 🔒 Fixed — Đọc, không sửa
├── context/    # ✏️ Human fills — Đọc, sửa chỉ khi được chỉ định
└── runtime/    # 🤖 AI fills — Tự do tạo và cập nhật
```

---

## Git Convention

```
[iter-N] <type>(<scope>): <description>

Types: feat | fix | refactor | docs | test | chore
Example: [iter-3] fix(auth): handle null user in JWT middleware
```

---

## Harness Engineering Philosophy

> "Build the systems that build software.
>  The filesystem is memory. Git is history. BLOCKED.md is the brake.
>  One loop, one scope. Fresh context every iteration."
>  — Ralph Loop Methodology
