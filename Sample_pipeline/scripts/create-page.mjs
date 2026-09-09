#!/usr/bin/env node
// Create a Shopify custom page record (/pages/<handle>) and attach a theme template — route parity step.
//
// "A template is theme code; a page is store data." The template (theme/templates/page.<suffix>.json) is
// pushed with the CLI; THIS creates the record that makes the route exist and links the template via
// templateSuffix. Scope: write_content or write_online_store_pages. ⚠️ doc-derived (pageCreate).
//
// Usage:  node scripts/create-page.mjs "<Title>" <handle> [--template <suffix>] [--body "<html>"] [--draft]
//         node scripts/create-page.mjs --list
import { adminGraphql, assertNoUserErrors } from './shopify-admin.mjs';
import { isMainModule } from './is-main.mjs';

export async function createPage({ title, handle, templateSuffix = null, body = '', isPublished = true }) {
  const q = `mutation($page: PageCreateInput!) { pageCreate(page: $page) { page { id handle title templateSuffix } userErrors { field message } } }`;
  const data = await adminGraphql(q, { page: { title, handle, templateSuffix, body, isPublished } });
  return assertNoUserErrors(data.pageCreate, 'pageCreate').page;
}
export async function listPages() {
  const data = await adminGraphql(`{ pages(first: 50) { nodes { id handle title templateSuffix } } }`);
  return data.pages.nodes;
}

if (isMainModule(import.meta.url)) {
  const argv = process.argv.slice(2);
  try {
    if (argv.includes('--list')) { console.log(JSON.stringify(await listPages(), null, 2)); process.exit(0); }
    const [title, handle] = argv;
    if (!title || !handle) { console.error('usage: create-page.mjs "<Title>" <handle> [--template <suffix>] [--body "<html>"] [--draft] | --list'); process.exit(2); }
    const arg = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : undefined; };
    const page = await createPage({ title, handle, templateSuffix: arg('--template') || null, body: arg('--body') || '', isPublished: !argv.includes('--draft') });
    console.log(`✓ page created: /pages/${page.handle} (${page.id}) template=${page.templateSuffix || 'default'}`);
  } catch (e) { console.error(`create-page: ${e.message}`); process.exit(1); }
}
