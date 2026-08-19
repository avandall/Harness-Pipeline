# Task Blockers Log Directory

Thư mục này chứa các báo cáo kẹt (Blocker Reports) theo từng Task khi hệ thống chạy ở chế độ **Overnight Non-Blocking Mode**.

Khi một task gặp sự cố không thể tự giải quyết:
1. AI sẽ tạo file `TASK-XXX.md` tại thư mục này với mô tả chi tiết lý do và câu hỏi cho Human.
2. AI cập nhật trạng thái của task trong `H_docs/context/Tasks_list.md` thành `[!] BLOCKED`.
3. Hệ thống sẽ bỏ qua task này và tiếp tục xử lý các task `[ ] TODO` khác.
