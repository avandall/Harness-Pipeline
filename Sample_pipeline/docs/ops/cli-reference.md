# 02 — Shopify CLI (`shopify theme …`) Reference
> **Authority: ops.** ✅ = executed on the test store · ⚠️ = from the docs, not yet run here.

```bash
shopify auth login                                          # ✅ browser/device auth (one-time)
shopify theme list --store $SHOPIFY_STORE [--json]          # ✅ id · name · role (live | unpublished | development)
shopify theme push --path theme --theme $SHOPIFY_THEME_ID --store $SHOPIFY_STORE [--json]   # ✅ deploy to the UNPUBLISHED target
shopify theme push --path theme --unpublished --theme "harness-dev" --store $SHOPIFY_STORE  # ✅ create a NEW unpublished theme
shopify theme push … --only sections/hero.liquid --nodelete  # ⚠️ surgical push; --nodelete keeps remote-only files
shopify theme pull --path theme --theme $SHOPIFY_THEME_ID --only layout/theme.liquid         # ✅ round-trip verify
shopify theme dev --path theme --store $SHOPIFY_STORE        # ⚠️ local preview with hot reload (development theme)
shopify theme publish --theme $SHOPIFY_THEME_ID --store $SHOPIFY_STORE                       # ⚠️ GO-LIVE — explicit step only
shopify theme check --path theme                            # ⚠️ Theme Check linting
```
Useful flags: `--json` (machine output: id, role, editor_url, preview_url), `--password` (Theme Access / Admin token
instead of a login), `--allow-live` (required to push onto the live theme — **we never set it**), `--publish` (push then
publish — never in a migration iteration), `--environment` (`shopify.theme.toml` profiles).
Env equivalents: `SHOPIFY_FLAG_STORE`, `SHOPIFY_FLAG_THEME_ID`, `SHOPIFY_FLAG_PATH`, `SHOPIFY_CLI_THEME_TOKEN`,
`SHOPIFY_CLI_NO_ANALYTICS=1`. Preview URL shape: `https://<store>.myshopify.com/?preview_theme_id=<id>` (✅ — it 302s
once to set the preview cookie; password-protected stores then redirect to `/password`).
