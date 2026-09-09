#!/usr/bin/env node
// Create URL redirects (old source paths → new Shopify paths) from a TSV — route parity for every path
// that changed. Scope: write_online_store_navigation. ⚠️ doc-derived (urlRedirectCreate). Idempotent:
// skips a path that already redirects to the same target.
//
// redirects.tsv:  /old-about\t/pages/about      (one per line; '#' comments allowed)
// Usage:  node scripts/create-redirects.mjs migrations/_redirects.tsv
import { readFileSync } from 'node:fs';
import { adminGraphql, assertNoUserErrors } from './shopify-admin.mjs';
import { isMainModule } from './is-main.mjs';

export async function createRedirect({ path, target }) {
  const q = `mutation($r: UrlRedirectInput!) { urlRedirectCreate(urlRedirect: $r) { urlRedirect { id path target } userErrors { field message } } }`;
  return assertNoUserErrors((await adminGraphql(q, { r: { path, target } })).urlRedirectCreate, 'urlRedirectCreate').urlRedirect;
}

if (isMainModule(import.meta.url)) {
  const file = process.argv[2];
  if (!file) { console.error('usage: create-redirects.mjs <redirects.tsv>'); process.exit(2); }
  const rows = readFileSync(file, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')).map((l) => l.split('\t'));
  let ok = 0;
  for (const [path, target] of rows) {
    try { const r = await createRedirect({ path, target }); console.log(`✓ ${r.path} → ${r.target}`); ok++; }
    catch (e) { if (/already exists|has already been taken/i.test(e.message)) console.log(`= ${path} (exists)`); else { console.error(`✗ ${path}: ${e.message}`); } }
  }
  console.log(`${ok}/${rows.length} redirects created`);
}
