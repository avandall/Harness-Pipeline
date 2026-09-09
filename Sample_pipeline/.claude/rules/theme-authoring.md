---
paths:
  - "theme/sections/**/*"
  - "theme/blocks/**/*"
  - "theme/templates/**/*"
  - "theme/locales/**/*"
---
# Rule: Theme authoring (auto-loaded when editing sections/blocks/templates/locales)
Authority: `docs/craft/liquid-syntax.md`, `docs/craft/sections-blocks-templates.md`, `docs/craft/settings-schema-and-locales.md`, `docs/principles/implementation-principles.md`.

> Harness note: a *rule* is a short, path-scoped reminder that loads itself exactly when you touch these files. It
> never holds the knowledge — it cites the doc that does. Keep rules under ~15 lines.

- Liquid only, Online Store 2.0: sections are `.liquid` files with a `{% schema %}` JSON block; pages are JSON templates (`templates/*.json`) that compose sections — never one-off page HTML in a template.
- Files use kebab-case; setting ids use snake_case; labels use `t:` keys defined in `locales/en.default.schema.json`.
- Structural names are brand-neutral and role-based (`image-with-text`, not `acme-hero`). Brand wording lives in settings/content only.
- Every merchant-addable section has `presets`, a `color_scheme` setting, real defaults, and section-level spacing settings.
- Image settings are `"type": "image_picker"`; render with `image_url` / `image_tag`; bundled files via `asset_url`.
- Section root carries `{{ section.shopify_attributes }}`; block roots carry `{{ block.shopify_attributes }}` so the theme editor can select/reorder.
- Give every migrated section a stable root `data-section-key="<key>"` — it is the contract's `replicaSelector`.
