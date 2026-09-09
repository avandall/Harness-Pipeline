# Migration Decisions — v1 (locked, AUTHORITATIVE)

> **Authority: principles.** Harness note: decisions are *files*, not memories. A locked decision record stops every
> new session from re-litigating scope. Change it by editing this file, never by arguing in a prompt.

## Output & quality
- **Productized / modular ONLY.** Every piece of UI is a proper section (schema, presets, color scheme, responsive
  settings, locales). When a source block has no stock section equivalent, **author a new custom section**.
- **Brand-neutral names** for all structure; brand wording only in editable content.
- **Fidelity: pixel-close, desktop AND mobile** — achieved *through* the color-scheme + responsive-settings systems.

## Scope (v1)
- **Static pages + content** — home, about, FAQ, contact, marketing, nav, footer, brand styling. Commerce (products,
  collections, cart) deferred unless a source route demands an explicit mapping.
- **Sources:** a live URL (any platform), a **design-tool export** (HTML/CSS/JS bundle under `reference/`), or any
  static HTML — all enter the same pipeline (`scripts/plan.sh`).
- **Assets: exact-source first.** CAPTURE writes `assets.json` + exact bytes; BUILD copies them byte-for-byte into
  `theme/assets/` and references them with `asset_url` (never hotlink the source CDN).
- **Localization:** carry every source language into `theme/locales/<locale>.json`.
- **SEO/URLs:** preserve handles, create 301 redirects (`urlRedirectCreate`), carry meta (title/description/og).
- **Navigation:** recreate as Shopify menus (`menuCreate`) and wire the header/footer sections to them.
- **Route parity is MANDATORY:** every source route exists on the target — pages (`pageCreate` + `templateSuffix`),
  blogs/articles, collections/products if in scope; missing = incomplete; aliasing = not acceptable unless recorded.

## Operations
- **Tenancy:** one store per migration, isolated `.env`.
- **Target:** always an **unpublished** theme; **publish is a separate explicit step** after human QA on the preview.
- **Precedence on conflict:** split authority — ops/CLI/deploy/records/validation → `docs/ops/*`; Liquid craft → `docs/craft/*`.
