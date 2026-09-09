#!/usr/bin/env node
// Mint (and cache) a Shopify Admin API access token — the "token is a dependency, wrap it" pattern.
//
// WHY: since 2026 new apps are created in the Shopify Dev Dashboard and no longer show a permanent
// token. Apps you own can exchange their client credentials for a 24-hour Admin API token:
//   POST https://{store}/admin/oauth/access_token
//   Content-Type: application/x-www-form-urlencoded
//   grant_type=client_credentials&client_id=…&client_secret=…
//   → { "access_token": "…", "scope": "write_content,…", "expires_in": 86399 }
// (docs: shopify.dev → apps → authentication → access tokens → client credentials grant — ⚠️ doc-derived,
// not yet executed in this repo; see docs/validation-status.md). A legacy static token (shpat_…) from an
// app created before 2026 still works: set SHOPIFY_ADMIN_TOKEN and this script just returns it.
//
// Harness rules encoded here:
//   - secrets come from .env (scripts/env.mjs); nothing is ever printed except the token on stdout when asked;
//   - the cache lives under .ralph/ (gitignored) and is refreshed a few minutes before expiry;
//   - a 401/403 from the API is reported as "scope or credentials", never silently swallowed.
//
// Usage:  node scripts/shopify-admin-token.mjs            → prints the token (for shell use: TOKEN=$(node …))
//         node scripts/shopify-admin-token.mjs --check    → prints scope + expiry, exit 0/1
//         import { getAdminToken } from './shopify-admin-token.mjs'   (used by scripts/shopify-admin.mjs)
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { loadEnv } from './env.mjs';
import { isMainModule } from './is-main.mjs';

const CACHE = path.resolve('.ralph/shopify-token.json');
const REFRESH_MARGIN_S = 10 * 60; // re-mint 10 minutes before expiry

export async function getAdminToken(env = loadEnv()) {
  if (env.SHOPIFY_ADMIN_TOKEN) return { token: env.SHOPIFY_ADMIN_TOKEN, source: 'static', scope: null, expiresAt: null };
  const store = (env.SHOPIFY_STORE || '').replace(/^https?:\/\//, '').replace(/\/+$/, '');
  if (!store || !env.SHOPIFY_CLIENT_ID || !env.SHOPIFY_CLIENT_SECRET) {
    throw new Error('need SHOPIFY_STORE + SHOPIFY_CLIENT_ID + SHOPIFY_CLIENT_SECRET (or a static SHOPIFY_ADMIN_TOKEN) in .env');
  }
  if (existsSync(CACHE)) {
    try {
      const cached = JSON.parse(readFileSync(CACHE, 'utf8'));
      if (cached.store === store && cached.expiresAt - REFRESH_MARGIN_S * 1000 > Date.now()) return { ...cached, source: 'cache' };
    } catch { /* corrupt cache → re-mint */ }
  }
  const body = new URLSearchParams({ grant_type: 'client_credentials', client_id: env.SHOPIFY_CLIENT_ID, client_secret: env.SHOPIFY_CLIENT_SECRET });
  const res = await fetch(`https://${store}/admin/oauth/access_token`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
  const text = await res.text();
  if (!res.ok) throw new Error(`token mint failed: HTTP ${res.status} — credentials, app install, or scopes (${text.slice(0, 200)})`);
  const json = JSON.parse(text);
  const record = { store, token: json.access_token, scope: json.scope, expiresAt: Date.now() + (json.expires_in || 86399) * 1000 };
  mkdirSync(path.dirname(CACHE), { recursive: true });
  writeFileSync(CACHE, JSON.stringify(record, null, 2), { mode: 0o600 });
  return { ...record, source: 'minted' };
}

if (isMainModule(import.meta.url)) {
  try {
    const t = await getAdminToken();
    if (process.argv.includes('--check')) {
      console.log(`token ok (${t.source}) scope=${t.scope || '(static token: scopes unknown)'} expires=${t.expiresAt ? new Date(t.expiresAt).toISOString() : 'never'}`);
    } else process.stdout.write(t.token);
  } catch (e) { console.error(`shopify-admin-token: ${e.message}`); process.exit(1); }
}
