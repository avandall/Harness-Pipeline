# BLOCKED
# ⛔ Tín hiệu dừng — AI cần human intervention

> **Trạng thái:** RUNTIME (Auto-generated) | **Tạo bởi:** AI khi gặp blocker
>
> 🛑 **FILE NÀY CÓ NGHĨA LÀ AI ĐÃ DỪNG LẠI VÀ CHỜ HUMAN.**
> Đọc file này → Trả lời câu hỏi → Xóa file này để AI tiếp tục.

---

## Blocker Summary

```
Blocker ID:     [BLOCK-NNN]
Task:           [Task ID — Task Name]
Iteration:      [N]
Created:        [YYYY-MM-DD HH:MM]
Severity:       CRITICAL | HIGH | MEDIUM
```

---

## Tại sao AI dừng lại?

```
Loại blocker:
  [ ] MISSING_INFO      — Thiếu thông tin để tiến tiếp
  [ ] AMBIGUOUS_SPEC    — Spec mâu thuẫn hoặc không rõ ràng
  [ ] DECISION_NEEDED   — Cần human quyết định kiến trúc/ưu tiên
  [ ] OUT_OF_BOUNDS     — Task yêu cầu thứ gì đó ngoài BOUNDARIES.md
  [ ] REPEATED_FAILURE  — Fail ≥ 3 lần với nhiều cách tiếp cận khác nhau
  [ ] CONTRADICTION     — Hai docs mâu thuẫn nhau
  [ ] TOOL_MISSING      — Cần tool/permission chưa có
```

---

## Mô tả chi tiết

### Tôi đang cố làm gì?
[Mô tả rõ ràng hành động AI đang thực hiện khi gặp blocker]

### Tại sao tôi bị kẹt?
[Mô tả chính xác điểm mà AI không thể tiến tiếp và tại sao]

### Tôi đã thử gì rồi?
1. [Approach 1 — tại sao không hoạt động]
2. [Approach 2 — tại sao không hoạt động]
3. [Approach 3 — tại sao không hoạt động]

---

## Câu hỏi cụ thể cho Human

> ⚠️ Trả lời **tất cả** các câu hỏi sau để AI có thể tiếp tục:

**Q1: [Câu hỏi cụ thể nhất có thể]**
- Options: [Option A / Option B / Option C]
- Impact: [Quyết định này ảnh hưởng gì?]
- Answer: _______________

**Q2: [Câu hỏi 2 nếu có]**
- Answer: _______________

---

## Tác động nếu không giải quyết

```
Task có thể tiếp tục không?  NO
Bị block từ:                 [YYYY-MM-DD HH:MM]
Estimated unblock time:      [Sau khi nhận answer từ human]
```

---

## Cách unblock AI

1. Điền câu trả lời vào section "Câu hỏi cụ thể" ở trên
2. Cập nhật doc liên quan nếu cần (`BOUNDARIES.md`, `Tasks_list.md`, v.v.)
3. **Xóa file BLOCKED.md này**
4. Thông báo cho AI tiếp tục với context về quyết định đã được đưa ra

---

## Context tại thời điểm bị block

```
Last commit:      [hash]
Last iteration:   [ITER-NNN]
Current PLAN.md step: [Step N]
Files đang sửa:   [list files]
```
