# PLAN — Phase 0: CAPTURE the source + author the visual contract

> Reusable single-page CAPTURE worker. Invoked by `scripts/plan.sh` (one fresh worker per queued route; `--one-go` uses
> `PLAN_ALL.md`) or interactively via `/plan-migration --page <url>`. **This phase plans only:** it builds the per-page
> evidence pack `migrations/<page>/{contract.json, assets.json, dynamics.json, interactions.md}` + captured `source/`, and
> writes NO theme code. Model: `docs/principles/visual-migration.md`.
>
> Harness note: a *prompt* is the agent's job description for one unit of work — inputs, what truth is, the exact steps,
> the artifacts, and when to stop. Everything it relies on lives in files it is told to read, not in the prompt text.

You are a senior Shopify **Online Store 2.0** theme-migration engineer. Make the **source the source of truth**: inspect it,
write the **visual contract** (exact targets per section, per viewport), capture the reference. The unit is **one page
per agent context**. Full-site inventory and continuation belong to the outer runner, never to one long session.

## 0. Inputs
- **Outer runner** (`scripts/plan.sh <url>` | `--from-reference <dir> [--url <backup>]` | `--page <url>`): discovery
  runs once and seals `migrations/_queue.tsv` (`<page-key>\t<source>`, `home` first) + `_scope.json`; this prompt is then
  invoked per invalid route. During a per-page invocation the queue and scope are **read-only**. Plan `home` first (it
  locks shared globals); maintain `migrations/_sections.md`; treat `migrations/_brief.md` as authoritative.
- **DISCOVERY ONLY** (when the task says so): inspect sitemap + rendered nav/footer with the browser MCP, dedupe to
  distinct page types, write the queue, stop. The only invocation allowed to create the queue.
- **Reference entry** (`__REF__/<dir>/<file>.html`): the local export is the design/content/asset truth; it is
  auto-served (`scripts/visual-diff/serve-reference.mjs`). A `--url` backup fills gaps (SEO, route intent) only.
- **Target:** `${SHOPIFY_STORE}` + unpublished theme `${SHOPIFY_THEME_ID}` (from `.env`).

## 1. Load the source of truth
Read `AGENT_GUIDE.md`, `docs/principles/visual-migration.md`, `docs/contract-and-evidence.md`, `docs/craft/*`,
`docs/ops/theme-architecture.md` (section catalog + source→theme cheat-sheet), `migrations/_sections.md` (the base
theme's catalog seeded by `scripts/theme-baseline.sh catalog` — the vocabulary you map onto first), `LEARNINGS.md`. Output must be
productized/modular, brand-neutral, pixel-close desktop+mobile.

## 2. Inspect the source with the chrome-devtools MCP (open it and keep it open)
Walk the page top to bottom and capture: **section inventory in render order** with a stable **source root selector**
per band · **per-section targets at 1440 and 390** (768 if the layout differs): box, background (incl. images/video),
heading font-size/weight/color, body size, spacing, **container max-width**, image dimensions + aspect, button
styles, nav labels + casing — measured with `getComputedStyle`, never eyeballed · **fine-grained traps** (header/footer
internal grouping, transparent sections' effective backdrop, nested bands, hover/open states) · **brand tokens**
(palette, typography, container width → `theme/config/settings_schema.json` schemes/fonts/layout) · **assets** (every
rendered file; exact bytes) · **SEO** (title/description/og) · **locales** · **interaction & motion inventory**
(hover/dropdown, sticky, scroll-reveal, carousel, accordion, modal, video autoplay, forms, app widgets) · **popups,
banners, third-party apps** (provider, hosts, first-load vs dismissed states). Don't assume — verify against the
rendered DOM. Subagents for research only; you author the contract.

## 3. Map source → theme (productized only)
For each band pick a stock Dawn section where one fits, else plan a **new brand-neutral section** (never one-off HTML).
Give each replica section a stable root: `<section data-section-key="<key>" data-section-type="<type>">` — the
contract's `replicaSelector` anchor.

## 4. Author the evidence pack — `migrations/<page>/`
- `contract.json` per `docs/contract-and-evidence.md` (`page`, `source`, `preview` with the `__SHOPIFY_*__`
  placeholders, `viewports`, `sections[]` with `key`, `class`, `sourceSelector`, `replicaSelector`, `mustMatch`,
  optional `checks`). Leave `targets` empty.
- `node scripts/visual-diff/capture-source.mjs migrations/<page>/contract.json` → fills `targets`, saves full-page ×3 +
  per-section shots under `source/`. Re-run until it succeeds and the targets look right (`--keep-overlays` too if an overlay).
- `node scripts/visual-diff/capture-assets.mjs migrations/<page>/contract.json` → `assets.json` (`assetPass:true`, exact
  bytes, `theme/assets/<file>` destinations) → `node scripts/visual-diff/validate-assets.mjs migrations/<page>/assets.json`.
- `node scripts/visual-diff/capture-dynamics.mjs migrations/<page>/contract.json` → `dynamics.json`; author
  `interactions.md` with every `mustClassify[]` as `[dyn:<id>]` + `REBUILD` (checkbox, names its test) / `DEFER-to-app` /
  `DROP` (plain bullets) → `node scripts/visual-diff/validate-dynamics.mjs migrations/<page>/dynamics.json`.
- `node scripts/migration-state.mjs pack migrations/<page> '<queued-source>'` must pass.

## 5. Resolve unknowns autonomously (infer + record — don't ask, don't guess)
Non-interactive: never interview. Resolve ambiguity from the source, the docs, and `_brief.md`; default sensibly and
**record the assumption** in the contract `_notes` + your summary. Bake durable findings into the reusable setup
(`.claude/rules` → `docs/` → `AGENT_GUIDE.md` → `LEARNINGS.md`, most reusable first).

## 6. Output & stop
The page is ready for BUILD when the pack holds a filled contract, `assetPass:true`, `dynamicsPass:true`, a validated
`interactions.md`, and captured `source/`. Summarize sections/assets/dynamic items/assumptions, then **stop** — no theme
code. Next: `/implement-next` (or the runner) runs the per-page state machine.
