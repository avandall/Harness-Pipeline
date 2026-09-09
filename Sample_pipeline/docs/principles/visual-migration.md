# Visual-First Migration (READ FIRST — the operating model)

> **Authority: principles. This wins over anything older.** Harness note: an *operating model* doc states the unit of
> work, what counts as truth, and what "done" means. Everything else (prompts, gates, runners) implements it.

## The model in one line
**Migrate one page at a time, in one sustained session, against the source — build the whole page first, then drive
visible deltas to zero. The source (a live site, a design export, or any static HTML) is the source of truth; "done"
is visual parity at desktop AND mobile, not a ticked checklist.**

## Three rules that make it work
1. **Truth = the source.** You measure the original and match it. A green test proves *non-regression*, never fidelity.
2. **Held whole.** A page is built and converged in **one context** with the source open, so whole-page bugs (global
   container width, base font size, an inherited button style) surface the moment a second section inherits them.
   Never build one section per fresh context during initial migration.
3. **Done = zero deltas + the final gate + an eye-level pass**, at desktop and mobile.

## The unit: one page = one sustained session
The unit is a **route/page**, not a section. Sections are still modular, brand-neutral Liquid sections — but the agent
holds the whole page target while building them. A multi-page site is migrated page after page, each its own session.
The default loop (`scripts/ralph.sh`) starts a fresh invocation per page; `--one-go` keeps one invocation and moves
through the queue in order — same contract, different context lifetime.

## The phases (per page) — a state machine read from disk
| # | Phase | What happens | Output |
|---|---|---|---|
| 0 | **CAPTURE** | inspect the source with the browser MCP; author `contract.json`; run `capture-source` (targets), `capture-assets` (exact bytes), `capture-dynamics` (popups/hovers/motion); classify `interactions.md` | `migrations/<page>/` evidence pack |
| 1 | **BUILD** | foundation (settings/schemes/fonts/container width) → assets → every section in source order → JSON template; deploy the whole page to the unpublished theme | a complete first-pass page |
| 2 | **CONVERGE** | `contract-diff.mjs` regenerates `visual-deltas.md`; measure both sides; fix to the source value; redeploy; re-diff — until zero open | every section matches by measure + eye |
| 3 | **INTERACTIONS** | reproduce + test the REBUILD rows (hover, sticky, video, carousels, forms…) | passing behaviour tests |
| 4 | **GATE** | the machine verdict (below) → `reports/final.md` | — |
| 5 | **VISUAL-VERIFY** | a dedicated eye-level pass: header, every band, footer, desktop + mobile → `reports/visual-verify.md` | page done → next page |

## The comparison hierarchy (right tool per level — never one pixel score for everything)
| Level | Method | Catches | Trust |
|---|---|---|---|
| element → element | `getComputedStyle` + bounding box on matched nodes (**measurement, not pixels**) | font 14↔16, aspect 2/3↔1/1, width 1200↔1760, color, spacing | **deterministic — the verdict** |
| section → section | screenshot the element **by its contract selector**, then pixel-diff | a section drifted/broke | strong (small AA noise) |
| full page → full page | side-by-side image, human/agent **review** | order, rhythm, spacing (gestalt) | **eyes only — never a %** |
| viewport → viewport | scroll fold by fold and look | "this screen feels off" | weak as a gate |
A single uniform pixel score is what failed before (irreducible cross-engine noise got rationalized into a pass).
**Computed-style equality is un-gameable and noise-free — make it the spine. Pixel diff is a smoke detector.**

## Capture mechanic
One full-page screenshot per viewport (desktop 1440, tablet 768, mobile 390); element/section shots **by selector**
(`locator.screenshot()`), never crops of a stitched page (drift-proof).

## Final gate — a page is done only when ALL hold (desktop + mobile)
1. `contract-diff.mjs`: all sections within tolerance, none missing; `gate.json` `visualPass: true` with a contract hash that matches.
2. Browser-MCP side-by-side wrap-up at all four levels (source + replica open together).
3. Interactions verified: `validate-dynamics.mjs` passes; every REBUILD row has a passing Playwright test.
4. Assets verified: `validate-assets.mjs --public` passes (exact bytes under `theme/assets/`, no source-CDN hotlinks).
5. Records + routes intact: pages/menus/redirects created, every route resolves, no stale test contradictions.
Then `LEARNINGS.md`, commit, next page.

## What changed vs the older checklist model (kept for teaching)
| | Old (superseded) | Now |
|---|---|---|
| Unit | one section per fresh context | one **page** per sustained session |
| Truth | the spec checklist | the **source** (contract + evidence pack) |
| Done | zero unchecked boxes | **zero deltas + gate + eye pass** |
| Section gate | heading-anchored crop | **selector-anchored** element shot |
| Screenshots | "judge from the score" | **mandatory — looking is the point** |
