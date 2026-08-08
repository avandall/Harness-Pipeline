# CODE STANDARDS
# Tiêu chuẩn code — Quy tắc viết code trong mọi project

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0
>
> Áp dụng cho mọi ngôn ngữ và framework. `H_docs/context/TECH_CONTEXT.md` sẽ override/bổ sung các rule đặc thù theo project.

---

## 1. Nguyên tắc nền tảng

### 1.1 Readability First
Code được đọc nhiều hơn viết. Ưu tiên rõ ràng hơn ngắn gọn.
```
❌ const x = arr.filter(i => i.a > 5).map(i => i.b).reduce((a,b) => a+b, 0)
✅ const activeItems = arr.filter(item => item.score > 5)
   const values = activeItems.map(item => item.value)
   const total = values.reduce((sum, val) => sum + val, 0)
```

### 1.2 Intention Over Implementation
Comment tại sao, không phải cái gì. Code nói cái gì, comment nói tại sao.
```
❌ // increment counter
   counter++

✅ // Rate limit: allow max 5 requests per minute per user
   userRequestCount++
```

### 1.3 Fail Fast
Validate input sớm, return early, avoid deep nesting.
```
✅ function processUser(user) {
     if (!user) throw new Error('User required')
     if (!user.id) throw new Error('User ID required')
     // ... main logic here, unindented and clean
   }
```

---

## 2. Naming Conventions

### Variables & Functions
| Loại | Convention | Ví dụ |
|------|-----------|-------|
| Variables | `camelCase` | `userProfile`, `requestCount` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_RETRY`, `API_BASE_URL` |
| Functions | `camelCase`, verb-first | `fetchUser()`, `validateEmail()` |
| Classes | `PascalCase` | `UserService`, `PaymentProcessor` |
| Files | `kebab-case` | `user-service.ts`, `auth-middleware.ts` |
| Booleans | `is/has/can` prefix | `isActive`, `hasPermission`, `canEdit` |

### Functions
- Tên phải nói rõ **ý định**: `getUserById()` không phải `getUser()`
- Tối đa **3 tham số** trực tiếp, nhiều hơn dùng object
- Mỗi function làm **đúng một việc**

---

## 3. File Structure

### Module Structure (cho mọi file)
```
1. Imports (external libs trước, internal sau)
2. Constants / Config
3. Types / Interfaces
4. Helper functions (private)
5. Main logic / exports
```

### Project Structure (generic)
```
src/
├── core/           # Business logic, không phụ thuộc framework
├── infrastructure/ # Database, API clients, external services
├── interfaces/     # Types, interfaces, DTOs
├── utils/          # Pure utility functions
└── [feature]/      # Feature-based modules
```

---

## 4. Error Handling

### Nguyên tắc
1. **Never swallow errors**: Luôn log hoặc re-throw
2. **Specific over generic**: Throw lỗi cụ thể, không phải `Error('Something went wrong')`
3. **User-facing vs Internal**: Phân biệt lỗi hiển thị cho user và lỗi internal
4. **Recovery information**: Lỗi phải chứa đủ info để debug

### Template
```typescript
// ✅ Good error handling
try {
  const result = await fetchUserData(userId)
  return result
} catch (error) {
  // Log với context
  logger.error('Failed to fetch user data', { userId, error: error.message })
  
  // Re-throw với context rõ ràng
  throw new ServiceError(`User ${userId} data unavailable`, { 
    cause: error, 
    recoverable: true 
  })
}
```

---

## 5. Testing Standards

### Test Naming
```
describe('UserService', () => {
  describe('fetchUser', () => {
    it('should return user when valid ID provided')
    it('should throw NotFoundError when user does not exist')
    it('should throw ValidationError when ID is invalid format')
  })
})
```

### Test Structure (AAA)
```
// Arrange — chuẩn bị data và mocks
const mockUser = { id: '123', name: 'Test User' }

// Act — gọi function cần test
const result = await userService.fetchUser('123')

// Assert — kiểm tra kết quả
expect(result).toEqual(mockUser)
```

### Coverage Requirements
- Unit tests: ≥ 80% line coverage cho core/ và utils/
- Integration tests: Happy path + 2 error cases cho mỗi API endpoint
- E2E tests: Tất cả critical user flows

---

## 6. Documentation Standards

### Function Documentation
```typescript
/**
 * Tính toán phí giao dịch dựa trên giá trị và loại giao dịch.
 * 
 * @param amount - Giá trị giao dịch (VND)
 * @param type - Loại giao dịch ('domestic' | 'international')
 * @returns Phí giao dịch (VND), không bao gồm VAT
 * @throws {ValidationError} Khi amount <= 0 hoặc type không hợp lệ
 */
function calculateFee(amount: number, type: TransactionType): number
```

### README Requirements
Mỗi module/package phải có README với:
1. Purpose — làm gì
2. Setup — cài đặt thế nào
3. Usage — ví dụ cơ bản
4. API — các functions/endpoints chính

---

## 7. Security Checklist

Trước mỗi commit, check:
- [ ] Không có credentials/secrets trong code
- [ ] Input validation đầy đủ cho tất cả user-facing data
- [ ] SQL queries dùng parameterized queries, không string concatenation
- [ ] Authentication check trước mọi sensitive operation
- [ ] Sensitive data không được log

---

## 8. Performance Guidelines

- **Lazy loading**: Load resources chỉ khi cần
- **Pagination**: Không bao giờ return unbounded list
- **Caching**: Document cache strategy rõ ràng — cache key, TTL, invalidation
- **Database**: Luôn có index cho columns được query thường xuyên
- **Async**: Prefer async/await, tránh blocking operations

---

## 9. Override Rules

`H_docs/context/TECH_CONTEXT.md` có thể override bất kỳ rule nào ở trên với lý do rõ ràng.
Format override:
```
## Code Standards Override
Rule: [tên rule]
Override: [rule mới]
Reason: [tại sao project này cần khác]
```
