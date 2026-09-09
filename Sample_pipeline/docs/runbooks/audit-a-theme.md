# Runbook: Audit a theme
Review against the principles + craft rules; pair with `docs/troubleshooting.md`. Checklist: every merchant-addable
section has schema + presets + `color_scheme` + responsive settings + `t:` labels · no brand words in structural
names · no hardcoded brand colors in CSS · assets referenced via `asset_url` (no hotlinks) · every contract section root
carries `data-section-key` · JSON templates compose sections only · locales cover every source language · `shopify
theme check` clean · gate green at desktop + mobile.
