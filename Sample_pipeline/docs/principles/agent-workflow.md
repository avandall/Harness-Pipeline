# Agent Workflow (READ FIRST)

> **Authority: principles.** Harness note: this doc fixes *how agents work* — phases, what they may delegate, what
> counts as progress. The operating model (`visual-migration.md`) wins on any conflict.

## Two phases (three with follow-up)
1. **Plan / CAPTURE** — `scripts/plan.sh` (+ `prompts/PLAN.md` per page; `PLAN_ALL.md` in one-go) discovers and seals
   the route queue, then inspects the source and authors every queued evidence pack. **No implementation.**
2. **Migrate** — `scripts/ralph.sh` (+ `prompts/PROMPT.md`; `IMPLEMENT_ALL.md` in one-go): one page per sustained
   session, advanced as a state machine: BUILD whole page → CONVERGE → INTERACTIONS → GATE → VISUAL-VERIFY. Deploy to
   the unpublished theme, validate vs the source at desktop + mobile. Resume a page from its evidence pack if a session dies.
3. **Follow-up** — `scripts/follow-up.sh` (+ `prompts/FOLLOW_UP.md`): a post-migration change request runs through the
   same rules, accepted only from a clean, fully gated migration.

## Rules (non-negotiable)
- **One whole PAGE at a time** (never one-section-per-fresh-context). The loop iterates pages + resume.
- **Exit is explicit.** Done = all pages gated; or BLOCKED, a cap, a provider failure, or context compaction — never the
  agent's claim alone. Runner + codes: `loop-and-exit.md`.
- **Don't assume "not implemented".** Search the codebase (parallel subagents for *search*) before building.
- **Subagents = research only.** The main agent alone edits, builds, tests, validates (single writer keeps back-pressure honest).
- **Full implementations, never placeholders** — modular, brand-neutral, color scheme + responsive + presets + locales.
- **Tests are back-pressure.** Per page, runnable `tests/*.test.js` (Playwright) that document what they guard and why.
- **Deploy before validating.** A visual check is meaningful only against the pushed theme + created records.
- **Visual validation is mandatory — and looking is required.** Element by computed style (verdict), section by
  selector shot (regression net), full page by eye (gestalt), desktop + mobile.
- **Close every page:** `reports/final.md` + `visual-verify.md`, append `LEARNINGS.md`, commit with detail, push.
  Go-live mirror (`sync-theme-branch.sh`, `RALPH_SYNC_LIVE=1`) only on an explicit go-live.
- **Keep the source of truth current.** If the guidance itself is wrong, fix it as part of the task.
- **Docs-first for Shopify.** Official docs before guessing (`docs/ops/shopify-references.md`); record the link in `LEARNINGS.md`.

## Source-of-truth chain
`AGENT_GUIDE.md` (router) → `docs/principles/*` (read first) → `docs/craft/*` + `docs/ops/*` (on demand) → the active
`migrations/<page>/` evidence pack (contract, deltas, interactions, gate) → `LEARNINGS.md`. Cite these in reports.
