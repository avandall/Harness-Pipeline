# Craft: Color Schemes (theme-wide)
> **Authority: craft.** **Trust: ✅ platform-documented (Dawn mechanism).** Harness note: this is the pixel-close color
> engine — brand colors live in ONE place and every section consumes them.

1. **Define** schemes in `theme/config/settings_schema.json` under a `color_scheme_group` setting (`background`,
   `text`, `button`, `button_label`, `secondary_button_label`, `shadow`, …) — values in `settings_data.json`.
2. **Emit** — Dawn's `layout/theme.liquid` loops `settings.color_schemes` and writes one `.color-<id>` block of CSS
   custom properties (`--color-background`, `--color-foreground`, `--color-button`, …).
3. **Expose** — every section schema has `{ "type": "color_scheme", "id": "color_scheme", "default": "scheme-1", "label": "t:sections.all.colors.label" }`.
4. **Apply** — the section root carries `class="color-{{ section.settings.color_scheme }} gradient"`.
5. **Consume** — section CSS uses `rgb(var(--color-background))`, `rgb(var(--color-foreground))`, button vars. **No hardcoded brand hex in section CSS.**
Checklist: new scheme → schema group + data; new section → setting + root class + vars only; then the gate at both viewports.
