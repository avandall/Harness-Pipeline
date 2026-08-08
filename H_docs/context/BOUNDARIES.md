# BOUNDARIES
# Giới hạn quyền hạn — Những gì AI được và không được làm

> **Trạng thái:** CONTEXT (Mutable) | **Cập nhật:** Khi có task mới hoặc khi scope thay đổi
>
> ✏️ **HUMAN FILLS THIS FILE.** AI phải đọc và tuân thủ nghiêm ngặt.
>
> ⚠️ **CRITICAL:** Đây là "hợp đồng" giữa bạn và AI. Nếu không rõ ràng, AI sẽ đặt câu hỏi thay vì tự ý làm.

---

## 1. Phạm vi File (File Scope)

### AI được phép đọc và sửa:
```
✅ [Ví dụ: src/auth/**]
✅ [Ví dụ: prisma/schema.prisma — CHỈ thêm bảng mới, không sửa bảng hiện có]
✅ [Ví dụ: H_docs/runtime/**]
✅ [Ví dụ: tests/auth/**]
```

### AI KHÔNG được chạm vào:
```
❌ [Ví dụ: src/payment/** — module thanh toán đang được maintain riêng]
❌ [Ví dụ: .env* files — chỉ đọc .env.example]
❌ [Ví dụ: prisma/migrations/** — không tạo migration thủ công]
❌ [Ví dụ: package.json — không thêm/xóa dependencies]
```

---

## 2. Database Permissions

```
READ:    ✅ / ❌  [Được đọc dữ liệu production không?]
WRITE:   ✅ / ❌  [Được ghi dữ liệu không?]
MIGRATE: ✅ / ❌  [Được chạy migrations không?]
DROP:    ❌        [Không bao giờ được phép DROP]

Môi trường:
  - Local DB:    ✅ Tất cả quyền
  - Staging DB:  [Chỉ READ / READ+WRITE]
  - Production:  ❌ Không có access
```

---

## 3. External Services

```
Được gọi:
✅ [Ví dụ: Stripe API — chỉ Test mode key]
✅ [Ví dụ: SendGrid — chỉ sandbox mode]

KHÔNG được gọi:
❌ [Ví dụ: Stripe Production keys]
❌ [Ví dụ: Bất kỳ third-party analytics nào không có trong TOOL_REGISTRY.md]
```

---

## 4. Quyền Kiến trúc (Architecture Decisions)

### AI có thể tự quyết định:
```
✅ Internal file/folder structure trong scope
✅ Naming conventions (theo CODE_STANDARDS.md)
✅ Thuật toán implementation
✅ Error handling patterns
```

### Phải hỏi human trước:
```

❓ Thay đổi database schema của bảng hiện có
❓ Thay đổi API contract (endpoint URL, request/response format)
❓ Bất kỳ thay đổi nào ảnh hưởng đến nhiều modules

```

### KHÔNG được làm dù có lý do:
```
❌ Hardcode credentials, API keys, secrets
❌ Disable security checks hoặc validation
❌ Thay đổi production config
❌ Xóa data hoặc logs
❌ Tắt error tracking/monitoring
```

---

## 5. Network & Security

```
Được phép:
✅ HTTP requests đến services trong TOOL_REGISTRY.md
✅ Đọc public APIs (no auth) cho research

KHÔNG được phép:
❌ Lưu trữ bất kỳ credentials nào trong code
❌ Bypass CORS hoặc security headers
❌ Log PII (Personal Identifiable Information): email, phone, address
```

---

## 6. Rollback Permissions

```
AI được phép:
✅ git reset --hard HEAD    (rollback unstaged changes)
✅ git stash               (tạm thời lưu changes)

Phải hỏi human:
❓ git reset --hard HEAD~N  (rollback N commits — có thể mất work)
❓ git revert               (tạo revert commit)

KHÔNG bao giờ:
❌ git push --force         (không được force push)
❌ git rebase production    (không rebase production branch)
```

---

## 7. Thời gian & Tài nguyên

```
Thời gian chạy tối đa mỗi command:  [Ví dụ: 15 phút — nếu lâu hơn, kill và report]
Disk space tối đa:                  [Ví dụ: Không tạo file > 200MB]
Memory limit:                        [Ví dụ: Build process không được vượt 8GB RAM]
```

---

## 8. Escalation Path

Khi AI gặp tình huống không có trong Boundaries:

```
1. DỪNG LẠI — không tự ý làm
2. Tạo BLOCKED.md với mô tả tình huống
3. Đặt câu hỏi cụ thể: "Tôi cần làm X để hoàn thành Y. Có được phép không?"
4. Chờ human trả lời và cập nhật BOUNDARIES.md
```

---

## 9. Lịch sử thay đổi Boundaries

| Ngày | Thay đổi | Lý do | Người phê duyệt |
|------|---------|-------|----------------|
| [YYYY-MM-DD] | [Mô tả thay đổi] | [Lý do] | [Tên] |


## Note : ./H_docs/harness.sh --max-iter 30 --timeout 20m0s

