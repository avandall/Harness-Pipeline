# Craft: Settings Schema & Locales
> **Authority: craft.** **Trust: ✅ platform-documented.**

- **Global settings:** `theme/config/settings_schema.json` defines the theme-editor groups (`color_scheme_group`,
  typography `font_picker`s, layout/page width, buttons, …); `theme/config/settings_data.json` stores the current values
  (and `presets`). Migrated brand tokens (palette, fonts, **container width**) go here first.
- **Section settings types you'll use:** `text`, `inline_richtext`, `richtext`, `image_picker`, `video`, `url`,
  `link_list` (menus), `color`, `color_scheme`, `range` (spacing/size), `select`, `checkbox`, `font_picker`,
  `header`/`paragraph` (editor-only labels). Always give real `default`s.
- **Images:** `"type": "image_picker"` → `{{ section.settings.image | image_url: width: 1600 | image_tag }}`; aspect
  ratios via a `select` setting that feeds a CSS custom property.
- **Locales:** editor labels via `t:` keys in `theme/locales/en.default.schema.json`; storefront strings via
  `theme/locales/en.default.json` + `{{ 'key' | t }}`; carry every source language as `<locale>.json`.
- **Presets:** every merchant-addable section ships `"presets": [{ "name": "…" }]` so it appears in "Add section".
