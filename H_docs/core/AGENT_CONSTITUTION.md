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
- **Logged**: Appended to `H_docs/runtime/PROGRESS_LOG.md` after completion of each step/iteration (written to filesystem to maintain memory across fresh agy runs)
- **Committed**: Git commit is created ONLY when the target task is completely DONE (`[x] DONE`). Intermediate iterations update filesystem runtime docs without making git commits.

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

**Commit theo Task hoàn chỉnh — rõ ràng, mạch lạc, đúng thứ tự.**

### Quy tắc Task-Based Commit (QUAN TRỌNG)

```
Mỗi commit = đúng 1 Task hoàn chỉnh đã pass verify [x] DONE
```

**ĐÚNG** — commit rõ ràng, mạch lạc, đúng thứ tự task:
```
[TASK-001] feat(infra): setup database schema & SQLAlchemy models
[TASK-002] feat(auth): add JWT token generation and validation middleware
[TASK-003] fix(quota): resolve boundary edge cases in quota enforcement
```

**SAI** — commit vụn vặt từng iteration hoặc mỗi lần cập nhật runtime docs:
```
[iter-1] chore: iter-1 complete — continue
[iter-2] chore: iter-2 complete — continue
[iter-3] docs: update status.md
```

### Khi nào commit?
- **CHỈ commit khi TASK hoàn thành (`[x] DONE`)**: Sau khi task đã hoàn tất tất cả các bước, được kiểm tra (Phase 4 VERIFY) và phản biện (Phase 5 REVIEW) pass 100%.
- **Trong khi task chưa xong**: Cập nhật runtime docs (`STATUS.md`, `PROGRESS_LOG.md`, `PLAN.md`) ra filesystem liên tục để lưu progression context cho Ralph loop khi reset phiên, nhưng **KHÔNG chạy git commit**.

### Commit message format
```
[TASK-ID] <type>(<scope>): <short description of completed task>

Types: feat | fix | refactor | docs | test | chore
Example: [TASK-001] feat(auth): implement JWT authentication handler
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
