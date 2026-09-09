# PROMPT — Migrate one page (default-loop visual-first worker)

> Reusable across every migration. Invoked via `/implement-next` or the loop (`scripts/ralph.sh`; `--one-go` uses
> `IMPLEMENT_ALL.md`). **Unit = ONE page, ONE sustained session, the source open the whole time.** Build the whole page,
> then drive visible deltas to zero. Truth = the source; done = visual parity, not a ticked box. Model:
> `docs/principles/visual-migration.md`. Do **not** fragment into one-section-per-context.
>
> Harness note: this prompt is a *state machine* — it detects the page's phase from files on disk and advances it. That is
> what makes a crashed or recycled session resume instead of restart.

You are a senior Shopify **Online Store 2.0** theme-migration engineer.

## 1. Load context (every session)
**NON-INTERACTIVE in the loop (`claude -p` / `codex exec`): never interview the user.** Read `migrations/_brief.md` if
present and treat it as authoritative; for anything it omits, default sensibly and **record the assumption**.
Read `AGENT_GUIDE.md`, `docs/principles/visual-migration.md`, `docs/contract-and-evidence.md`, the docs your work
routes to (`docs/craft/*`, `docs/ops/*`, `docs/runbooks/visual-qa.md` + `testing.md`), and `LEARNINGS.md`. Path rules
auto-load for theme files. **The chrome-devtools MCP is your primary eyes + ruler:** keep **both** the source and the
replica preview (`?preview_theme_id=${SHOPIFY_THEME_ID}`) open the whole session; after every change compare side by side
— `evaluate_script` → `getComputedStyle` on both (cheap; catches global cascade bugs: base font, container width,
aspect) plus a targeted screenshot when you need to see it. **The MCP is REQUIRED** — if its browser is locked, kill the
stale Chromium / launch your own instance; never degrade to screenshots-only. If you genuinely cannot get a live browser,
write `.ralph/BLOCKED` and stop.

## 2. Pick the page + detect its phase (the state machine)
Work `migrations/<page>/` from `.ralph/ACTIVE_PAGE` (else the first queued page with open work). Determine the phase
**from disk** and advance it — then keep going in this session toward the gate:
1. **No `contract.json`** → CAPTURE isn't done → run `prompts/PLAN.md` (never build without a contract).
2. **`assets.json` missing/failing** → `capture-assets.mjs` + `validate-assets.mjs` (no build with missing/approximate/hotlinked assets).
3. **`dynamics.json` missing/failing** → `capture-dynamics.mjs`, classify every `mustClassify[]` in `interactions.md`, `validate-dynamics.mjs`.
4. **Contract exists but the page isn't built/deployed** → **BUILD**.
5. **`visual-deltas.md` missing or has open `- [ ]`** → **CONVERGE**.
6. **Deltas zero but `interactions.md` rows unverified** → **INTERACTIONS**.
7. **All done but no `reports/final.md`** → **GATE** → write it.
8. **Gate passed but no `reports/visual-verify.md`** → **VISUAL-VERIFY** → write it. The page is done **only after this**.

## 3. Phase playbooks
### BUILD — the whole page, in source order
- **Reuse-first:** consult `migrations/_sections.md` + `theme/sections/`; reuse an existing type with a new preset/instance;
  author a new brand-neutral section only when no type fits (schema + presets + `color_scheme` + responsive settings +
  locales). Shared globals (header/footer/schemes/fonts/container width) are built once.
- **Foundation first:** `theme/config/settings_schema.json` + `settings_data.json` — color schemes, fonts, **the global
  container width set to the source's measured value** (the #1 whole-page miss). Header/footer groups. Push.
- **Assets first:** `validate-assets.mjs` → copy every captured `localPath` to `theme/assets/<file>` **unchanged** →
  `validate-assets.mjs --public` → reference with `{{ '<file>' | asset_url }}`. No hotlinks, no lookalikes, no renames.
- **Dynamic scope first:** read `dynamics.json` + `interactions.md`; don't code while a popup/widget/hover/form/video is unclassified.
- Build each contract section with the stable root `<section data-section-key="<key>" data-section-type="<type>">`.
  Mirror compound layout (header/footer grouping, logo asset/aspect, icons, nested bands) before polish.
- Wire the JSON template (`theme/templates/index.json` / `page.<suffix>.json`) in source order. **Deploy the whole page**
  (`shopify theme push --path theme --theme ${SHOPIFY_THEME_ID} --store ${SHOPIFY_STORE}`), confirm it renders top to
  bottom, commit ("BUILD first-pass: <page>").

### CONVERGE — drive visible deltas to zero (the core loop)
- Deploy, then gate every viewport: `node scripts/visual-diff/contract-diff.mjs migrations/<page>/contract.json
  --viewport desktop` then `mobile` (+ `tablet` if listed; `--keep-overlays` once if an overlay section). It regenerates
  `visual-deltas.md` (open `- [ ]` = real mismatches) + `gate.json`.
- **Work each delta — measure, never guess:** the report / `inspect.mjs` / the MCP `getComputedStyle` on both sides →
  fix the section to the source's value → redeploy → re-run. Watch for **cross-cutting** causes (one container/base-font
  fix clears many sections — you see that because you hold the whole page).
- **Looking is required:** after each fix compare the section side by side in the MCP and open the one `*.review.png`
  (don't load full-page PNGs into context). Loop until zero open at every viewport. Commit when a viewport goes green.
- Check the blind spots before accepting green: transparent sections' backdrop, nested bands, hover styles, open panels,
  header/footer geometry. If the report is green but the MCP shows a mismatch, the contract is incomplete — fix code +
  add the check.
- Per section, write its Playwright **regression** test (`tests/<section>.test.js`) — it guards, it doesn't prove fidelity.

### INTERACTIONS — reproduce + verify what the static gate can't see
- For each **REBUILD** row: rebuild natively, verify on both pages with the MCP (hover, dropdowns, sticky header, video
  autoplay/loop, carousels/accordions, forms), back it with a passing `tests/*.test.js`. **DEFER-to-app** rows leave a
  documented mount hook (app block/snippet); **DROP** rows are noted in `reports/final.md`.
- **Tick only when 100% done** (reproduced + test passes + verified live on both). **Never hand-tick `visual-deltas.md`.**
  Re-run `validate-dynamics.mjs` after editing `interactions.md`.

### GATE — final acceptance (ALL must hold, desktop + mobile)
1. `contract-diff.mjs` all sections within tolerance, none missing; `visual-deltas.md` zero open; `gate.json` `visualPass:true` every viewport.
2. **MCP side-by-side wrap-up at all four levels** (element / section / viewport / full page) — any mismatch → CONVERGE.
3. Every kept interaction has a passing test; the suite is green (`npx playwright test`).
4. `validate-assets.mjs --public` passes; no rendered asset 404s; no source-CDN hotlinks unless documented as a defer.
5. `validate-dynamics.mjs` passes; every rebuilt behaviour tested, every deferred app has a mount note, every drop listed.
6. Records/routes intact: pages (`pageCreate` + `templateSuffix`), blogs, menus (`menuCreate`), redirects
   (`urlRedirectCreate`) created via the Admin API first (`scripts/create-*.mjs`); every route resolves (no 404); no
   stale test/contract contradiction; no silent route aliasing. Any contract route change → rerun the full gate matrix.
- Write `migrations/<page>/reports/final.md` (review images, accepted cross-engine deltas + why, interaction result,
  records created, assumptions). Then VISUAL-VERIFY.

### VISUAL-VERIFY — final eye-level acceptance (its OWN pass, one page)
Open SOURCE and REPLICA in the MCP at 1440 then 390 (clear gates/popups on both). Walk the **entire page — every band,
source-first**: HEADER (logo + size, every nav link label/casing/destination, icons, CTA, mobile menu, sticky) · EVERY
SECTION (background/pattern, every image/icon/video, all text + casing, layout, spacing, buttons/links) · FOOTER (every
column, link, social icon, legal text). Scroll fold by fold on both; trigger every interaction. **Pass bar = nothing
missing or wrong** (cross-engine antialiasing is fine; a missing element, wrong text, broken interaction, wrong layout
is not — fix, redeploy, re-check). Write `reports/visual-verify.md` (header / each section / footer: checked, ✓/✗, gaps +
fixes, verdict per viewport). The page is done only when it covers header + every section + footer with zero open gaps.
Commit + push.

## 4. You have full access — exhaust it, then escalate
Migrate mode never interviews. Use the CLI session, the Admin API token (`scripts/shopify-admin-token.mjs`), and —
only after the docs confirm no API covers it — the logged-in admin Chrome (`scripts/ensure-admin-cdp.mjs`: 0 ready / 10
one-time human login / 2 error). Docs-first for any unknown (`docs/ops/shopify-references.md`); a 403 is a scope issue,
not a missing endpoint. Only when no other progress is possible: one-line reason + unblock steps to **`.ralph/BLOCKED`**, stop.

## 5. Context hygiene (sustained ≠ wasteful)
Hold the whole page but stay lean so the session never auto-compacts (a hard fail): judge QA from review images + section
reports; use the harness, never hand-roll capture; read big files in parts; deploy to the unpublished `${SHOPIFY_THEME_ID}`
only (never publish per task); no throwaway scripts in the repo.

## 6. Close — at every phase boundary, sync BOTH targets + tick what's done
**Shopify:** `shopify theme push` to the unpublished target (the live theme / connected branch is go-live only,
`RALPH_SYNC_LIVE=1`). **GitHub:** commit with a detailed message + push the branch. Tick only fully verified REBUILD rows;
never hand-tick `visual-deltas.md`. Append durable discoveries to `LEARNINGS.md` (fix `docs/` / `validation-status.md`
for durable corrections). When the page's VISUAL-VERIFY is written, it's done — the next page is the next unit.
