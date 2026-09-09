// Visual INSPECTION (diagnosis) — the "what + why + target value" layer that turns
// the pixel diff from a validator into a fix tool. For an original and a replica URL
// it renders BOTH, extracts a per-element fingerprint (text, curated computed styles,
// box/layout rect, image src + broken-state, link href), and DIFFS them — with NO
// knowledge of what differs; everything is derived from the rendered output. It also
// runs the pixel diff (score + diff image), a side-by-side merged image, and a
// downscaled review image the loop agent can actually open.
//
// WHY: "score 0.13" is not actionable. "h1 font-size 28px should be 36px; CTA bg
// rgb(61,56,25) should be rgb(17,17,17); hero img broken" is. Output maps cleanly to
// Shopify levers (color_scheme vars, style.* controls, image_url()).
//
// Driver-agnostic by design: uses our own Playwright Chromium so it survives a
// locked chrome-devtools MCP profile (same independence as capture.mjs).
//
// Usage:
//   node scripts/visual-diff/inspect.mjs <originalUrl> <replicaUrl> [desktop|mobile|WxH] [--out dir] [--threshold 0.01]
//   # test affordance — mutate the replica in-page to prove blind detection:
//   node scripts/visual-diff/inspect.mjs <url> <url> desktop --self-mutate tweaks.js
//
// Requires: npm i -D playwright pixelmatch pngjs   (npx playwright install chromium)
import { launchChromium } from './launch.mjs';
import { loadEnv } from '../env.mjs';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const positional = argv.filter((a) => !a.startsWith('--'));
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const [origUrl, replicaUrl = origUrl, viewport = 'desktop'] = positional;
const outDir = flag('--out', 'scripts/visual-diff/out/inspect');
const threshold = Number(flag('--threshold', '0.01'));
const selfMutate = flag('--self-mutate', null);     // test: mutate replica in-page
const injectReplica = flag('--inject-replica', null); // test: run JS on the replica after load
if (!origUrl) {
  console.error('usage: node inspect.mjs <originalUrl> [replicaUrl] [desktop|mobile|WxH] [--out dir] [--self-mutate file]');
  process.exit(1);
}
const PRESETS = { desktop: { width: 1440, height: 900 }, mobile: { width: 390, height: 844 } };
const vp = PRESETS[viewport] ?? (() => { const [w, h] = viewport.split('x').map(Number); return { width: w, height: h || 900 }; })();
mkdirSync(outDir, { recursive: true });

const env = loadEnv();
const { STOREFRONT_PASSWORD, SHOPIFY_STORE, SHOPIFY_PRIMARY_DOMAIN } = env;

// The fidelity-relevant computed styles (what a 1:1 migration must reproduce).
const PROPS = ['font-family', 'font-size', 'font-weight', 'font-style', 'line-height', 'letter-spacing',
  'text-align', 'text-transform', 'text-decoration-line', 'color', 'background-color', 'background-image',
  'border-top-width', 'border-bottom-width', 'border-top-color', 'border-radius', 'margin-top', 'margin-bottom',
  'padding-top', 'padding-bottom', 'padding-left', 'padding-right', 'width', 'height', 'display',
  'flex-direction', 'justify-content', 'align-items', 'gap', 'position', 'opacity', 'box-shadow'];

// Runs IN the browser: fingerprint every meaningful element by a stable DOM path.
function snapshot(props) {
  const ALLOW = new Set(['H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'P', 'A', 'BUTTON', 'IMG', 'LI', 'SECTION',
    'HEADER', 'FOOTER', 'NAV', 'MAIN', 'FORM', 'INPUT', 'LABEL', 'PICTURE', 'SVG', 'SPAN', 'BLOCKQUOTE']);
  const pathOf = (el) => { const parts = []; while (el && el.nodeType === 1 && el.tagName !== 'HTML') { let i = 1, s = el; while ((s = s.previousElementSibling)) { if (s.tagName === el.tagName) i++; } parts.unshift(el.tagName.toLowerCase() + '[' + i + ']'); el = el.parentElement; } return parts.join('>'); };
  const ownText = (el) => { let t = ''; for (const n of el.childNodes) if (n.nodeType === 3) t += n.nodeValue; return t.replace(/\s+/g, ' ').trim().slice(0, 160); };
  const out = []; let truncated = false;
  const all = document.querySelectorAll('*');
  for (const el of all) {
    const tag = el.tagName, ot = ownText(el), isAsset = tag === 'IMG' || tag === 'PICTURE' || tag === 'SVG';
    if (!ALLOW.has(tag) && !ot && !isAsset) continue;
    if (tag === 'SPAN' && !ot) continue;
    const cs = getComputedStyle(el), styles = {};
    for (const p of props) styles[p] = cs.getPropertyValue(p);
    const r = el.getBoundingClientRect();
    const rec = { path: pathOf(el), tag, text: ot, styles, rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) } };
    if (tag === 'IMG') { rec.src = (el.currentSrc || el.src || '').slice(0, 300); rec.broken = !!(el.complete && el.naturalWidth === 0 && (el.src || el.currentSrc)); }
    if (tag === 'A') rec.href = (el.getAttribute('href') || '').slice(0, 300);
    out.push(rec);
    if (out.length >= 2500) { truncated = true; break; }
  }
  return { records: out, domCount: all.length, truncated };
}

async function prep(page) { // trigger lazy content, settle fonts, return to top (matched coords)
  await page.evaluate(async () => { await new Promise((r) => { let y = 0; const s = setInterval(() => { window.scrollBy(0, 800); y += 800; if (y >= document.body.scrollHeight) { clearInterval(s); r(); } }, 60); }); });
  await page.waitForTimeout(400);
  await page.evaluate(() => window.scrollTo(0, 0));
  try { await page.evaluate(() => document.fonts && document.fonts.ready); } catch { /* noop */ }
  await page.waitForTimeout(200);
}
async function gotoSettle(page, url) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await clearGate(page, url);
}
// Clear the Shopify storefront password gate. This store shows the gate INLINE on
// the SAME url (a `#Password` field, optionally behind a collapsed "Login with
// password" toggle) — it does NOT redirect to /password — so we detect the field by
// SELECTOR, not by url (the old `/\/password/` url-guard silently skipped it, leaving
// the capture stuck on the password splash). Host-gated + fully wrapped so it never
// crashes the run. Mirrors tests/home-render.test.js's proven handshake + capture.mjs.
async function clearGate(page, url) {
  const isShopify = /\.myshopify\.com/i.test(url) || (SHOPIFY_STORE && url.includes(SHOPIFY_STORE)) || (SHOPIFY_PRIMARY_DOMAIN && url.includes(SHOPIFY_PRIMARY_DOMAIN));
  if (!STOREFRONT_PASSWORD || !isShopify) return;
  // The `#Password` field starts HIDDEN inside a collapsed <details> whose
  // <summary class="password-modal__trigger"> reads "Login with password" — so we MUST
  // click that trigger first, then WAIT for the field to become visible before filling
  // (filling a hidden field 30s-timeouts). The submit redirects with ?common_result=SUCCESS;
  // re-goto(url) then renders the real page. (Verified flow — see LEARNINGS 2026-06-15 visual-diff.)
  const trigger = page.locator('summary.modal__toggle, summary.password-modal__trigger, summary:has-text("Enter using password"), summary:has-text("Login with password")').first();
  if (await trigger.count().catch(() => 0)) await trigger.click().catch(() => {});
  const pw = page.locator('#Password, input[name="password"]').first();
  if (!(await pw.count().catch(() => 0))) return; // no gate on this page
  try {
    await pw.waitFor({ state: 'visible', timeout: 8000 });
    await pw.fill(STOREFRONT_PASSWORD);
    await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle', timeout: 60000 }).catch(() => {}), pw.press('Enter')]);
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 }).catch(() => {});
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  } catch (e) { console.error('warning: storefront password gate not cleared —', e.message); }
}

const consoleErr = { orig: [], rep: [] };
let phase = 'orig';
// Hoisted out of the try so the diff/report section below can use them; assigned inside.
let origSnap, origPng, repSnap, repPng, replicaLabel = replicaUrl;
const browser = await launchChromium();
try {
  const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: 1,
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36' });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error') consoleErr[phase].push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => { consoleErr[phase].push(String(e.message).slice(0, 200)); });

  // ---- ORIGINAL ----
  await gotoSettle(page, origUrl);
  await prep(page);
  origSnap = await page.evaluate(snapshot, PROPS);
  origPng = await page.screenshot({ fullPage: true });

  // ---- REPLICA ----
  phase = 'rep';
  if (selfMutate) {                                   // test mode: mutate the SAME page in place
    await page.evaluate(readFileSync(selfMutate, 'utf8'));
    await page.waitForTimeout(500); await prep(page);
    replicaLabel = `${origUrl}  (self-mutated: ${selfMutate})`;
  } else {
    await gotoSettle(page, replicaUrl); await prep(page);
    if (injectReplica) { await page.evaluate(readFileSync(injectReplica, 'utf8')); await page.waitForTimeout(400); }
  }
  repSnap = await page.evaluate(snapshot, PROPS);
  repPng = await page.screenshot({ fullPage: true });
} finally {
  await browser.close();   // ALWAYS close — even if extraction throws above — so no zombie Chromium leaks
}

// ---- DOM / STYLE DIFF (blind: derived purely from the two snapshots) ----
const oMap = new Map(origSnap.records.map((r) => [r.path, r]));
const rMap = new Map(repSnap.records.map((r) => [r.path, r]));
const changed = [], missing = [], extra = [];
for (const [p, o] of oMap) {
  const r = rMap.get(p);
  if (!r) { missing.push(o); continue; }
  const diffs = [];
  for (const k of PROPS) if (o.styles[k] !== r.styles[k]) diffs.push({ prop: k, original: o.styles[k], replica: r.styles[k] });
  if (o.text !== r.text) diffs.push({ prop: 'text', original: o.text, replica: r.text });
  if ((o.src || '') !== (r.src || '')) diffs.push({ prop: 'img.src', original: o.src || '', replica: r.src || '' });
  if ((o.href || '') !== (r.href || '')) diffs.push({ prop: 'a.href', original: o.href || '', replica: r.href || '' });
  const moved = ['x', 'y', 'w', 'h'].filter((d) => Math.abs(o.rect[d] - r.rect[d]) > 2);
  if (moved.length) diffs.push({ prop: 'rect(' + moved.join(',') + ')', original: JSON.stringify(o.rect), replica: JSON.stringify(r.rect) });
  if (diffs.length) changed.push({ path: p, tag: o.tag, text: o.text, diffs });
}
for (const [p, r] of rMap) if (!oMap.has(p)) extra.push(r);
const brokenAssets = repSnap.records.filter((r) => r.broken).map((r) => r.src);
// rank: style/text/asset deltas first (actionable roots), rect-only last (usually cascade)
const rootKinds = (c) => c.diffs.some((d) => !d.prop.startsWith('rect'));
changed.sort((a, b) => (rootKinds(b) - rootKinds(a)) || (b.diffs.length - a.diffs.length));

// ---- PIXEL DIFF (same engine as compare.mjs) ----
const a = PNG.sync.read(origPng), b = PNG.sync.read(repPng);
const W = Math.min(a.width, b.width), H = Math.max(a.height, b.height);
const fit = (img) => { const o = new PNG({ width: W, height: H }); for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const di = (y * W + x) * 4; if (y < img.height && x < img.width) { const si = (y * img.width + x) * 4; o.data[di] = img.data[si]; o.data[di + 1] = img.data[si + 1]; o.data[di + 2] = img.data[si + 2]; o.data[di + 3] = img.data[si + 3]; } else { o.data[di] = o.data[di + 1] = o.data[di + 2] = o.data[di + 3] = 255; } } return o; };
const A = fit(a), B = fit(b), diff = new PNG({ width: W, height: H });
const mismatched = pixelmatch(A.data, B.data, diff.data, W, H, { threshold: 0.1 });
const score = mismatched / (W * H);
writeFileSync(path.join(outDir, `${viewport}.diff.png`), PNG.sync.write(diff));
const merged = new PNG({ width: W * 2 + 10, height: H }); merged.data.fill(255);
const blit = (img, offx) => { for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const si = (y * W + x) * 4, di = (y * (W * 2 + 10) + (x + offx)) * 4; merged.data[di] = img.data[si]; merged.data[di + 1] = img.data[si + 1]; merged.data[di + 2] = img.data[si + 2]; merged.data[di + 3] = img.data[si + 3]; } };
blit(A, 0); blit(B, W + 10);
writeFileSync(path.join(outDir, `${viewport}.merged.png`), PNG.sync.write(merged));
// downscaled review image (so the loop agent can open it; the merged is too tall to view)
const maxH = 1600, scale = Math.min(1, maxH / merged.height), rw = Math.max(1, Math.round(merged.width * scale)), rh = Math.max(1, Math.round(merged.height * scale));
const review = new PNG({ width: rw, height: rh });
for (let y = 0; y < rh; y++) for (let x = 0; x < rw; x++) { const sx = Math.min(merged.width - 1, Math.floor(x / scale)), sy = Math.min(merged.height - 1, Math.floor(y / scale)); const si = (sy * merged.width + sx) * 4, di = (y * rw + x) * 4; review.data[di] = merged.data[si]; review.data[di + 1] = merged.data[si + 1]; review.data[di + 2] = merged.data[si + 2]; review.data[di + 3] = merged.data[si + 3]; }
writeFileSync(path.join(outDir, `${viewport}.review.png`), PNG.sync.write(review));

// ---- REPORTS ----
const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
let md = `# Visual inspection — ${viewport}\n\n`;
md += `- **Original:** ${origUrl}\n- **Replica:** ${replicaLabel}\n`;
md += `- **Pixel score:** ${score.toFixed(5)} (${score <= threshold ? 'PASS' : 'REVIEW'} @ ${threshold})\n`;
md += `- **DOM tracked:** original ${origSnap.records.length} / ${origSnap.domCount} nodes · replica ${repSnap.records.length}\n\n`;
md += `## Summary\n- Changed elements: **${changed.length}**\n- Missing in replica: **${missing.length}**\n- Extra in replica: **${extra.length}**\n- Broken images (replica): **${brokenAssets.length}**\n- Console errors (replica): **${consoleErr.rep.length}**\n\n`;
if (origSnap.truncated || repSnap.truncated) md += `> ⚠️ element list truncated at 2500 (large page) — report may be partial.\n\n`;
md += `## Changed elements (style/text/asset roots first, layout cascade last)\n`;
if (!changed.length) md += `\n_none_\n`;
for (const c of changed.slice(0, 80)) {
  md += `\n### \`${c.path}\` (${c.tag})${c.text ? ` — "${esc(c.text).slice(0, 60)}"` : ''}\n\n| property | original | replica |\n|---|---|---|\n`;
  for (const d of c.diffs) md += `| ${d.prop} | ${esc(d.original).slice(0, 80)} | ${esc(d.replica).slice(0, 80)} |\n`;
}
if (changed.length > 80) md += `\n…and ${changed.length - 80} more (see inspection.json).\n`;
if (missing.length) { md += `\n## Missing in replica (present in original)\n`; for (const m of missing.slice(0, 40)) md += `- \`${m.path}\` (${m.tag})${m.text ? ` "${esc(m.text).slice(0, 50)}"` : ''}\n`; }
if (extra.length) { md += `\n## Extra in replica\n`; for (const e of extra.slice(0, 40)) md += `- \`${e.path}\` (${e.tag})${e.text ? ` "${esc(e.text).slice(0, 50)}"` : ''}\n`; }
if (brokenAssets.length) { md += `\n## Broken images (replica)\n`; for (const s of brokenAssets.slice(0, 40)) md += `- ${esc(s)}\n`; }
if (consoleErr.rep.length) { md += `\n## Console errors (replica)\n`; for (const e of consoleErr.rep.slice(0, 30)) md += `- ${esc(e)}\n`; }
writeFileSync(path.join(outDir, 'inspection.md'), md);
writeFileSync(path.join(outDir, 'inspection.json'), JSON.stringify({ viewport, origUrl, replica: replicaLabel, score: Number(score.toFixed(5)), pass: score <= threshold,
  summary: { changed: changed.length, missing: missing.length, extra: extra.length, brokenAssets: brokenAssets.length, consoleErrors: consoleErr.rep.length },
  changed, missing: missing.map((m) => ({ path: m.path, tag: m.tag, text: m.text })), extra: extra.map((e) => ({ path: e.path, tag: e.tag, text: e.text })), brokenAssets, consoleErrors: consoleErr.rep }, null, 2));
console.log(`inspect: score=${score.toFixed(5)} changed=${changed.length} missing=${missing.length} extra=${extra.length} brokenImg=${brokenAssets.length} consoleErr=${consoleErr.rep.length}`);
console.log(`-> ${outDir}/inspection.md , inspection.json , ${viewport}.{merged,diff,review}.png`);
