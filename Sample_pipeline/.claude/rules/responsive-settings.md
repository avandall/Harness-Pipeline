---
paths:
  - "theme/sections/**/*"
  - "theme/blocks/**/*"
---
# Rule: Responsive settings (auto-loaded when editing sections/blocks)
Authority: `docs/craft/responsive-settings.md`, `docs/principles/implementation-principles.md`.

- Merchant-controlled spacing/layout/size are schema settings (`range`/`select`) rendered into CSS custom properties on the section root; desktop defaults + mobile overrides behind `@media screen and (max-width: 749px)` (Dawn's breakpoint).
- Do not duplicate the same spacing values in static CSS; CSS handles structure/states the settings cannot express.
- Verify desktop AND mobile after every edit (the gate runs both). A desktop-only match is incomplete.
