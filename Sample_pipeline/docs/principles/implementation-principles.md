# Implementation Principles (READ FIRST)

> **Authority: principles.** Harness note: product-quality rules the agent must internalize before building — they turn
> "make it look the same" into "make it a reusable theme".

## Reusability (productized output)
- Every piece of UI is a proper section: `{% schema %}` with settings, `presets`, a `color_scheme`, spacing/layout
  settings, locale keys. No one-off HTML in templates, no `custom-liquid` escape hatch as a crutch.
- **Reuse-first:** before authoring, check `migrations/_sections.md` (the catalog) and `theme/sections/` — reuse an
  existing section type with a new preset/instance; author a new one only when no type fits, and make it reusable.
- Shared globals (header, footer, announcement, color schemes, fonts, container width) are built once and inherited.

## Theme vs apps
- The theme owns layout and content. Third-party widgets (chat, reviews, popups) are **apps**: the theme leaves a
  documented mount hook (app block / snippet) — we do not re-implement them (classify as DEFER-to-app in `interactions.md`).

## Product page (PDP) safety
- Never break add-to-cart, variant selection, price/availability rendering; keep Dawn's product form and media gallery
  contracts; style, don't rewire.

## Typography, spacing, color, responsive
- Global type scale and container width are set once in `config/settings_schema.json` / `settings_data.json` and
  measured from the source (the #1 whole-page miss is the container width).
- Colors only via color schemes (`docs/craft/color-schemes.md`); spacing/layout via schema settings rendered into CSS
  custom properties with a mobile override (`docs/craft/responsive-settings.md`).

## Naming conventions
- Files/folders: kebab-case. Setting ids: snake_case. Locale keys: `t:sections.<section>.settings.<id>.label`.
- **Brand-neutral structural names are required** (`image-with-text`, `logo-list`, `hero-video`), never the merchant's
  brand/campaign words in file or setting names — those belong in editable content.
