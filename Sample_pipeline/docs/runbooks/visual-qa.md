# Runbook — Visual QA (prove the replica matches the source)
> Authority for *how* to compare. Model: `principles/visual-migration.md`. The job is **identical to the source**, and you
> confirm that by **looking and measuring** — never by trusting a single pixel score.

**Golden rule:** computed-style equality + a faithful full-page review is the acceptance bar; pixel diff is a backstop.
**Capture mechanic:** one full-page shot per viewport (1440/768/390) + element shots by contract selector.
**The harness (`scripts/visual-diff/`):** `capture-source` (targets + reference) · `capture-assets` / `validate-assets`
· `capture-dynamics` / `validate-dynamics` · **`contract-diff` (THE GATE)** → `visual-deltas.md` + `gate.json` + per-section
`*.merged.png`/`*.diff.png` + a downscaled `*.review.png` · `inspect` (diagnosis: "h1 28px should be 36px") ·
`capture`/`compare` (generic side-by-side) · `serve-reference` (local `__REF__` sources) · `launch` (tagged Chromium).
**Protocol per page:** deploy → gate desktop → gate mobile → open the `*.review.png` (never raw full-page PNGs into context)
→ measure both sides with the browser MCP (`getComputedStyle`) for each delta → fix → redeploy → repeat → zero.
**What the gate does NOT cover:** motion/behaviour (it freezes animation and pauses video) → `dynamics.json` →
`interactions.md` → INTERACTIONS phase with Playwright + MCP cross-check.
**Tolerances are triage, not acceptance:** structural sections flag `> 0.06`, content `> 0.08` — investigate, never raise
the number; a documented per-section `pixelCeiling` exists only for irreducible cross-engine residue.
**Capture gotchas:** hide DEFER-to-app widgets in both passes (scoped selectors) · the Shopify preview bar iframe is
hidden on the replica · password gate submitted on `/password` · the MCP's `resize_page` clamps small widths — use the
harness (Playwright viewport) for mobile captures.
