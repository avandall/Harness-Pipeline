# AGENTS — Harness Engineering Router Adapter

> Loaded automatically by Antigravity and compatible AI agents.
> This file is a thin adapter pointing to `pipeline/AGENT_GUIDE.md`.

---

## 🚦 Operating Modes

### 🟢 MODE 1: Interactive Assistant (IDE Chat / Debugging)
- Direct user conversation. Do NOT run `harness.sh` or edit runtime files unless explicitly requested.
- Explain, analyze, and pair-program as a Senior Engineer.

### 🤖 MODE 2: Autonomous Ralph Loop (CLI Headless via `harness.sh`)
- Activated by `./harness.sh` or prompts starting with `[TASK-BOUND SESSION ...]`.
- Follow the router at `pipeline/AGENT_GUIDE.md` and 10 Inviolable Rules.
- State on disk, verify with `python3 pipeline/scripts/verify.py`, commit only when `[x] DONE`.
