# Craft: Sections, Blocks & JSON Templates
> **Authority: craft.** **Trust: ✅ platform-documented.** The modular unit model of an Online Store 2.0 theme.

- **Section** = `theme/sections/<name>.liquid`: markup + `{% schema %}{ "name", "settings", "blocks", "presets", "disabled_on"/"enabled_on" }{% endschema %}`.
  A section with `presets` is merchant-addable in the theme editor. Root must carry `{{ section.shopify_attributes }}`
  and, for our migration gate, `data-section-key="<contract key>"` + `data-section-type="<name>"`.
- **Blocks** = repeatable children declared in the section schema (`"blocks": [{ "type": "item", "name": "Item", "settings": [...] }]`),
  rendered with `{% for block in section.blocks %} … {{ block.shopify_attributes }}`. (Newer *theme blocks* live in
  `theme/blocks/` and are shared across sections; Dawn 16 uses section blocks.)
- **JSON template** = `theme/templates/<name>.json`: `{ "sections": { "<id>": { "type": "<section-file>", "settings": {…}, "blocks": {…}, "block_order": [...] } }, "order": ["<id>", …] }`.
  A page route renders `page.json` or `page.<suffix>.json` (`templateSuffix` on the page record). Templates never hold HTML.
- **Section groups** = `theme/sections/header-group.json`, `footer-group.json`: the merchant-reorderable header/footer areas.
- **Snippets** = `theme/snippets/*.liquid`, rendered with `{% render %}` — small reusable fragments (cards, icons, price).
- **Recipe for a migrated section:** schema first (settings that mirror the source's variable parts) → markup with the
  stable root → `{% style %}` with custom properties → a preset → locale keys → one instance in the page's JSON template.
  Full recipe: `docs/runbooks/build-a-section.md`.
