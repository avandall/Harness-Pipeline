---
description: Migrate one page via the visual-first state machine (BUILD whole page → CONVERGE deltas→0 → INTERACTIONS → GATE → VISUAL-VERIFY), deploy to the unpublished theme, validate vs the source, commit + push.
---
Read and follow `prompts/PROMPT.md` exactly. Work the active page under `migrations/<page>/`: detect its phase from
disk, then carry it forward in ONE sustained session with the source open — build the whole page in source order,
deploy to `${SHOPIFY_THEME_ID}` (unpublished), drive `visual-deltas.md` to zero with
`scripts/visual-diff/contract-diff.mjs` (measuring the source, never guessing, and looking at the review images),
verify interactions, run the final gate, then the eye-level VISUAL-VERIFY pass. Do NOT fragment into
one-section-per-context. Done = visual parity vs the source (not a ticked box). Commit at phase boundaries and push.
