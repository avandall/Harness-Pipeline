# Loop & Exit Strategy — READ FIRST

> **Authority: principles.** How the migrate loop runs and — critically — **when it stops**. Runner: `scripts/ralph.sh`.
> Per-iteration prompt: `prompts/PROMPT.md`. Harness note: a loop without explicit exits is a bill, not a harness.

## The loop in one line
`scripts/ralph.sh` repeatedly invokes the selected provider (via `scripts/agent-runner.sh`) on `prompts/PROMPT.md`.
Each invocation advances the first unfinished page in the sealed `migrations/_queue.tsv` (`.ralph/ACTIVE_PAGE`)
through its next phase. Progress lives in **files + git + the page's evidence pack**, so a crashed or compacted
session resumes the same page instead of starting blind.

## Two runner modes, one contract
- **Loop (default):** a fresh invocation per page/phase; resumable; context recycled at page boundaries.
- **One go (`--one-go`):** `plan.sh` invokes `prompts/PLAN_ALL.md` exactly once (discovery + all packs);
  `ralph.sh --one-go` invokes `prompts/IMPLEMENT_ALL.md` exactly once for every unfinished page. `migrate.sh --one-go`
  = exactly two invocations. One-go removes the shell's per-page loop, not the harness: queue, evidence packs, gates,
  deploy rules, logs, and resume are identical; an early end, a provider failure, or compaction fails the run.

## Two layers of "done"
1. **Per-page gate (inner):** zero open `visual-deltas.md` + `gate.json` pass (hash-bound to the contract) +
   interactions verified + assets exact + records/routes intact, desktop AND mobile, plus the eye-level VISUAL-VERIFY.
   Decided by **comparison against the source**, never by the agent's self-assessment.
2. **Per-loop exit (outer — the runner decides, in priority order):**

| # | Condition | Action | exit |
|---|---|---|---|
| 1 | **Work complete** — queue validates; every queued page gated with both final reports | success | `0` |
| 2 | **Blocked** — `.ralph/BLOCKED` exists (needs a human: a decision, a one-time login, an unverified capability) | stop + escalate | `3` |
| 3 | **Max iterations** (`RALPH_MAX_ITERATIONS`, default 200) | stop (safety cap) | `4` |
| 4 | **Budget** exceeded (`RALPH_MAX_BUDGET_USD`, default 500; token cap `RALPH_MAX_TOKENS`) | stop (cost cap) | `5` |
| 5 | **Stuck** — no new commit for `RALPH_NO_PROGRESS` loops | stop + escalate (circuit breaker) | `6` |
| 6 | **Context blowup** — the invocation auto-compacted mid-run | stop hard — re-narrow the task | `7` |
| 7 | **Provider/API failure** — a failed turn/process, or `RALPH_API_MAX` consecutive retryable errors | stop; state resumable | `8` |

> **Why exit 7 is a HARD fail:** a page/phase must sit well under the context window. If it auto-compacts, quality has
> already degraded — stop and re-narrow rather than commit degraded work.
> **Transient provider/5xx errors do not trip the stuck breaker** — the loop backs off (`RALPH_API_BACKOFF`) and retries.

**Natural terminator:** for every route in the sealed queue: zero open `- [ ]` in `visual-deltas.md` /
`interactions.md`, both `reports/final.md` and `reports/visual-verify.md`, and a fresh `gate.json` with
`visualPass: true`, `openDeltas: 0`, contract hash matching. A missing queue or pack is an error, never success.
*Regression-tested by `scripts/ralph-selftest.sh`, `plan-selftest.sh`, `migrate-selftest.sh`, `follow-up-selftest.sh`
(throwaway repos, stub agents, no network) — run `npm run test:orchestration`.*

## When to recycle context
At the page/phase boundary. Don't run one conversation toward compaction to "save" reloads; keep each phase's context
small (research via subagents, big files read in parts). Treat caps as ceilings that stop a run, not targets.

## Blocked vs stuck (operator playbook)
- **Blocked** = the task *can't* proceed (unverified API, a human decision, a one-time admin login). The agent writes one
  line + unblock steps to `.ralph/BLOCKED`; the loop stops cleanly. Fix → `rm .ralph/BLOCKED` → rerun.
- **Stuck** = it runs but lands no commits. Re-narrow to one item, tune `prompts/PROMPT.md`, clarify the contract, or
  `git reset --hard` and rerun. *"Any problem created by AI can be resolved through a different series of prompts."*
