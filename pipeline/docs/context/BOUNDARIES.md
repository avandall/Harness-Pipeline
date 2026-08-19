# BOUNDARIES
# Giới hạn quyền hạn — Những gì AI được và không được làm

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** Khi bắt đầu project mới hoặc khi scope thay đổi
>
> ✏️ **HUMAN FILLS THIS FILE.** AI phải đọc và tuân thủ nghiêm ngặt.
>
> ⚠️ **CRITICAL:** Đây là "hợp đồng" ranh giới giữa bạn và AI. AI sẽ dừng lại và hỏi nếu thao tác vượt quá scope.

---

## 1. Phạm vi File (File Scope)

### AI được phép đọc và sửa:
```
✅ [Đường dẫn thư mục/file AI được phép làm việc, ví dụ: src/**]
✅ [Ví dụ: tests/**]
✅ [Ví dụ: pipeline/docs/runtime/**]
```

### AI KHÔNG được chạm vào:
```
❌ [Đường dẫn file/thư mục cấm sửa, ví dụ: .env]
❌ [Ví dụ: pipeline/docs/core/** — Bộ quy chuẩn cố định]
❌ [Ví dụ: production configuration / deployment scripts chưa được chỉ định]
```

---

## 2. Database Permissions

```
READ:    ✅ [Có được đọc database local / test không?]
WRITE:   ✅ [Có được ghi dữ liệu test không?]
MIGRATE: ✅ / ❌ [Có được chạy migration script không?]
DROP:    ❌ [KHÔNG BAO GIỜ được phép DROP DB]

Môi trường:
  - Local DB:    ✅ Quyền đọc/ghi/migration trên DB local
  - Staging DB:  [READ / NONE]
  - Production:  ❌ Không có access
```

---

## 3. External Services & APIs

```
Được phép gọi:
✅ [Danh sách APIs/Services test mode được phép gọi]

KHÔNG được phép gọi:
❌ [Production APIs / External live keys]
❌ [Bất kỳ dịch vụ nào tốn phí thực tế]
```

---

## 4. Quyền Kiến trúc (Architecture Decisions)

### AI có thể tự quyết định:
```
✅ Cấu trúc file/folder bên trong phạm vi cho phép
✅ Naming conventions (theo pipeline/docs/core/CODE_STANDARDS.md)
✅ Thuật toán & chi tiết implementation
✅ Local error handling & validation logic
```

### Phải hỏi human trước:
```
❓ Thay đổi database schema hiện tại ảnh hưởng đến modules khác
❓ Thay đổi API contract (URL, method, request/response format)
❓ Thêm dependencies mới ngoài danh sách đã chỉ định
```

### KHÔNG được làm dù có lý do:
```
❌ Hardcode credentials, API keys, secrets vào source code
❌ Tắt security checks, validation hoặc authentication
❌ Sửa đổi files trong pipeline/docs/core/
❌ Xóa bớt unit tests / integration tests sẵn có
```

---

## 5. Rollback & Git Permissions

```
AI được phép:
✅ git reset --hard HEAD    (xóa bỏ unstaged/staged changes hiện tại)
✅ git stash / stash pop    (tạm thời lưu / khôi phục changes)
✅ Commit theo đúng quy chuẩn: [TASK-ID] <type>(<scope>): <mô tả ngắn task đã hoàn thành> — CHỈ khi task [x] DONE

Phải hỏi human:
❓ git reset --hard HEAD~N  (quay ngược N commits)
❓ git revert               (tạo revert commit)

KHÔNG bao giờ:
❌ git push --force         (không force push)
❌ git branch -D main/master (không xóa nhánh chính)
```

---

## 6. Thời gian & Tài nguyên Execution

```
Thời gian chạy tối đa mỗi command:  [Ví dụ: 15 phút]
Dung lượng file tối đa tạo ra:      [Ví dụ: < 100MB]
Memory limit:                        [Ví dụ: không vượt 8GB RAM]
```

---

## 7. Escalation Path

Khi AI gặp tình huống chưa rõ ràng hoặc nằm ngoài ranh giới:

```
1. DỪNG LẠI ngay lập tức.
2. Tạo pipeline/docs/runtime/BLOCKED.md mô tả chi tiết lý do.
3. Đặt câu hỏi cụ thể cho Human.
4. Chờ Human phản hồi và cập nhật BOUNDARIES.md trước khi tiếp tục.
```

---

## 8. Lịch sử Thay đổi Boundaries

| Ngày | Thay đổi | Lý do | Người phê duyệt |
|------|---------|-------|----------------|
| [YYYY-MM-DD] | Khởi tạo file template Boundaries | Setup dự án | [Tên] |
