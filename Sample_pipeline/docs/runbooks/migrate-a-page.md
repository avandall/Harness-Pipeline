# Runbook: Migrate a page (the per-page lifecycle, end to end)
> Harness note: a *runbook* is a task recipe; the operating model (`principles/visual-migration.md`) and the prompt
> (`prompts/PROMPT.md`) are the authorities — this is the short walk-through for a human or an agent.

0. **Intake** — the source (URL / `__REF__` entry) is in `migrations/_queue.tsv`; `migrations/_brief.md` (if present) is authoritative.
1. **CAPTURE** (`/plan-migration --page <url>` or the outer `scripts/plan.sh`) — contract → targets → assets → dynamics → interactions; validate the pack (`node scripts/migration-state.mjs pack migrations/<page> '<source>'`).
2. **BUILD** — foundation (schemes/fonts/container width in `theme/config/*`), exact assets into `theme/assets/`, sections in source order (reuse-first), JSON template, `shopify theme push` to the unpublished theme; confirm it renders top-to-bottom; commit.
3. **CONVERGE** — `node scripts/visual-diff/contract-diff.mjs migrations/<page>/contract.json --viewport desktop` then `mobile` (and `--keep-overlays` if needed) → fix each open `- [ ]` by measuring both sides → redeploy → re-run until zero.
4. **INTERACTIONS** — rebuild + test each `REBUILD` row; tick only when verified live on both pages.
5. **GATE** — all conditions (principles) → `reports/final.md`.
6. **VISUAL-VERIFY** — dedicated eye pass, header + every band + footer, desktop + mobile → `reports/visual-verify.md`.
7. **Records + routes** — page/blog/menu/redirect records exist; every route resolves (content-and-routes).
8. **Close** — `LEARNINGS.md`, commit, push. Publish only on the explicit go-live step.
