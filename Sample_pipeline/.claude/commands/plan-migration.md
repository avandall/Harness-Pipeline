---
description: Phase 0 worker — CAPTURE one page and author its visual contract + evidence pack. Does not implement.
argument-hint: --page <source-url>  |  --from-reference [dir]
---
Source / reference mode: $ARGUMENTS

Read and follow `prompts/PLAN.md` exactly. This slash command is a **single-page CAPTURE worker**. Given
`--page <source-url>` (or one queued `__REF__` entry) it authors exactly that page's evidence pack under
`migrations/<page>/` (contract.json → capture-source → capture-assets + validate → capture-dynamics → interactions.md
+ validate) and stops. It writes no theme code and never edits `migrations/_queue.tsv` / `_scope.json`.
Given a bare site URL or a whole reference build, tell the operator to run `scripts/plan.sh <source-url>` or
`scripts/plan.sh --from-reference [dir]` — those outer runners seal the queue and invoke one fresh worker per page.

> Harness note: slash commands are thin pointers to the prompts in `prompts/`. The prompt is the contract; the
> command is just a convenient way to invoke it interactively.
