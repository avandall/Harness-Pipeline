# Shopify Theme Migration — Provider-Neutral Agent Guide (the ROUTER)

> **What this file is (harness engineering, step 1):** the one file every agent reads first. It is a *router*, not a
> manual — it states the job in two lines, the precedence rules, what you may assume about your access, a short
> **read-before** list, and a **read-on-demand** table that points at the right doc for the task at hand. Keep it
> short; put knowledge in `docs/`. Provider entry points (`CLAUDE.md`, `AGENTS.md`) only point here.

You migrate websites onto a **Shopify Online Store 2.0 theme** (Liquid; base theme: Dawn under `theme/`) — page by
page, 1:1 with the source. Output is always **reusable sections** (schema + presets + color scheme + responsive
settings + locale strings), **brand-neutral**, **pixel-close on desktop AND mobile**. The theme under `theme/` is the
product; everything else in this repo is the harness that makes an agent build it reliably.

**Precedence on conflict:** ops/CLI/deploy/records/validation → `docs/ops/*` wins. Liquid craft (syntax, sections,
schema, color, responsive) → `docs/craft/*` wins. Operating model → `docs/principles/*` wins over everything older.

**Before anything unattended (e.g. publishing):** check `docs/validation-status.md` — ⚠️ items are doc-derived, not
yet executed against a real store.

**This project's concrete values** (store, target theme id, credentials): `.env` (template: `.env.example`). Theme ids:
`shopify theme list --store $SHOPIFY_STORE`. The target theme is **always an unpublished theme**.

**Your access — you are NOT locked out (verify before escalating):** the **Shopify CLI** session (`shopify auth login`;
theme list/pull/push/publish), the **Admin API** (GraphQL first, REST where documented) with a token minted from the
app credentials (`node scripts/shopify-admin-token.mjs`), and — for the few admin-only settings with no API — a
**logged-in admin Chrome on `${CDP_PORT}`** (`node scripts/ensure-admin-cdp.mjs`). Never declare "no API exists" or
escalate without first checking the official docs (`docs/ops/shopify-references.md`) and trying the token path.
Inventory + what is verified: `docs/ops/environment-setup.md` → *Access & capabilities*.

**Learning/debugging Shopify?** Official docs FIRST (`docs/ops/shopify-references.md`) — never brute-force or guess
endpoints, but never *assume* an endpoint is missing either. Record the resolving link in `LEARNINGS.md`.

## Workflow — visual-first migration (two phases, same for a live URL, a design export, or any static HTML)
The unit is **one page in one sustained session with the source open**: build the whole page, then drive visible
deltas to zero. **Truth = the source; done = visual parity, not a ticked box.** Full model: `docs/principles/visual-migration.md`.
1. **Plan / CAPTURE** — `scripts/plan.sh <source-url>` (live site), `scripts/plan.sh --from-reference <dir>` (a local
   HTML/CSS/JS export — a design-tool export or any static site), `scripts/plan.sh --page <url>` (one page). Seals
   `migrations/_queue.tsv`, then one fresh CAPTURE worker per route until every evidence pack validates. No theme code.
   (`prompts/PLAN.md`; `--one-go` uses `prompts/PLAN_ALL.md`.)
2. **Migrate** — `scripts/ralph.sh` (loop: fresh context per page, resumable) or `scripts/ralph.sh --one-go`
   (`prompts/IMPLEMENT_ALL.md`). Each page: **BUILD → CONVERGE → INTERACTIONS → GATE → VISUAL-VERIFY**. Success = every
   queued page machine gate-verified. (`prompts/PROMPT.md`.) One command for both: `scripts/migrate.sh <source>`.
3. **Follow-up** — after a complete migration, operator change requests go through the same contract:
   `printf 'request' | scripts/follow-up.sh` (`prompts/FOLLOW_UP.md`).

Provider selection is outside the work contract: `AGENT_PROVIDER=claude|codex|custom` or `--provider`
(`scripts/agent-runner.sh`). Never change migration quality based on the selected CLI.

Append durable discoveries to `LEARNINGS.md` (its header says when and where to route them).

## Read BEFORE any work (principles — short, read them all)
- `docs/principles/visual-migration.md` — the operating model: page-unit, source-as-truth, 4-level comparison, done = deltas zero + gate
- `docs/principles/agent-workflow.md` — phases, search-first, subagents = research only, deploy-before-validate
- `docs/principles/implementation-principles.md` — reusability, brand-neutral naming, theme vs apps
- `docs/principles/migration-decisions.md` — the locked v1 decisions
- `docs/principles/loop-and-exit.md` — how the loop runs and when it stops (exit codes)

## Read ON-DEMAND (open the file when the task matches — do NOT preload)
| Task | Read |
|---|---|
| Write/edit a section, block, or template | `docs/craft/liquid-syntax.md`, `sections-blocks-templates.md`, `settings-schema-and-locales.md`, `color-schemes.md`, `responsive-settings.md` |
| Fonts / assets | `docs/craft/assets-and-fonts.md` |
| **Start a migration / fresh run (base theme, baseline, reset)** | `docs/runbooks/start-from-base-theme.md` (`scripts/theme-baseline.sh`) |
| Understand the theme | `docs/ops/theme-architecture.md` |
| CLI / pull / push / preview | `docs/ops/cli-reference.md` |
| Deploy / publish / validate | `docs/ops/deploy-publish-validate.md` |
| Recreate routes/content (MANDATORY for 1:1) | `docs/ops/content-and-routes.md` |
| Create a page (/pages/x) | `docs/ops/create-custom-pages.md` (`scripts/create-page.mjs`) |
| Create a blog / article (/blogs/x) | `docs/ops/create-blogs.md` (`scripts/create-blog.mjs`) |
| Menus + redirects | `docs/ops/content-and-routes.md` (`scripts/create-menu.mjs`, `scripts/create-redirects.mjs`) |
| Store/theme setup, access, tokens | `docs/ops/environment-setup.md`, `docs/ops/store-and-theme-config.md` |
| Plan / CAPTURE a page | `prompts/PLAN.md`, `docs/contract-and-evidence.md` |
| Migrate a page (the state machine) | `docs/principles/visual-migration.md`, `prompts/PROMPT.md` |
| Build one section | `docs/runbooks/build-a-section.md` |
| Visual QA (element/section/full page, desktop+mobile) | `docs/runbooks/visual-qa.md`, `docs/contract-and-evidence.md` |
| Assets (exact bytes first) | `docs/runbooks/scrape-assets.md` |
| Write / run tests | `docs/runbooks/testing.md` |
| Audit a theme | `docs/runbooks/audit-a-theme.md` |
| Learn / debug Shopify (docs-first) | `docs/ops/shopify-references.md` |
| Debug | `docs/troubleshooting.md`, `docs/validation-status.md` |

Claude Code auto-loads `.claude/rules/*` for matching paths (editing `theme/sections/**`, `theme/blocks/**`,
`theme/templates/**`, `theme/config/**`, `theme/locales/**`). Other providers must follow the authoritative
`docs/craft/*` + `docs/principles/*` those rule files cite.

## Non-negotiables
1. `@shopify/cli` (binary `shopify`), theme commands run with `--path theme`.
2. Liquid, Online Store 2.0: sections are `theme/sections/*.liquid` with `{% schema %}`; pages are JSON templates
   (`theme/templates/*.json`) composed of sections; global settings in `theme/config/settings_schema.json`.
3. kebab-case files; snake_case setting ids; locale keys via `t:` in `theme/locales/*.schema.json`.
4. Image settings are `image_picker`; render with `image_url` (+ `image_tag`); bundled files via `asset_url`.
5. Every merchant-addable section: a `color_scheme` setting + responsive spacing/layout settings + `presets`.
6. Brand-neutral names everywhere; merchant copy only in editable settings/content.
7. A template ≠ a page route. Create page records through the Admin API (`pageCreate`, `templateSuffix`), menus via
   `menuCreate`, redirects via `urlRedirectCreate` — docs first, CDP only as a documented last resort.
8. Route parity is not route aliasing. Never silently replace a source route; create, map, redirect, or record an
   explicit exception, and rerun the full gate matrix after any contract route change.
9. Deploy to the **unpublished** `${SHOPIFY_THEME_ID}` only. Publish = an explicit, separate step
   (`shopify theme publish` / `RALPH_SYNC_LIVE=1`), never part of a migration iteration.
