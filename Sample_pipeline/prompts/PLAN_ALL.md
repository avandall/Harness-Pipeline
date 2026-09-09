# PLAN_ALL — Plan the complete migration in one agent invocation (one-go)

> The experimental **one-go Plan** worker. The outer runner (`scripts/plan.sh --one-go`) invokes you exactly once. You must
> discover (when needed), CAPTURE, and validate the **complete** route queue before ending. Do not spawn or delegate to
> another agent. Harness note: one-go removes the shell's per-page loop, not the harness — queue, packs, validators, and
> resume are identical; the trade is fewer invocations for a higher context-compaction risk (which fails the run).

Read `AGENT_GUIDE.md`, `prompts/PLAN.md`, `docs/principles/visual-migration.md`, `docs/contract-and-evidence.md`. Follow
every CAPTURE/evidence rule in `PLAN.md`; this file overrides only its single-page stopping rules.

## Required sequence
1. Read the task, `migrations/_brief.md` (if present), and any existing `migrations/_queue.tsv` / `_scope.json`.
2. Live-site run without a queue: discover the complete distinct route inventory (sitemap + rendered header/footer
   navigation via the browser MCP) and write `_queue.tsv` with `home` first. Once written, the queue is **immutable**.
   Reference / single-page runs: the runner creates the queue before invoking you.
3. Process **every queue entry in order**: the full CAPTURE playbook per page (contract + targets, exact assets,
   dynamics, classified interactions, summary, `_sections.md` updates), validated with
   `node scripts/migration-state.mjs pack migrations/<page> '<queued-source>'`.
4. After a page validates, continue immediately. A completed page, checkpoint, commit, or summary is **not permission to end**.
5. Write no theme code. Never edit `_queue.tsv` / `_scope.json` once they exist.
6. Finish only when `node scripts/migration-state.mjs planned migrations` passes.

Non-interactive: never ask the user. Resolve omissions from the source, the official docs, and `_brief.md`; record
assumptions. If live browser access is genuinely unavailable and no CAPTURE progress is possible, write the exact unblock
step to `.ralph/BLOCKED` and stop.
