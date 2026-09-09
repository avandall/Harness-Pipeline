# reference/ — local sources of truth (design exports, static HTML)
Drop a provided HTML/CSS/JS bundle here — a design-tool export, a designer's static build, an exported site:
```
reference/<name>/index.html  (+ about.html … css/ js/ images/)     or a single  reference/<name>.html
```
Then `scripts/plan.sh --from-reference <name> [--url <backup-url>]` (or upload it in the control panel). Every HTML entry
is queued as a page; `contract.source` becomes `__REF__/<name>/<file>.html`; `scripts/visual-diff/serve-reference.mjs`
serves this folder on `REF_PORT` and the capture + gate scripts resolve `__REF__` automatically — **nothing downstream
changes** versus a live URL. The optional `--url` is gap-fill only (SEO, route intent, unclear copy), never a design
override. Files here are **tracked** so runs are reproducible (large client binaries go to the gitignored `external/`).
