# 📓 LEARNINGS — Durable Knowledge Inbox

> **Harness Engineering Principle (Tip 7 & 21):**
> Collect hard-won discoveries, tricky edge cases, and systemic tool errors here.
> After a Ralph Loop execution, `scripts/ralph-retro.sh` reviews this inbox and promotes actionable lessons into permanent documentation (`docs/*`), routers (`AGENT_GUIDE.md`), or prompt templates (`prompts/*`).

---

## Format for New Entries
```markdown
### [YYYY-MM-DD] <Topic / Symptom>
- **Context / Task:** [TASK-XXX] <Brief context>
- **Root Cause:** What actually went wrong or was missing.
- **Resolution:** What fixed it.
- **Promoted To:** (e.g. `docs/context/TECH_CONTEXT.md` / `scripts/verify.py` / None)
```

---

## Historical Learnings

### [2026-08-31] Ralph Loop Task-Bound Sessions & Memory Flush
- **Context / Task:** Multi-task overnight execution.
- **Root Cause:** Resetting conversation per iteration caused unnecessary reload overhead; keeping conversation across multiple tasks caused context drift & compaction.
- **Resolution:** Adopted Task-Bound Sessions — sustain 1 clean session per Task (maximizing prompt cache), then flush memory completely when switching tasks.
- **Promoted To:** `pipeline/docs/core/HARNESS_PROTOCOL.md` & `pipeline/scripts/harness.sh`.

### [2026-09-07] CLI & Verification Subprocess Execution Timeout Protection
- **Context / Task:** Ralph Loop execution encounters `Error: timeout waiting for response` or hung test runs.
- **Root Cause:** Subprocess test runners and browser/engine checks executed via `verify.py` lacked explicit timeout limits in `run_command()`, causing hanging subprocesses to stall until the parent CLI runner reached maximum print-timeout.
- **Resolution:** Added 60s timeout protection with `subprocess.TimeoutExpired` handling in `verify.py`, added `execution_timeout_seconds` in preset adapters, updated `AGENT_GUIDE.md` and `PROMPT.md` with rapid targeted verification rules (`--quick` / `--test-target`).
- **Promoted To:** `pipeline/scripts/verify.py`, `pipeline/presets/python_backend/preset.yaml`, `pipeline/AGENT_GUIDE.md`, `pipeline/prompts/PROMPT.md`.

### [2026-09-07] Log Analysis False Positive Prevention & Dynamic Workspace Path Anchoring
- **Context / Task:** Ralph Loop retrospective and log analysis (`ralph-analyze.mjs`).
- **Root Cause:**
  1. `ralph-analyze.mjs` regex matched status enum literals (`FAILED` inside `(PENDING, RUNNING, COMPLETED, FAILED)`) in markdown task tables as tool errors.
  2. Executing agents generated hardcoded legacy template paths (e.g. `/project/boilerplate/`) in file links instead of dynamically referencing the active project root.
- **Resolution:** Updated `ralph-analyze.mjs` regex filtering to skip false positive status enum descriptions, and updated `AGENT_GUIDE.md` and `prompts/PROMPT.md` to mandate dynamic workspace path anchoring.
- **Promoted To:** `pipeline/scripts/ralph-analyze.mjs`, `pipeline/AGENT_GUIDE.md`, `pipeline/prompts/PROMPT.md`.

### [2026-09-09] Prevention of Verification Script Background Wrapping & Turn Timeout
- **Context / Task:** Ralph Loop execution encountering turn runner timeouts during task verification.
- **Root Cause:** Executor agent launched deterministic quality verification (`python3 pipeline/scripts/verify.py`) as an asynchronous background task instead of executing it synchronously in the foreground, causing the turn runner to stall waiting for background notifications.
- **Resolution:** Updated `AGENT_GUIDE.md`, `prompts/PROMPT.md`, and `harness.sh` executor payload to mandate synchronous foreground execution for `verify.py` with fast target flags (`--quick` / `--test-target`), explicitly prohibiting wrapping deterministic verification checks in background tasks.
- **Promoted To:** `pipeline/AGENT_GUIDE.md`, `pipeline/prompts/PROMPT.md`, `pipeline/scripts/harness.sh`.
