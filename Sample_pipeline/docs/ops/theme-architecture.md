# 04 — Theme Architecture & Content Model (Online Store 2.0 / Dawn)
> **Authority: ops.** **Trust: ✅ platform-documented.**

## Template engine: Liquid (not Handlebars, not JSX)
```
theme/
├─ layout/theme.liquid          # the only REQUIRED file: <html> shell, {{ content_for_header }}, {{ content_for_layout }}
├─ templates/*.json             # page types (index, page, page.<suffix>, product, collection, blog, article, 404, password, …)
├─ sections/*.liquid            # modular blocks with {% schema %}; + header-group.json / footer-group.json (section groups)
├─ blocks/                      # (theme blocks, newer themes; Dawn 16 uses section blocks)
├─ snippets/*.liquid            # {% render %} fragments
├─ assets/                      # ONE flat folder: css/js/images/fonts → asset_url
├─ config/settings_schema.json  # global theme-editor settings (color_scheme_group, fonts, layout…) + settings_data.json (values)
└─ locales/*.json, *.schema.json # storefront strings / editor labels
```
## How a page renders (mental model)
route → template (JSON) → ordered sections (each with settings/blocks) → each section's Liquid + `{% schema %}` →
wrapped in `<div id="shopify-section-<id>" class="shopify-section">` inside `layout/theme.liquid`; global settings from
`settings_data.json`; menus from `linklists`; content objects (page/blog/product) from store records created via the
Admin API. **A template is theme code; a page/blog/menu is store data** — creating one never creates the other.

## Stock sections catalog (the base theme's vocabulary)
Dawn ships ~48 sections: page-building (`image-banner`, `image-with-text`, `rich-text`, `multicolumn`, `multirow`,
`collage`, `slideshow`, `video`, `featured-collection`, `featured-product`, `collection-list`, `featured-blog`,
`newsletter`, `email-signup-banner`, `contact-form`, `collapsible-content`, `custom-liquid`), global (`announcement-bar`,
`header`, `footer` + the two section groups), page-type `main-*` (product, collection, blog, article, page, search, cart,
404, password), commerce/cart, plus 190 assets, 51 locales and the `Dawn` settings preset. Regenerate the list with
`scripts/theme-baseline.sh catalog` (seeds `migrations/_sections.md`). `custom-liquid` exists but is **not** a migration
fallback — author a reusable section instead. Step 0 runbook: `docs/runbooks/start-from-base-theme.md`.

## Content-source model (where storefront content lives)
| Content | Lives in | Created by |
|---|---|---|
| section copy/images/layout | the template JSON (settings) + theme assets | the theme (git + `shopify theme push`) |
| pages `/pages/<handle>` | page records (`pageCreate`, `templateSuffix` → `templates/page.<suffix>.json`) | Admin API |
| blogs/articles `/blogs/<handle>/<article>` | blog + article records | Admin API |
| navigation | menus (`menuCreate`) referenced by `link_list` settings | Admin API |
| redirects | `urlRedirectCreate` | Admin API |
| homepage SEO title/description | Online Store → Preferences (no public API) | human / CDP fallback |

## Migration mapping cheat-sheet (source → theme)
hero with media → `image-banner` / `video` + settings · logo bar → `multicolumn`/new `logo-list` · text+image →
`image-with-text` · feature grid → `multicolumn` · FAQ → `collapsible-content` · newsletter → `newsletter` · footer
columns → `footer` blocks · anything without a stock fit → a new brand-neutral section (`docs/runbooks/build-a-section.md`).
Setting-type vocabulary: `docs/craft/settings-schema-and-locales.md`.
