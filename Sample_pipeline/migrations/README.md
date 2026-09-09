# migrations/ — per-page evidence packs
One folder per page (`migrations/<page>/`, `<page>` = the route handle). Underscore files/folders are harness-owned:
`_queue.tsv` (the sealed, ordered route inventory: `<page-key>\t<source>`), `_scope.json` (its source + SHA), `_brief.md`
(authoritative decisions for non-interactive runs), `_sections.md` (the reuse catalog — seeded from the base theme by `scripts/theme-baseline.sh catalog`, extended per migration), `_example/` (a worked contract).
`scripts/plan.sh` owns the queue; per-page agents never edit it. Plan succeeds only when every queued pack validates;
`scripts/ralph.sh` succeeds only when every queued page is gate-verified — a lone `home/` can never masquerade as a
finished site. Shapes + lifecycle: `docs/contract-and-evidence.md`. State queries: `node scripts/migration-state.mjs
<queue|pack|planned|remaining|active|fingerprint> [path]`.
