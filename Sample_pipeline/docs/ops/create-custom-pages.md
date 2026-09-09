# 07 — Create custom pages + attach templates
> Custom pages = `/pages/<handle>` (About, FAQ, …). **A template is theme code (CLI push). A page is store data
> (Admin API).** Creating one does not create the other. Trust: ⚠️ doc-derived (GraphQL `pageCreate`, current API).

1. **Template (CLI):** add `theme/templates/page.<suffix>.json` composing the page's sections → `shopify theme push`.
2. **Page record (Admin API):**
```graphql
mutation { pageCreate(page: { title: "About us", handle: "about", templateSuffix: "<suffix>", isPublished: true,
                              body: "" }) { page { id handle } userErrors { field message } } }
```
   Run: `node scripts/create-page.mjs "About us" about --template <suffix>` (mints/uses the token, posts to
   `/admin/api/$SHOPIFY_API_VERSION/graphql.json`). A `userErrors` entry = fix input; `ACCESS_DENIED` = scope, not absence.
3. **Verify:** `https://$SHOPIFY_PRIMARY_DOMAIN/pages/about` renders the template (a 404 means the record is missing;
   a default page look means `templateSuffix` didn't attach).
Fallback only: the admin UI (Online Store → Pages) via the human or the CDP session — after the API path is exhausted.
