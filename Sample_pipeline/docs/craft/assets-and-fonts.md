# Craft: Assets, Fonts & CDN
> **Authority: craft.** **Trust: ✅ platform-documented.**

- Shopify themes have ONE flat `theme/assets/` folder; reference by bare filename: `{{ 'hero-…webp' | asset_url }}`,
  `{{ 'section-hero.css' | asset_url | stylesheet_tag }}`, `{{ 'component.js' | asset_url | script_tag }}`.
- Migration rule: captured bytes from `assets.json` are copied **unchanged** to `theme/assets/<file>` (validated by
  `validate-assets.mjs --public`). Never hotlink the source CDN; never rename ad hoc.
- Fonts: prefer `font_picker` settings (Shopify's font library via `font_face`); a bundled webfont goes into
  `theme/assets/` with `@font-face { src: url('{{ 'font.woff2' | asset_url }}') }` only when the source font is not in
  the library (document it in the page report).
- Images in settings: `image_picker` + `image_url`/`image_tag` (responsive `srcset` for free). Don't use relative URLs in CSS.
