# 01 — Environment Setup
> **Authority: ops.** Harness note: ops docs hold the platform facts an agent must not guess — install, auth, what it
> can do, where values live. Each fact carries a trust mark (✅ executed here · ⚠️ doc-derived) — see `validation-status.md`.

## Host baseline
Node 22 (`.nvmrc`), bun or npm, Playwright Chromium (`bunx playwright install chromium`), Shopify CLI
(`npm i -g @shopify/cli` → binary `shopify`, ✅ 4.x verified), Google Chrome (for the MCP + CDP fallback), git + `gh`.

## Authenticate the CLI
`shopify auth login` (browser or device-code flow — ✅ verified headless: it prints a code + URL you approve once). Then
`shopify theme list --store $SHOPIFY_STORE` (✅). Theme commands accept `--store` and `--path theme`; a **Theme Access**
password or an Admin token can replace the login via `--password` / `SHOPIFY_CLI_THEME_TOKEN` (⚠️ doc-derived).

## Access & capabilities (what you can actually do — don't assume you're locked out)
| Channel | Auth | Use for | Status |
|---|---|---|---|
| **Shopify CLI** | `shopify auth login` session | theme list / pull / push (to an **unpublished** theme) / publish / dev preview | ✅ list, push `--unpublished`, pull round-trip verified on the test store |
| **Admin API (GraphQL first; REST where documented)** | `X-Shopify-Access-Token` — minted from the app's client credentials (`node scripts/shopify-admin-token.mjs`, 24 h) or a legacy static token | pages (`pageCreate`), blogs/articles, menus (`menuCreate`), redirects (`urlRedirectCreate`), themes (`themePublish`), products/collections | ⚠️ doc-derived until a token is configured; endpoints verified against shopify.dev |
| **Admin UI via CDP** (logged-in Chrome on `${CDP_PORT}`; `node scripts/ensure-admin-cdp.mjs`, exit 0 ready · 10 needs one human login · 2 error) | the human's admin session cookies | the few admin-only settings with no public API (e.g. homepage title/meta under Online Store → Preferences) | last resort — only after the docs confirm no API covers it |

**Endpoint discovery (docs-first, don't guess):** for any capability you're unsure about, look it up in the Admin
GraphQL reference before concluding "no API exists" (`shopify-references.md`). A `403`/`ACCESS_DENIED` means missing
**scope**, not a missing endpoint — report it as a scope issue.

## Admin API access in 2026 (what changed)
New apps are created in the **Dev Dashboard** (the admin "Develop apps" path no longer creates new ones). They don't show
a permanent token; the harness exchanges `SHOPIFY_CLIENT_ID` + `SHOPIFY_CLIENT_SECRET` for a 24-hour token
(`POST https://{store}/admin/oauth/access_token`, `grant_type=client_credentials`) and caches it under `.ralph/`.
Scopes to grant the app: `write_content`, `write_online_store_pages`, `write_online_store_navigation`, `write_themes`
(+ `read_*`), and `write_products` only if commerce is in scope. A legacy static token (`shpat_…`) still works via `SHOPIFY_ADMIN_TOKEN`.

## Project layout (harness vs product)
```
AGENT_GUIDE.md CLAUDE.md AGENTS.md LEARNINGS.md      # routing + memory
docs/ prompts/ .claude/{rules,commands}               # knowledge, job descriptions, path rules, shortcuts
scripts/ (runners, state, visual-diff/, platform)     # the tools
migrations/ reference/ .ralph/ (ignored)              # evidence packs, local sources, runtime state
tests/ demo/                                          # back-pressure + the control panel
theme/                                                # THE PRODUCT (Dawn base + migrated sections)
.env.example .gitignore package.json                  # config as policy
```

## Environment variables
Copy `.env.example` → `.env` and fill it; scripts read it via `scripts/env.mjs` (process env wins over the file).
Docs only ever mention placeholder names.

## Git / GitHub
`main` = full project (theme + harness). The Shopify GitHub integration connects only branches whose **root** is a
theme, so go-live uses `scripts/sync-theme-branch.sh` to mirror `theme/` onto the theme-only `shopify-theme` branch.
Dev builds never touch it — they push to the unpublished theme with the CLI.
