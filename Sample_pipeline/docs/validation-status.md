# 11 — Validation Status (proven vs. doc-derived)
> Trust calibration for an agent (and humans). Everything in these docs is either **executed & verified on the test
> store** or **derived from shopify.dev / CLI help but not yet run**. Treat the latter as "expected to work" — verify
> before relying on it unattended. Harness note: a trust model is how the harness keeps "documented" from being
> mistaken for "true" — the RAG half of this harness is calibrated, not blind.

## ✅ Executed & verified (2026-08-19, dev store, Shopify CLI 4.6.1)
| Capability | How it was proven |
|---|---|
| `npm i -g @shopify/cli` → `shopify` 4.x | installed; `shopify version` |
| `shopify auth login` headless device flow | printed code + URL; approved once; session persisted |
| `shopify theme list --store … [--json]` | returned live / unpublished themes with ids + roles |
| `shopify theme init theme --clone-url https://github.com/Shopify/dawn.git` | Dawn 16.0.0 cloned (default `theme init` now clones Shopify's Skeleton starter) |
| `shopify theme push --path theme --unpublished --theme "<name>" --json` | created a NEW unpublished theme; JSON returned id, editor_url, preview_url; live theme untouched |
| `shopify theme pull --theme <id> --only layout/theme.liquid` | round-trip succeeded |
| preview URL `?preview_theme_id=<id>` | 302 (sets preview cookie) → storefront; password-protected store then 302s to `/password` |
| `scripts/theme-baseline.sh push-target <name>` | created unpublished theme `harness-playbook-baseline` and printed its id |
| `scripts/theme-baseline.sh init --from-store` | pulled the store's theme (345 files) into `theme/` in a scratch repo |
| `scripts/theme-baseline.sh snapshot` / `catalog` / `reset` | tag + fingerprint printed; catalog generated; reset restores `theme/` from the tag and clears packs (dry-run on a scratch copy) |
| Offline harness self-tests (`npm run test:orchestration`) | stub agents; every exit path asserted |

## ⚠️ Documented but NOT yet executed here (verify before unattended use)
| Capability | Status / risk |
|---|---|
| Admin API token via client-credentials grant (`scripts/shopify-admin-token.mjs`) | endpoint + body from docs; needs an app with scopes on the store |
| `pageCreate` / `blogCreate` / `articleCreate` / `menuCreate` / `urlRedirectCreate` / `themePublish` | mutations + scopes from the Admin GraphQL reference; scripts untested against a store |
| `shopify theme publish`, `theme dev`, `theme check`, `--password` auth | from CLI docs |
| Theme Access app password path | from docs |
| Password-gate selectors on non-Dawn themes | Dawn's `<details>` form verified in code review only; generic `input[name=password]` fallback |
| Homepage SEO via admin UI/CDP | admin-only setting; CDP path inherited from the original harness (verified there, not here) |

## Trust legend used across `docs/`
✅ executed here · ⚠️ doc-derived / inherited, not re-tested · (no mark) = platform-neutral harness logic covered by the offline self-tests.
