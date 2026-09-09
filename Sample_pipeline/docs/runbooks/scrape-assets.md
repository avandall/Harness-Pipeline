# Runbook: Asset handling (exact source bytes first)
**Rule:** CAPTURE records every rendered asset (`capture-assets.mjs` → `assets.json`, SHA-256, re-fetched to prove
exactness); BUILD copies each `localPath` to `theme/assets/<file>` **unchanged** and references it with `asset_url`;
`validate-assets.mjs --public` proves the copy. Never hotlink the source CDN, never replace with a lookalike, never
rename ad hoc (the filename is the contract). Fonts: prefer `font_picker`; bundle only when the source font is not in
Shopify's library (note it in the report). Third-party widget glyphs: `skipSelectors` per migration, not failures.
