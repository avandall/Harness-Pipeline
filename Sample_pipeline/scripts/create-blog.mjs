#!/usr/bin/env node
// Create a blog (/blogs/<handle>) and/or an article (/blogs/<handle>/<article>) via Admin GraphQL.
// Scope: write_content. ⚠️ doc-derived (blogCreate / articleCreate). Part of route parity.
//
// Usage:  node scripts/create-blog.mjs blog "<Title>" <handle> [--template <suffix>]
//         node scripts/create-blog.mjs article <blogGid> "<Title>" <handle> "<html body>" [--author "<name>"] [--draft]
import { adminGraphql, assertNoUserErrors } from './shopify-admin.mjs';
import { isMainModule } from './is-main.mjs';

export async function createBlog({ title, handle, templateSuffix = null }) {
  const q = `mutation($blog: BlogCreateInput!) { blogCreate(blog: $blog) { blog { id handle title } userErrors { field message } } }`;
  return assertNoUserErrors((await adminGraphql(q, { blog: { title, handle, templateSuffix } })).blogCreate, 'blogCreate').blog;
}
export async function createArticle({ blogId, title, handle, body, author = 'Team', isPublished = true }) {
  const q = `mutation($article: ArticleCreateInput!) { articleCreate(article: $article) { article { id handle title } userErrors { field message } } }`;
  return assertNoUserErrors((await adminGraphql(q, { article: { blogId, title, handle, body, isPublished, author: { name: author } } })).articleCreate, 'articleCreate').article;
}

if (isMainModule(import.meta.url)) {
  const [kind, ...rest] = process.argv.slice(2);
  const arg = (f) => { const i = rest.indexOf(f); return i >= 0 ? rest[i + 1] : undefined; };
  try {
    if (kind === 'blog') { const [title, handle] = rest; const b = await createBlog({ title, handle, templateSuffix: arg('--template') || null }); console.log(`✓ blog created: /blogs/${b.handle} (${b.id})`); }
    else if (kind === 'article') { const [blogId, title, handle, body] = rest; const a = await createArticle({ blogId, title, handle, body, author: arg('--author') || 'Team', isPublished: !rest.includes('--draft') }); console.log(`✓ article created: ${a.handle} (${a.id})`); }
    else { console.error('usage: create-blog.mjs blog "<Title>" <handle> | article <blogGid> "<Title>" <handle> "<html>"'); process.exit(2); }
  } catch (e) { console.error(`create-blog: ${e.message}`); process.exit(1); }
}
