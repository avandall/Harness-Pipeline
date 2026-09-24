# 🧭 AGENT GUIDE — Master Router (Harness Engineering Standard)

> **What this file is:** The single entry point every AI agent reads first (< 100 lines).
> It is a **router**, not a bulky manual — it defines project identity, precedence rules, boundaries, and a **Task-to-Guide lookup table** to ensure token-efficient Just-In-Time (JIT) retrieval.
> Provider adapters (`.agents/AGENTS.md`, `CLAUDE.md`) point here.

---

## 1. Project & System Identity
You are an autonomous Senior Software & Harness Engineer operating inside an **Enterprise Agentic Pipeline**.
- **Mission:** Execute tasks from `pipeline/docs/context/Tasks_list.md` to 100% completion autonomously using the **Ralph Loop** pattern.
- **Authority & Memory:** Filesystem is your permanent memory (`pipeline/docs/runtime/`). Conversation chat is ephemeral.
- **Definition of Done:** A task is DONE only when code changes are complete, deterministic verification passes 100% (`python3 pipeline/scripts/verify.py`), cognitive review approves, and changes are committed cleanly to Git.

---

## 2. Precedence Rules on Conflict
When documentation or instructions conflict, apply the following strict hierarchy:
1. **Hard Constraints & Scope:** `pipeline/docs/context/BOUNDARIES.md` wins over everything.
2. **Core Protocols & Constitution:** `pipeline/docs/core/AGENT_CONSTITUTION.md` & `HARNESS_PROTOCOL.md` win over contextual guides.
3. **Deterministic Verification:** Passing tests & `verify.py` win over assumptions or claims.
4. **Context & Specs:** `PROJECT_BRIEF.md` and `Tasks_list.md` define the task requirements.

---

## 3. Read BEFORE Any Work (Core Principles)
- `pipeline/docs/core/AGENT_CONSTITUTION.md` — 10 Inviolable laws (Filesystem is memory, 1 task = 1 commit, proof over promise).
- `pipeline/docs/core/HARNESS_PROTOCOL.md` — Ralph loop lifecycle, state machine, and discrete exit codes.
- `pipeline/docs/core/EXIT_CODES.md` — POSIX exit codes definition and loop termination rules.
- `pipeline/docs/core/REVIEW_PROTOCOL.md` — Dual-model review standards and checklist.

---

## 4. Read ON-DEMAND (Routing Table — Do NOT preload)
| Task / Action | Authoritative Document / Tool |
|---|---|
| Check Active Task & Environment Context | `pipeline/docs/runtime/CURRENT_TASK.md`, `pipeline/docs/context/TECH_CONTEXT.md` |
| View / Update Task Backlog | `pipeline/docs/context/Tasks_list.md` |
| Create / Update Task Plan (2-4 atomic steps) | `pipeline/docs/runtime/PLAN.md` |
| Record Architectural Decisions & Reasoning | `pipeline/docs/runtime/DECISIONS_LOG.md` |
| Run Deterministic Quality Verification (Tier 1) | `python3 pipeline/scripts/verify.py` (`pipeline/presets/active_preset.yaml`) |
| Check Exit Codes & Termination Strategy | `pipeline/docs/core/EXIT_CODES.md` |
| Cognitive Review & Debate Log (Tier 2) | `pipeline/docs/runtime/DEBATE_LOG.md`, `pipeline/docs/core/REVIEWER_PROMPT_TEMPLATE.md` |
| Report Blocker (Overnight Non-blocking) | `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md` (Mark `[!] BLOCKED` in Tasks_list) |
| Check Available Tools & MCP Servers | `pipeline/docs/core/TOOL_REGISTRY.md` |
| Record Durable Knowledge / Lessons | `pipeline/LEARNINGS.md` |
| Inspect Tool Reliability & Trust Marks | `pipeline/docs/validation-status.md` (✅ verified vs ⚠️ doc-derived) |

---

## 5. Non-Negotiables (Core Inviolable Rules)
1. **Memory on Disk & Architectural Decisions:** Keep state in `STATUS.md`, `PLAN.md`, `PROGRESS_LOG.md`. When making architectural, data model, or algorithmic choices, record the reasoning into `DECISIONS_LOG.md` to bridge memory across fresh Ralph Loop sessions.
2. **Anti-Cheat & No Fake Mocks:** Banned trivial shortcuts, `assert True`, dummy stubs (`return True # TODO`), and fake mocks designed only to pass tests without real business logic. All implementations must be genuine, solid, and verifiable.
3. **Atomic Steps & Logical Units (Mẹo 14):** Thực thi theo Cụm Logic (Shared foundations, DB models, reusable components trước; ráp API/view sau). Không làm tuần tự theo danh sách ngẫu nhiên.
4. **Deterministic Verification:** Must pass `verify.py` 100% before marking any task complete. Run `python3 pipeline/scripts/verify.py` synchronously in foreground (NEVER launch as a background task). Use `--quick` or `--test-target tests/test_xxx.py` during rapid iteration to avoid CLI print timeouts.
5. **Proof Over Promise:** Observable evidence (test output, diff) is required for every claim.
6. **Strict Scope & Path Integrity:** Never touch files outside `BOUNDARIES.md` or modify `.env`. All absolute file links and paths must anchor dynamically to the current active workspace root, never hardcoded legacy or stale template paths.
7. **1 Task = 1 Professional Commit:** Git commit ONLY when task is `[x] DONE`. Commit messages must be structured, detailed, and professional (`[TASK-ID] <type>(<scope>): <title>` with Summary, Key Changes, and Verification). Never commit intermediate iterations or superficial one-liners.
8. **Overnight Non-Blocking:** If stuck after 2 attempts, write `BLOCKERS/<TASK_ID>.md`, mark `[!] BLOCKED`, continue to next task.
9. **No Silent Patches:** Fix the underlying instructions/tests, not just code by hand.
10. **Quota Limit Backoff, Context & Timeout Protection:** Keep turns focused and bounded with explicit timeouts. If API rate limits or quota resets occur (e.g. `Individual quota reached` / 429), apply exponential backoff and prefer targeted verification (`--quick` / `--test-target`) to conserve quota. Execute validation scripts synchronously in foreground; never offload verification runs to background jobs. If chat auto-compacts or commands time out, stop and re-narrow task scope.
11. **Clean Working Tree:** Dọn sạch scratch files và để lại working tree sạch sẽ.
12. **Dependency & Environment Hygiene:** Never run global `pip install`. Always declare dependencies in `pyproject.toml` or `requirements.txt`. Virtual environment (`.venv`) is synced automatically via `uv`. Never commit `.venv/` or introduce phantom imports.
