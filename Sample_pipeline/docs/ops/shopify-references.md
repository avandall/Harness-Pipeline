# 09 — Shopify official references (docs-first rule)
> **Rule:** when learning a Shopify behavior or debugging one, **consult the official docs FIRST** — never brute-force
> endpoints. Resolve it, link it, and when it mattered, **record the link in `LEARNINGS.md`**. Harness note: this is the
> "retrieval" half of the harness — the agent is told exactly where trustworthy knowledge lives.

| Topic | Link |
|---|---|
| Theme architecture | https://shopify.dev/docs/storefronts/themes/architecture |
| Liquid reference | https://shopify.dev/docs/api/liquid |
| Section schema, settings types | https://shopify.dev/docs/storefronts/themes/architecture/sections/section-schema · …/settings/input-settings |
| JSON templates | https://shopify.dev/docs/storefronts/themes/architecture/templates/json-templates |
| Shopify CLI theme commands | https://shopify.dev/docs/api/shopify-cli/theme |
| Theme push / publish flags | https://shopify.dev/docs/api/shopify-cli/theme/theme-push · …/theme-publish |
| GitHub integration (theme at repo root) | https://shopify.dev/docs/storefronts/themes/tools/github |
| Admin GraphQL API (versions, explorer) | https://shopify.dev/docs/api/admin-graphql |
| `pageCreate`, `blogCreate`, `articleCreate` | https://shopify.dev/docs/api/admin-graphql/latest/mutations/pageCreate |
| `menuCreate`, `urlRedirectCreate`, `themePublish` | https://shopify.dev/docs/api/admin-graphql/latest/mutations/menuCreate |
| Access tokens: client-credentials grant (24h) | https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/client-credentials-grant |
| Access scopes | https://shopify.dev/docs/api/usage/access-scopes |
| Theme Access app (CLI password) | https://shopify.dev/docs/storefronts/themes/tools/theme-access |
| Dawn source | https://github.com/Shopify/dawn |

**Verified gaps (so we don't re-discover):** homepage SEO title/description has no public Admin API (Preferences UI
only) · the admin no longer creates new custom apps (Dev Dashboard + client credentials) · GitHub integration ignores
anything outside the theme folder structure at the branch root.
