# TOOL REGISTRY
# Danh mục công cụ — Tools, Commands, MCPs được phép sử dụng

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0
>
> Định nghĩa tools nào được phép dùng, khi nào dùng, và cách dùng đúng. Cập nhật khi thêm tool mới vào workflow.

---

## 1. Nguyên tắc sử dụng Tool

1. **Prefer built-in over external**: Dùng tool có sẵn trong môi trường trước khi thêm dependency mới
2. **Declare before use**: Mọi tool được dùng phải có trong registry này
3. **Minimal permissions**: Chỉ request permissions cần thiết
4. **Audit trail**: Mọi tool call quan trọng phải được log trong PROGRESS_LOG.md

---

## 2. Core Tools (Luôn có sẵn)

### Git
| Command | Use Case | Ghi chú |
|---------|----------|---------|
| `git status` | Kiểm tra thay đổi hiện tại | Chạy trước mỗi commit |
| `git add -p` | Stage changes có chọn lọc | Preferred over `git add .` |
| `git commit -m "..."` | Tạo checkpoint | Theo format trong HARNESS_PROTOCOL.md |
| `git log --oneline -20` | Xem lịch sử gần đây | |
| `git diff HEAD~1` | So sánh với commit trước | |
| `git reset --hard HEAD` | Rollback toàn bộ unstaged changes | ⚠️ Không thể undo |
| `git reset --hard HEAD~N` | Rollback N commits | ⚠️ Không thể undo |
| `git stash` | Tạm thời lưu changes | Khi cần switch context |

### Filesystem
| Operation | Use Case |
|-----------|----------|
| Read files | Luôn đọc file trước khi sửa |
| Write files | Tạo/cập nhật code và docs |
| List directory | Hiểu cấu trúc trước khi thay đổi |

### Shell Commands
| Command | Use Case |
|---------|----------|
| `cat`, `head`, `tail` | Đọc nội dung file |
| `grep`, `find` | Tìm kiếm trong codebase |
| `mkdir -p` | Tạo thư mục |
| `cp`, `mv` | Copy/move files |
| `chmod` | Phân quyền file |

---

## 3. Package Managers

| Tool | Ecosystem | Khi nào dùng |
|------|-----------|-------------|
| `npm` | Node.js | Default cho JS/TS projects |
| `yarn` | Node.js | Nếu project đã dùng yarn.lock |
| `pnpm` | Node.js | Nếu project đã dùng pnpm-lock |
| `pip` | Python | Python projects |
| `poetry` | Python | Nếu project có pyproject.toml |

⚠️ **Rule**: Không mix package managers trong cùng project. Check lockfile trước khi cài package.

---

## 4. Test Runners

| Tool | Ecosystem | Command |
|------|-----------|---------|
| Jest | JS/TS | `npx jest --coverage` |
| Vitest | Vite/Vue | `npx vitest run` |
| pytest | Python | `python -m pytest -v` |
| go test | Go | `go test ./...` |

---

## 5. Code Quality Tools

| Tool | Loại | Command |
|------|------|---------|
| ESLint | JS/TS Linting | `npx eslint src/ --max-warnings 0` |
| Prettier | Formatting | `npx prettier --check src/` |
| TypeScript | Type check | `npx tsc --noEmit` |
| Ruff | Python Linting | `ruff check .` |
| Playwright | UI testing | `npx playwright test` |
| Chroma | Database query | `npx chroma query` |

---

## 6. MCP Servers (Model Context Protocol)

Đây là extension points để AI tương tác với external systems.

| MCP Server | Chức năng | Khi nào dùng |
|-----------|----------|-------------|
| `filesystem` | Read/write files | Default, luôn available |
| `git` | Git operations | Khi cần git operations phức tạp |
| `browser` | Web scraping, UI testing | Khi cần interact với web |
| `database` | Query DB trực tiếp | ⚠️ Chỉ dùng read-only trong dev |
| `chrome_devtools` | Debug chrome | Khi cần debug chrome |

> **Để thêm MCP server mới:** Phải có approval từ `pipeline/docs/context/BOUNDARIES.md` trước.

---

## 7. Forbidden Tools / Patterns

❌ **KHÔNG được dùng:**
- `rm -rf` mà không có git backup
- `DROP TABLE` hoặc destructive DB operations không có transaction + backup
- Hardcoded credentials trong bất kỳ command nào
- `sudo` commands trừ khi được specify rõ trong BOUNDARIES.md
- Direct production database modifications

---

## 8. Thêm Tool Mới

Khi cần dùng tool chưa có trong registry:
1. Ghi vào `BLOCKED.md`: "Need tool X for Y purpose"
2. Chờ human approve
3. Sau khi approve, thêm vào registry này
4. Document use case và constraints rõ ràng
