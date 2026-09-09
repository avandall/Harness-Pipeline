# Craft: Liquid Template Syntax (Shopify themes)
> **Authority: craft.** **Trust: ✅ platform-documented** (shopify.dev/docs/api/liquid). Harness note: craft docs are the
> on-demand "how do I write this correctly" shelf — opened only when the task is authoring theme code.

## Essentials
- Output: `{{ product.title }}` · tags: `{% if %} … {% endif %}`, `{% for item in list %}`, `{% assign x = … %}`,
  `{% capture %}`, `{% render 'snippet', arg: value %}` (never `include`), `{% section 'name' %}` / `{% sections 'group' %}`.
- Whitespace control: `{%- -%}` / `{{- -}}`. Comments: `{% comment %}…{% endcomment %}` or `{% # inline %}`.
- Filters chain left to right: `{{ 'hero.webp' | asset_url }}`, `{{ image | image_url: width: 1600 | image_tag: loading: 'lazy' }}`,
  `{{ 'sections.hero.title' | t }}`, `| money`, `| escape`, `| default: 'x'`, `| image_url: width: 800 }}`.
- Objects you will touch most: `section.settings.*`, `section.blocks`, `block.settings.*`, `settings.*` (global),
  `shop`, `page`, `blog`, `article`, `collection`, `product`, `linklists[handle]` (menus), `request`, `localization`.
- Section CSS: `{% style %} … {% endstyle %}` (scoped with `#shopify-section-{{ section.id }}` or a data attribute).
- Never emit brand strings in Liquid literals — they come from settings/locales.

## Cheat sheet — source platform → Shopify Liquid
| Source idiom (Webflow/Wix/WordPress/static) | Shopify |
|---|---|
| static `<img src="cdn/…">` | `{{ 'file.webp' \| asset_url }}` (captured bytes in `theme/assets/`) or an `image_picker` setting rendered with `image_url` |
| hardcoded nav links | `{% for link in linklists[section.settings.menu].links %}` |
| inline brand colors | color scheme variables (`docs/craft/color-schemes.md`) |
| page-specific HTML file | a JSON template composing sections (`docs/craft/sections-blocks-templates.md`) |
| copied text | section/block settings (`text`, `richtext`) with locale defaults |
