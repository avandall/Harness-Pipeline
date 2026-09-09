# IMPLEMENT_ALL — Implement the complete migration in one agent invocation (one-go)

> The experimental **one-go Execute** worker. The outer runner (`scripts/ralph.sh --one-go`) invokes you exactly once. In
> this invocation, implement, deploy, converge, test, gate, and visually verify **every unfinished page** in the sealed
> queue. Do not spawn or delegate to another agent.

Read `AGENT_GUIDE.md`, `prompts/PROMPT.md`, `docs/principles/visual-migration.md`, `docs/contract-and-evidence.md`, the
routed craft/ops/runbook docs, and `LEARNINGS.md`. Follow every BUILD / CONVERGE / INTERACTIONS / GATE / VISUAL-VERIFY,
deployment, testing, and evidence rule in `PROMPT.md`; this file overrides only its one-page/session stopping rules.

## Required sequence
1. Verify planning before touching theme code: `node scripts/migration-state.mjs planned migrations`.
2. Repeatedly identify the first unfinished queued page: `node scripts/migration-state.mjs active migrations` → write
   that path to `.ralph/ACTIVE_PAGE`, then carry that page through its complete state machine. Queue order; never edit
   `_queue.tsv` / `_scope.json`.
3. Build the whole page, deploy to the unpublished `${SHOPIFY_THEME_ID}`, converge generated deltas to zero, verify
   interactions + tests, write `reports/final.md`, perform the independent VISUAL-VERIFY pass — with source + replica
   open in the chrome-devtools MCP exactly as `PROMPT.md` requires.
4. Commit + push at safe phase/page checkpoints, but **continue in this same invocation** — a completed page, commit,
   deployment, or summary is not permission to end.
5. When a page is machine-complete, select the next active page and repeat. Preserve shared/global work; reuse sections.
6. Finish only when `node scripts/migration-state.mjs remaining migrations` prints `0`; then remove `.ralph/ACTIVE_PAGE`,
   run the relevant test suite, report the completed queue.

Non-interactive: never ask the user. Use the CLI, the Admin API, the browser, and the docs before escalating; only when no
progress is possible, write one precise reason + unblock steps to `.ralph/BLOCKED` and stop. Stay context-efficient:
provider auto-compaction makes the run fail.
