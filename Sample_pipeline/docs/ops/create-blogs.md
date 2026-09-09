# 08 — Create blogs & articles
> Trust: ⚠️ doc-derived (Admin GraphQL `blogCreate` / `articleCreate`, scope `write_content`). Part of route parity.
```graphql
mutation { blogCreate(blog: { title: "News", handle: "news" }) { blog { id handle } userErrors { field message } } }
mutation { articleCreate(article: { blogId: "gid://shopify/Blog/…", title: "Hello", handle: "hello",
           body: "<p>…</p>", isPublished: true, author: { name: "Team" } }) { article { id handle } userErrors { field message } } }
```
`node scripts/create-blog.mjs blog "News" news` · `node scripts/create-blog.mjs article <blogGid> "Hello" hello "<p>…</p>"`.
Attach a theme template with `templateSuffix` (`templates/article.<suffix>.json`). Verify `/blogs/news/hello` resolves.
