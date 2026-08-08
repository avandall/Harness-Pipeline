# REVIEW PROTOCOL
# Giao thức phản biện 2 lớp — Hybrid Verification & Cognitive Review

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 2.0
>
> Không có AI nào đủ tốt để không cần review. Để khắc phục điểm mù của AI (confirmation bias), protocol này kết hợp **Kiểm định Định tính Tự động (Tier 1 CLI)** và **Phản biện Nhận thức Khách quan (Tier 2 LLM)**.

---

## 0. Quy trình Phản biện 2 Lớp (Two-Tier Review)

```
[Mã nguồn mới] ──► [Tier 1: python H_docs/scripts/verify.py] ──► [PASS 100%] ──► [Tier 2: Cognitive LLM Review (git diff)] ──► [APPROVED]
```

- **Tier 1 (Automated Mechanical Checks):** Do CLI Tools đảm nhận (`ruff`, `mypy`, `bandit`, `pytest`). Bắt 100% lỗi cú pháp, kiểu dữ liệu, lỗ hổng bảo mật cơ bản và runtime crash.
- **Tier 2 (Cognitive LLM Review):** Do AI Reviewer đảm nhận qua `git diff`. Đánh giá thiết kế, logic ngầm, edge cases, scalability và clean code.

---

## 1. Tier 2 Cognitive Review Checklist

Thực hiện checklist này trên `git diff` **sau khi Tier 1 đã PASS 100%** (PHASE 5 trong WORKFLOW_STANDARDS).
Kết quả ghi vào `H_docs/runtime/DEBATE_LOG.md`.

### 1.1 Correctness (Tính đúng đắn)
- [ ] Output có đáp ứng **tất cả** acceptance criteria trong PLAN.md không?
- [ ] Tất cả edge cases đã được handle chưa?
- [ ] Có test nào fail không?
- [ ] Logic có đúng với business rules trong PROJECT_BRIEF.md không?
- [ ] Có race condition hoặc timing issue nào không?

### 1.2 Completeness (Tính đầy đủ)
- [ ] Có bước nào bị bỏ sót không?
- [ ] Tất cả error paths có xử lý không?
- [ ] Documentation có được cập nhật không?
- [ ] Migration/rollback plan có được viết không (nếu cần)?

### 1.3 Consistency (Tính nhất quán)
- [ ] Naming có nhất quán với codebase hiện tại không?
- [ ] Code style có tuân theo CODE_STANDARDS.md không?
- [ ] API contract có nhất quán với các endpoints khác không?

### 1.4 Security (Bảo mật)
- [ ] Có hardcoded credentials không?
- [ ] Input validation đầy đủ chưa?
- [ ] Authentication/authorization đúng chưa?

### 1.5 Performance (Hiệu năng)
- [ ] Có N+1 query nào không?
- [ ] Có unbounded loop hoặc recursion không?
- [ ] Memory usage có reasonable không?

### 1.6 Side Effects (Tác dụng phụ)
- [ ] Thay đổi này có phá vỡ gì khác không?
- [ ] Có thay đổi nào ngoài scope không?
- [ ] Backward compatible chưa?

---

## 2. Adversarial Self-Review

Sau khi hoàn thành self-review checklist, thực hiện "Adversarial Mode":

Giả sử vai trò **Senior Engineer đang review code của người khác**. Đặt các câu hỏi khó:

```
1. "Tại sao không làm theo cách X đơn giản hơn?"
2. "Điều gì xảy ra nếu input này là null/empty/extremely large?"
3. "Cái này có fail không nếu service X down?"
4. "Nếu tôi là hacker, tôi sẽ attack vào đâu?"
5. "Code này có dễ maintain sau 6 tháng không?"
6. "Có assumption nào đang được made mà không được validate không?"
```

Ghi từng câu hỏi và câu trả lời vào DEBATE_LOG.md.

---

## 3. Inter-Agent Review (Multi-Agent Debate)

Khi task quan trọng hoặc phức tạp, sử dụng 2-agent review:

### Cách setup

**Agent A — Builder (Người xây dựng):**
```
Prompt: "Bạn vừa hoàn thành [task]. Đây là output của bạn: [output]. 
Hãy giải thích từng quyết định thiết kế bạn đưa ra."
```

**Agent B — Critic (Người phản biện):**
```
Prompt: "Đây là output của một engineer: [output từ Agent A].
Nhiệm vụ của bạn là tìm MỌI vấn đề có thể có. Không giữ lại bất kỳ phê bình nào.
Đặt tối thiểu 5 câu hỏi khó về giải pháp này."
```

**Agent A — Defender (Người phản hồi):**
```
Prompt: "Đây là phê bình về work của bạn: [critique từ Agent B].
Với mỗi điểm phê bình: (1) Đồng ý hay không đồng ý? (2) Lý do? (3) Action cụ thể nếu đồng ý."
```

### Số rounds
- **Task nhỏ**: 1 round (Builder → Critic → Defender)
- **Task trung bình**: 2 rounds
- **Task quan trọng**: 3 rounds hoặc đến khi không còn critique mới

---

## 4. DEBATE_LOG.md Format

Mỗi review session được append vào file này:

```markdown
## Review Session — [date] [time]
### Iteration: N
### Type: self-review | adversarial | inter-agent

#### Questions Raised
1. [Câu hỏi / phê bình]
   - Answer: [Câu trả lời]
   - Action: [FIXED | ACCEPTED_RISK | WON'T_FIX | DEFERRED]
   - Reason: [Lý do]

2. [...]

#### Summary
- Total issues found: N
- Fixed: N
- Accepted risk: N
- Won't fix: N
- Deferred: N

#### Review Result: APPROVED | NEEDS_REVISION | BLOCKED
```

---

## 5. Escalation Triggers

Sau review, nếu bất kỳ điều sau đây là true → tạo `BLOCKED.md`:

- Có issue với severity **CRITICAL** hoặc **HIGH** không thể tự fix
- Critique chỉ ra **contradiction với PROJECT_BRIEF.md**
- Cần **architectural decision** không thể tự quyết định
- Sau 3 rounds debate vẫn không resolve được issue

---

## 6. Review Severity Levels

| Level | Ý nghĩa | Action |
|-------|---------|--------|
| CRITICAL | Security vulnerability, data loss risk | MUST fix before commit |
| HIGH | Functional bug, wrong business logic | MUST fix before commit |
| MEDIUM | Code quality, maintainability | SHOULD fix, document if deferred |
| LOW | Style, naming, minor optimization | CAN fix, log as tech debt |
| INFO | Observation, suggestion | Document in DEBATE_LOG |
