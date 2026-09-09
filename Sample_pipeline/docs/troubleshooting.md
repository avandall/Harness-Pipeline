# 10 — Troubleshooting (gotcha catalog)
> Harness note: symptom → fix, one line each. When a new gotcha costs you time, add it here (and `LEARNINGS.md`).

- **`/pages/<handle>` 404s** → the page *record* is missing (a template alone is not a route) → `create-page.mjs`.
- **Page renders with the default look** → `templateSuffix` not attached, or `templates/page.<suffix>.json` not pushed.
- **Storefront shows "Opening soon" / password page** → set `STOREFRONT_PASSWORD`; the harness submits it on `/password`.
- **Preview shows the live theme** → you hit the primary domain without the preview cookie; open `?preview_theme_id=<id>` on the myshopify domain first.
- **`shopify theme push` refuses the live theme** → correct: never push live; target an unpublished id (`--allow-live` is forbidden here).
- **Admin API `ACCESS_DENIED` / 403** → missing **scope** on the app — not a missing endpoint; add the scope and re-mint the token.
- **Admin API 401 after a day** → client-credentials tokens expire in 24h → `scripts/shopify-admin-token.mjs` re-mints (delete `.ralph/shopify-token.json` to force).
- **Chrome "browser is already running for <profile>"** → a stale Chromium holds the profile → kill it / use the MCP `--isolated` or the harness's own launcher.
- **Gate shows a uniformly red diff** → misregistration (height/Y offset), not colors → fix the section's box first.
- **Gate green but it looks wrong** → the contract misses a band/check → add the section/`checks`, never "accept".
- **Loop exits 3 immediately** → a stale `.ralph/BLOCKED` → read it, fix, `rm .ralph/BLOCKED`.
- **Loop exits 7** → the invocation auto-compacted → re-narrow the task (smaller phase), never ship that work.
- **GitHub integration ignores your theme** → the connected branch must have the theme folders at its ROOT → `scripts/sync-theme-branch.sh`.
