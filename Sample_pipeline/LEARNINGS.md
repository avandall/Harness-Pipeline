# LEARNINGS

> Per-project log for durable, non-obvious discoveries a future loop can't re-derive from the code/git.
> **Keep this lean.** When a discovery generalizes across projects, route it into the matching `docs/` page (and
> `docs/validation-status.md` if it changes a verified capability) — that's where the reusable platform knowledge
> lives and gets surfaced on demand by the router. This file starts empty in a fresh clone; add dated entries as
> *this* migration surfaces them, then promote the durable ones.

**Rubric — log when:** a platform behavior contradicted the docs · a tool needed a non-obvious flag/workaround · a
gate false-failed for a reason future runs must know · an assumption was made because the brief was silent.
**Format:** `- YYYY-MM-DD — <what> — <why it matters> — <doc link if platform fact> — routed to: <docs/… or "project-only">`

<!--
Routing examples (how earlier projects promoted entries):
  · a CLI flag that is a no-op                    → docs/ops/cli-reference.md + docs/troubleshooting.md
  · a route gotcha (404 template≠page)            → docs/ops/content-and-routes.md
  · a capture gotcha (preview bar, password gate) → docs/runbooks/visual-qa.md
  · a verified Admin API endpoint                 → docs/validation-status.md (✅ row) + the matching docs/ops page
-->
