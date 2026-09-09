// Tiny Admin GraphQL client — one place that knows the URL, the header, the API version, and how to
// surface userErrors. Every record script (create-page/blog/menu/redirects) goes through here so the
// agent never hand-rolls fetch calls or guesses endpoints (harness rule: docs-first, one client).
//
//   POST https://{store}/admin/api/{SHOPIFY_API_VERSION}/graphql.json
//   X-Shopify-Access-Token: <token>      (from scripts/shopify-admin-token.mjs)
//
// ⚠️ doc-derived (Admin GraphQL reference); not yet executed against a store in this repo.
import { loadEnv } from './env.mjs';
import { getAdminToken } from './shopify-admin-token.mjs';

export async function adminGraphql(query, variables = {}, env = loadEnv()) {
  const store = (env.SHOPIFY_STORE || '').replace(/^https?:\/\//, '').replace(/\/+$/, '');
  const version = env.SHOPIFY_API_VERSION || '2026-07';
  const { token } = await getAdminToken(env);
  const res = await fetch(`https://${store}/admin/api/${version}/graphql.json`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Shopify-Access-Token': token },
    body: JSON.stringify({ query, variables }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Admin GraphQL HTTP ${res.status}: ${JSON.stringify(json).slice(0, 300)}`);
  if (json.errors?.length) {
    // ACCESS_DENIED here means a missing SCOPE on the app — report it as such, never as "no API exists".
    throw new Error(`Admin GraphQL errors: ${json.errors.map((e) => `${e.extensions?.code || ''} ${e.message}`).join('; ')}`);
  }
  return json.data;
}

// Throw a readable error when a mutation returns userErrors (Shopify's validation channel).
export function assertNoUserErrors(payload, label) {
  const errs = payload?.userErrors || [];
  if (errs.length) throw new Error(`${label}: ${errs.map((e) => `${(e.field || []).join('.')} ${e.message}`).join('; ')}`);
  return payload;
}
