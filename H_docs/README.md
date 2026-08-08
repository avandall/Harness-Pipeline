# Harness Engineering Docs System — README
# Điểm vào — Đọc trước khi làm bất cứ điều gì

> Đây là bộ docs chuẩn hoá theo triết lý **Harness Engineering / Ralph Loop** — thiết kế để AI agent hoạt động tự trị, có thể kiểm soát, và luôn có đủ context để thực hiện bất kỳ task nào.

---

## Cấu trúc

```
H_docs/
├── core/                      🔒 FIXED — Không thay đổi theo task
│   ├── AGENT_CONSTITUTION.md  Luật nền tảng (đọc đầu tiên)
│   ├── HARNESS_PROTOCOL.md    Ralph Loop + State machine
│   ├── WORKFLOW_STANDARDS.md  Pipeline 7 phases (Hybrid Verification)
│   ├── CODE_STANDARDS.md      Tiêu chuẩn code universal
│   ├── REVIEW_PROTOCOL.md     Tự phản biện 2 lớp (Tier 1 & Tier 2)
│   ├── TOOL_REGISTRY.md       Danh sách tools được phép dùng
│   └── GLOSSARY.md            Từ điển thuật ngữ
│
├── context/                   ✏️ MUTABLE — Bạn cập nhật theo từng task
│   ├── PROJECT_BRIEF.md       Mô tả dự án (cập nhật khi bắt đầu project)
│   ├── TECH_CONTEXT.md        Tech stack và môi trường
│   ├── Tasks_list.md        ← CẦN CẬP NHẬT TRƯỚC MỖI TASK MỚI
│   └── BOUNDARIES.md          Giới hạn quyền của AI
│
├── scripts/                   🛠️ HARNESS TOOLING — Công cụ hỗ trợ AI
│   └── verify.py              Kiểm định định tính (Ruff/Mypy/Bandit/Pytest) + Log Truncator
│
└── runtime/                   🤖 AUTO-GENERATED — AI tự tạo khi chạy
    ├── PLAN.md                Kế hoạch thực thi (AI tạo)
    ├── STATUS.md              Trạng thái real-time
    ├── VERIFICATION_REPORT.md Kết quả kiểm định định tính Tier 1
    ├── PROGRESS_LOG.md        Nhật ký chi tiết mỗi iteration
    ├── PROOF_OF_SOLUTION.md   Bằng chứng hoàn thành
    ├── DEBATE_LOG.md          Lịch sử tự phản biện Tier 2
    ├── BLOCKED.md             ← Xuất hiện khi AI cần help
    └── ITERATIONS/            Snapshot từng vòng lặp
```

---

## Cách dùng cho task mới

### Bước 1: Cập nhật context (2-5 phút)

Chỉ cần sửa **2 files** tối thiểu:

```bash
# File QUAN TRỌNG NHẤT — mô tả task cho AI
nano H_docs/context/Tasks_list.md

# Nếu task liên quan đến giới hạn đặc biệt
nano H_docs/context/BOUNDARIES.md
```

### Bước 2: Clear runtime (nếu task mới hoàn toàn)

```bash
# Xóa runtime docs từ task trước (nếu muốn fresh start)
rm -rf H_docs/runtime/*.md H_docs/runtime/ITERATIONS/
# Hoặc commit chúng trước: git add H_docs/runtime/ && git commit -m "archive: prev task runtime"
```

### Bước 3: Giao task cho AI

Chỉ cần nói với AI:
```
Hãy đọc H_docs/ và thực hiện task trong Tasks_list.md theo Harness Protocol.
```

AI sẽ tự:
- Đọc tất cả docs cần thiết
- Tạo `PLAN.md`
- Thực thi theo Ralph Loop
- Tạo `PROOF_OF_SOLUTION.md` khi xong

### Bước 4: Chạy tự động (optional)

```bash
# Cấp quyền thực thi
chmod +x harness.sh

# Chạy harness
./harness.sh --task "TASK-001"

# Xem options
./harness.sh --help
```

---

## Khi AI tạo BLOCKED.md

```bash
# Đọc file để biết vấn đề
cat H_docs/runtime/BLOCKED.md

# Sau khi giải quyết, xóa file để AI tiếp tục
rm H_docs/runtime/BLOCKED.md

# Chạy lại harness
./harness.sh
```

---

## Philosophy

> **"Filesystem là bộ nhớ. Git là lịch sử. BLOCKED.md là phanh khẩn cấp."**
>
> Thay vì giữ context trong conversation (dễ bị "context rot"), toàn bộ state được externalise ra filesystem. Mỗi iteration, AI bắt đầu với fresh context và đọc state từ files. Điều này giúp:
>
> - **Reproducible**: Bất kỳ AI nào cũng có thể tiếp tục từ điểm dừng
> - **Auditable**: Mọi quyết định đều được log
> - **Recoverable**: `git reset --hard` là recovery mechanism
> - **Scalable**: Có thể song song nhiều agents mà không conflict context

---

## Files bạn cần quan tâm nhất

| File | Tần suất cập nhật | Ai cập nhật |
|------|------------------|------------|
| `context/Tasks_list.md` | Mỗi task mới | **Bạn** |
| `context/PROJECT_BRIEF.md` | Mỗi project mới | **Bạn** |
| `context/BOUNDARIES.md` | Khi scope thay đổi | **Bạn** |
| `runtime/BLOCKED.md` | Khi AI cần help | AI tạo, **Bạn** giải quyết |
| `runtime/PROOF_OF_SOLUTION.md` | Khi task done | AI |

---

## Versioning

```
Docs System Version: 1.0.0
Harness Protocol: 1.0
Last Updated: 2026-08-07
```
