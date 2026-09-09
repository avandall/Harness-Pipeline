#!/usr/bin/env node
// Create a navigation menu (header/footer) from a JSON file — the theme's header/footer sections then
// select it via a `link_list` setting. Scope: write_online_store_navigation. ⚠️ doc-derived (menuCreate).
//
// menu.json: { "title": "Main menu", "handle": "main-menu",
//              "items": [ { "title": "Shop", "type": "HTTP", "url": "/collections/all",
//                           "items": [ { "title": "New", "type": "HTTP", "url": "/collections/new" } ] } ] }
// Usage:  node scripts/create-menu.mjs migrations/home/menus/main-menu.json
import { readFileSync } from 'node:fs';
import { adminGraphql, assertNoUserErrors } from './shopify-admin.mjs';
import { isMainModule } from './is-main.mjs';

export async function createMenu({ title, handle, items }) {
  const q = `mutation($title: String!, $handle: String!, $items: [MenuItemCreateInput!]!) { menuCreate(title: $title, handle: $handle, items: $items) { menu { id handle } userErrors { field message } } }`;
  return assertNoUserErrors((await adminGraphql(q, { title, handle, items })).menuCreate, 'menuCreate').menu;
}

if (isMainModule(import.meta.url)) {
  const file = process.argv[2];
  if (!file) { console.error('usage: create-menu.mjs <menu.json>'); process.exit(2); }
  try { const m = await createMenu(JSON.parse(readFileSync(file, 'utf8'))); console.log(`✓ menu created: ${m.handle} (${m.id})`); }
  catch (e) { console.error(`create-menu: ${e.message}`); process.exit(1); }
}
