# Runbook: Build a section (productized, brand-neutral)
1. **Reuse check:** `migrations/_sections.md` + `theme/sections/` — an existing type + new preset beats a new file.
2. **Schema first:** settings that mirror the source's variable parts (heading, text, image_picker, link, color_scheme,
   padding ranges, alignment/ratio selects), blocks for repeated items, a preset, `t:` labels.
3. **Markup:** `<section data-section-key="<contract key>" data-section-type="<name>" class="color-{{ section.settings.color_scheme }}" {{ section.shopify_attributes }}>`.
4. **Styles:** `{% style %}` scoped to the section with custom properties from settings; mobile override at 749px; no brand hex.
5. **Locales:** add `t:` keys to `locales/en.default.schema.json` (+ other source languages).
6. **Instance:** add it to the page's JSON template with the source's values; `shopify theme push`; gate at both viewports.
7. **Test:** `tests/<section>.test.js` guarding structure/behaviour (not fidelity). Minimal example: `docs/craft/responsive-settings.md`.
