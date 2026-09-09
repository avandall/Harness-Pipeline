---
paths:
  - "theme/sections/**/*"
  - "theme/config/settings_schema.json"
  - "theme/layout/theme.liquid"
---
# Rule: Color schemes (auto-loaded when editing sections / settings schema / the theme layout)
Authority: `docs/craft/color-schemes.md`, `docs/principles/implementation-principles.md`.

- Every merchant-addable section exposes a `color_scheme` setting (type `color_scheme`, a default).
- Apply the scheme on the section root: `color-{{ section.settings.color_scheme }}` (Dawn pattern).
- Section CSS reads scheme variables (`rgb(var(--color-foreground))`, `rgb(var(--color-background))`, button/card vars) — never hardcoded brand hex in section CSS.
- Brand colors go into `config/settings_schema.json` (`color_scheme_group`); Dawn emits one `.color-<scheme>` CSS block per scheme from `layout/theme.liquid` (`{% style %}` loop over `settings.color_schemes`). Add schemes in the schema group, never as ad-hoc CSS.
