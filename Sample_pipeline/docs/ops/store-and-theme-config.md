# 03 — Store & Theme Configuration
> **Authority: ops.**

- **Store identity:** `SHOPIFY_STORE` = `<handle>.myshopify.com`; the public `SHOPIFY_PRIMARY_DOMAIN` may differ.
  Dev/test stores are usually **password-protected** → `STOREFRONT_PASSWORD` (the harness submits it on `/password`).
- **Themes:** `shopify theme list` shows roles. Strategy: **one unpublished theme per migration run** as the build
  target (`SHOPIFY_THEME_ID`); the live theme is never a target. Create a fresh one with
  `shopify theme push --path theme --unpublished --theme "<name>"`.
- **Step 0 — baseline:** `scripts/theme-baseline.sh` (`init` / `init --from-store` / `snapshot` / `catalog` / `push-target` / `reset`) — runbook `docs/runbooks/start-from-base-theme.md`.
- **Base theme:** Dawn (MIT) under `theme/` (`shopify theme init theme --clone-url https://github.com/Shopify/dawn.git`;
  the CLI's default `theme init` now clones Shopify's lighter *Skeleton* starter — both work with this harness).
- **Rollback:** themes are versioned by id — keep the previous theme, publish the old id back (`shopify theme publish --theme <old-id>`) or duplicate in admin before go-live.
- **Secrets:** `.env` only; `.gitignore` blocks `.env*`; the token cache lives in `.ralph/` (ignored); never paste
  tokens into prompts, docs, or reports.
