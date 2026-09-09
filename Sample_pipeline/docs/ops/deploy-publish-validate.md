# 05 — Deploy, Publish & Validate
> **Authority: ops.** Harness note: "deploy before validate" + "publish is a separate step" are guardrails, not habits.

## 1. Deploy (push to the UNPUBLISHED target) — every phase boundary
```bash
shopify theme push --path theme --theme $SHOPIFY_THEME_ID --store $SHOPIFY_STORE --json   # ✅
```
Confirm the whole page renders on the preview URL (`?preview_theme_id=$SHOPIFY_THEME_ID`) before any gate.

## 2. Publish (GO-LIVE — explicit, human-approved, never inside an iteration)
`shopify theme publish --theme $SHOPIFY_THEME_ID` (⚠️) or Admin GraphQL `themePublish` (⚠️). The runner only mirrors
the theme to the GitHub-connected branch when `RALPH_SYNC_LIVE=1` (`scripts/sync-theme-branch.sh`). `--allow-live` and
`--publish` on push are never used by the harness.

## 3. Validate — isolated Chrome + CDP (doesn't disturb your own browser)
The visual-diff harness launches its own Playwright Chromium (`scripts/visual-diff/launch.mjs`, run-tagged so the loop
can reap only what it spawned). The chrome-devtools MCP is the agent's eyes + ruler for side-by-side work. For the
admin-only fallback tasks: `node scripts/ensure-admin-cdp.mjs` (exit 0 ready · 10 one-time human login · 2 error).
**Password gate:** a protected store 302s to `/password`; the harness submits `STOREFRONT_PASSWORD` there (Dawn's form
sits inside a collapsed "Enter using password" `<details>`; other themes show it inline — selector-based, not URL-based).
**Preview bar:** the iframe Shopify injects on unpublished-theme previews is hidden during capture.

## Validation checklist (per migrated page)
deployed to the unpublished theme ✓ · `contract-diff.mjs` desktop + mobile (+ `--keep-overlays` if an overlay section) ✓ ·
review images looked at ✓ · interactions tests green ✓ · `validate-assets.mjs --public` ✓ · routes resolve (no 404) ✓ ·
`reports/final.md` + `reports/visual-verify.md` ✓ · LEARNINGS appended ✓ · commit + push ✓.
