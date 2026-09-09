# Runbook: STEP 0 — start from a base theme (the starting point every migration builds on)
> Harness note: an agent should never build "from nothing". It starts from a **known, committed base theme** whose
> stock sections, snippets, assets, settings and locales are the vocabulary the migration reuses — and every fresh
> run starts from **exactly** that baseline again (comparable runs, no leakage from a half-finished run). The
> original harness did this by hand with "reset theme to pristine default" commits; here it is one script.

## The two kinds of starting point
| Starting point | When | Command |
|---|---|---|
| **A stock theme** (Dawn — or Shopify's lighter Skeleton, or any theme repo) | greenfield migration: the target store has no theme worth keeping | `scripts/theme-baseline.sh init` (Dawn) · `init --clone-url <git-url>` |
| **The merchant's existing theme** pulled from the store | you must build on what the store already runs (its settings, assets, customizations are the baseline) | `scripts/theme-baseline.sh init --from-store` (pulls `SHOPIFY_THEME_ID` into `theme/`) |

## The procedure
1. **Init** `theme/` (one of the two above) → review → `git add theme && git commit -m "theme: baseline"`.
2. **Snapshot** — `scripts/theme-baseline.sh snapshot` tags that commit `theme-baseline` and prints the theme
   fingerprint (`migration-state.mjs fingerprint` — the same hash every `gate.json` is bound to).
3. **Catalog** — `scripts/theme-baseline.sh catalog > migrations/_sections.md` seeds the reuse catalog: the stock
   sections (Dawn: `image-banner`, `image-with-text`, `rich-text`, `multicolumn`, `multirow`, `collage`, `slideshow`,
   `video`, `featured-collection`, `featured-product`, `collection-list`, `featured-blog`, `newsletter`,
   `email-signup-banner`, `contact-form`, `collapsible-content`, `announcement-bar`, `header`, `footer`, the
   `main-*` page-type sections …), templates, snippets, the 190 assets, 51 locales, the `Dawn` settings preset.
   PLAN maps every source band onto this catalog first; a new section is authored only when nothing fits.
4. **Push the baseline to a dedicated UNPUBLISHED target** — `scripts/theme-baseline.sh push-target <name>` prints
   the new theme id → `SHOPIFY_THEME_ID` in `.env`. Never the live theme; the previous live theme stays as rollback.
5. **Migrate** (Plan → Execute). The migration **adds** to the baseline: captured assets into `theme/assets/` (exact
   bytes, `asset_url`), brand tokens into `config/settings_data.json` (schemes, fonts, container width), content into
   JSON templates, new brand-neutral sections only where the catalog has no fit.
6. **Fresh run?** `scripts/theme-baseline.sh reset` restores `theme/` to the tag, clears per-page packs, the queue and
   `.ralph/` — the harness, `migrations/_brief.md`, `_example/`, and `reference/` stay. Commit the reset, push the
   baseline to the target, start Plan again.

## Content-source model (where a rendered value comes from — increasing priority)
1. **Schema `default`** in the section's `{% schema %}` — shows only when nothing overrides it.
2. **JSON template** `templates/*.json` `settings`/`blocks` — **where the migration writes per-page content.**
3. **Section groups** `sections/header-group.json`, `footer-group.json` — global header/footer composition.
4. **Theme settings** `config/settings_data.json` (`current` + presets) — global look (schemes, fonts, layout).
5. **Merchant-set values** entered in the theme editor, stored server-side — they materialize into the files on
   `shopify theme pull` (which is why `init --from-store` is the right baseline for an existing store).
→ A migration injects content into **(2)** and **(4)**, relies on **(1)** for fields it leaves unset, and keeps **(5)**
by pulling before it pushes when building on a live merchant theme.
