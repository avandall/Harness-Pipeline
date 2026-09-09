# 06 — Content & Routes — the route-parity hub
> **Authority: ops.** **MANDATORY for a 1:1 migration:** the store must reproduce **every route the source has** — same
> paths, same content. A missing route = an incomplete migration; a silent alias (`/products` → `/collections/all`) is
> not acceptable unless recorded as an intentional redirect/exception.

| Route type | Shopify path | Create with | Script | Trust |
|---|---|---|---|---|
| home | `/` | `templates/index.json` | — | ✅ |
| custom page | `/pages/<handle>` | Admin GraphQL `pageCreate { title, handle, body, templateSuffix, isPublished }` (scope `write_content` or `write_online_store_pages`) | `scripts/create-page.mjs` | ⚠️ |
| blog / article | `/blogs/<handle>` / `/blogs/<handle>/<article>` | `blogCreate`, `articleCreate` (`write_content`) | `scripts/create-blog.mjs` | ⚠️ |
| navigation | header/footer menus | `menuCreate { title, handle, items[{title,type,url,resourceId,items}] }` (`write_online_store_navigation`) → theme `link_list` settings | `scripts/create-menu.mjs` | ⚠️ |
| redirects (old URLs → new) | any | `urlRedirectCreate { path, target }` (`write_online_store_navigation`) | `scripts/create-redirects.mjs` | ⚠️ |
| collections / products | `/collections/<handle>`, `/products/<handle>` | `collectionCreate`, `productCreate` (`write_products`) — only if commerce is in scope | — | ⚠️ |
| policies, search, cart, account, 404, password | fixed | theme templates | — | ✅ |
| homepage SEO title/description | — | Online Store → Preferences (no public API) | `ensure-admin-cdp.mjs` + human | last resort |

**The rule:** a template (`templates/page.<suffix>.json`) is theme code; the page record is store data — both are
needed, and `templateSuffix` links them. **Two auth models, don't mix them up:** the CLI session (themes) vs the
Admin API token (records). **Per source route:** inventory in CAPTURE → record created in BUILD/GATE → route resolves
(no 404) → redirect for any path that changed → noted in `reports/final.md`.
