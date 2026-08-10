# AGENT CONSTITUTION
# Hiến pháp AI — Luật nền tảng không thể thương lượng

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 1.0 | **Cập nhật:** Chỉ khi thay đổi toàn bộ quy trình
>
> ⚠️ **MANDATORY READ:** Every AI agent MUST read this document fully before taking any action in this workspace.

---

## Điều 1 — Filesystem Is Memory (Tệp tin là bộ nhớ)

You do NOT rely on conversation history as your primary memory. Every decision, assumption, plan, and result MUST be written to the appropriate file in `H_docs/runtime/`. If it is not written down, it does not exist.

```
Conversation context = temporary working memory
H_docs/runtime/       = permanent authoritative state
```

## Điều 2 — Read Before Write (Đọc trước khi viết)

Before generating any output or making any change, you MUST:
1. Read `H_docs/context/CURRENT_TASK.md` — understand the exact task scope
2. Read `H_docs/context/PROJECT_BRIEF.md` — understand project constraints
3. Read `H_docs/context/BOUNDARIES.md` — understand what you are NOT allowed to do
4. Read `H_docs/runtime/STATUS.md` (if exists) — understand current state

Never assume context. Always read it.

## Điều 3 — One Loop, One Scope (Mỗi vòng lặp, một phạm vi)

Each iteration of work must be:
- **Atomic**: Completable in one coherent unit
- **Verifiable**: Has a clear pass/fail exit condition
- **Logged**: Appended to `H_docs/runtime/PROGRESS_LOG.md` after completion
- **Committed**: Results committed to git before the next iteration starts

Do not compound multiple unrelated changes in one iteration.

## Điều 4 — Proof Over Promise (Bằng chứng hơn lời hứa)

Never claim something "works" or "is done" without objective evidence. Before marking any task complete:
- Run `python3 H_docs/scripts/verify.py` and ensure Tier 1 checks pass 100%.
- Inspect `H_docs/runtime/VERIFICATION_REPORT.md` for zero errors.
- Document results in `H_docs/runtime/PROOF_OF_SOLUTION.md`.
- If verification cannot be run, explicitly state why and what manual steps are needed.

## Điều 5 — Fail Loudly, Not Silently (Thất bại rõ ràng, không âm thầm)

If you are blocked, uncertain, or detect a contradiction:
1. STOP immediately — do not proceed with guesses
2. Create `H_docs/runtime/BLOCKED.md` with:
   - Exact point of failure
   - What you attempted
   - What information/decision is needed from a human
3. Do NOT attempt to paper over the blocker with workarounds

## Điều 6 — Critique Before Commit (Phản biện trước khi cam kết)

Before committing any significant change:
1. Ensure Tier 1 Deterministic Verification (`verify.py`) has PASSED.
2. Execute Tier 2 Cognitive Review on `git diff` using checklist from `H_docs/core/REVIEW_PROTOCOL.md`.
3. Document review output in `H_docs/runtime/DEBATE_LOG.md`.

## Điều 7 — Respect Boundaries (Tôn trọng giới hạn)

`H_docs/context/BOUNDARIES.md` defines hard limits for the current task. You MUST NOT:
- Modify files outside the declared scope
- Install dependencies not listed in TECH_CONTEXT.md without explicit approval
- Make architectural decisions that contradict PROJECT_BRIEF.md
- Delete data or files unless explicitly instructed

## Điều 8 — Git Is Your Safety Net (Git là mạng lưới an toàn)

**Commit sớm, commit nhỏ, commit thường xuyên — như một senior developer.**

### Quy tắc Atomic Commit (QUAN TRỌNG)

```
Mỗi commit = đúng 1 đơn vị có thể review độc lập
```

**ĐÚNG** — mỗi commit là một unit rõ ràng:
```
[iter-2] feat(auth): add JWT token generation
[iter-2] feat(auth): add JWT validation middleware  
[iter-2] test(auth): add unit tests for JWT service
[iter-2] docs(auth): update API docs for /login endpoint
```

**SAI** — gom nhiều thứ vào 1 commit:
```
[iter-2] feat: implement auth, add tests, update docs, fix bug in user model
```

### Khi nào commit?
- Hoàn thành xong **1 function, 1 feature, hoặc 1 task logic hoàn chỉnh** → commit 1 lần cho cả đơn vị công việc đó.
- Sửa xong **1 bug** → commit riêng cho bug fix.
- Refactor xong **1 module** → commit riêng cho refactoring.
- KHÔNG commit vụn vặt từng file đơn lẻ liên tục nếu các file đó phục vụ cùng một mục tiêu công việc (ví dụ: dọn dẹp bộ 4 docs context thì gom commit 1 lần cho cả bộ docs thay vì tách làm 4 commits riêng).

### Commit message format
```
[iter-N] <type>(<scope>): <short description>

Types: feat | fix | refactor | docs | test | chore
Example: [iter-3] fix(auth): handle null user in JWT middleware
```

### Recovery
If anything goes wrong: `git reset --hard HEAD` hoặc `git reset --hard HEAD~1`.
Commit nhỏ = mỗi rollback chỉ mất ít nhất công sức.

## Điều 9 — Escalate, Don't Improvise (Leo thang, không tự ý)

When facing a decision that is:
- Not covered by existing docs
- Contradicted by two different instructions
- Potentially destructive or irreversible

→ STOP. Document the dilemma in `BLOCKED.md`. Request human input. Do not improvise.

## Điều 10 — Continuous Improvement (Cải tiến liên tục)

After each task is marked DONE, append a "Retrospective" section to `PROOF_OF_SOLUTION.md` with:
- What worked well
- What could be improved in the harness itself
- Any rule in this Constitution that should be updated

---

## Thứ tự đọc docs khi bắt đầu task mới

```
1. H_docs/core/AGENT_CONSTITUTION.md        ← Bạn đang ở đây
2. H_docs/core/HARNESS_PROTOCOL.md          ← Hiểu cơ chế vòng lặp
3. H_docs/core/WORKFLOW_STANDARDS.md        ← Hiểu từng bước thực thi
4. H_docs/context/PROJECT_BRIEF.md          ← Hiểu dự án
5. H_docs/context/CURRENT_TASK.md           ← Hiểu task cụ thể
6. H_docs/context/BOUNDARIES.md             ← Biết giới hạn
7. H_docs/runtime/STATUS.md                 ← Biết trạng thái hiện tại
→ Bắt đầu tạo/cập nhật H_docs/runtime/PLAN.md
```
