# Craft: Responsive Settings (pixel-close on desktop AND mobile)
> **Authority: craft.** **Trust: ✅ platform-documented (Dawn pattern).**

- Merchant-controlled spacing/layout/size = schema settings (`range` for padding-top/bottom, `select` for alignment,
  columns, image ratio) rendered into CSS custom properties on the section root:
  `{% style %} #shopify-section-{{ section.id }} { --padding-top: {{ section.settings.padding_top }}px; } {% endstyle %}`.
- Desktop defaults plus mobile overrides behind `@media screen and (max-width: 749px)` (Dawn's breakpoint; `min-width: 750px` for desktop-only rules).
- Measure the source at 1440 and 390 (`capture-source` targets) and set the values to match — don't eyeball.
- Don't duplicate the same values in static CSS; CSS handles structure and states the settings can't express.
- A desktop-only match is incomplete — the gate runs both viewports.
