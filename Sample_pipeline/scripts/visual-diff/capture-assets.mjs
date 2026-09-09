// CAPTURE exact source assets for one migration page.
//
// Reads migrations/<page>/contract.json, opens the live source at every contract viewport,
// walks each source section, extracts rendered image/video/background/font/svg assets,
// downloads or serializes them into migrations/<page>/source/assets/, and writes a
// tracked migrations/<page>/assets.json register with SHA-256 hashes. HTTP(S) assets
// are immediately re-fetched and byte-compared so "captured" means exact source bytes,
// not a guessed replacement.
//
// Usage: node scripts/visual-diff/capture-assets.mjs migrations/<page>/contract.json
// Exit: 0 = all discovered assets captured and verified; 1 = missing/failed assets; 2 = bad args.
import { launchChromium } from './launch.mjs';
import { loadEnv, requireResolvedHttpUrl, resolveSource, readyPage, VIEWPORT_DEFAULTS } from './lib.mjs';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const contractPath = argv.find((a) => !a.startsWith('--'));
if (!contractPath) {
  console.error('usage: capture-assets.mjs <contract.json> [--viewport desktop|mobile|tablet|all]');
  process.exit(2);
}

const env = loadEnv();
const contractRaw = readFileSync(contractPath, 'utf8');
const contract = JSON.parse(contractRaw);
const contractHash = createHash('sha256').update(contractRaw).digest('hex');
const baseDir = path.dirname(contractPath);
const sourceDir = path.join(baseDir, 'source');
const assetDir = path.join(sourceDir, 'assets');
mkdirSync(assetDir, { recursive: true });

const VPH = { desktop: 900, tablet: 1024, mobile: 844 };
const want = flag('--viewport', 'all');
const viewports = Object.entries(contract.viewports || VIEWPORT_DEFAULTS)
  .filter(([name]) => want === 'all' || want === name)
  .map(([name, width]) => ({ name, width: Number(width), height: VPH[name] || 900 }));
if (!viewports.length) { console.error(`no matching viewport for "${want}" in contract`); process.exit(2); }

if (!contract.source) { console.error('contract.source is required'); process.exit(2); }
const SRC = requireResolvedHttpUrl(await resolveSource(contract, env), 'contract.source');

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const slug = (s) => String(s || 'asset').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80) || 'asset';
const posixRel = (from, to) => path.relative(from, to).split(path.sep).join('/');
const extFromContentType = (ct = '') => {
  const t = ct.split(';')[0].trim().toLowerCase();
  return ({
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/svg+xml': 'svg',
    'image/avif': 'avif',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'font/woff': 'woff',
    'font/woff2': 'woff2',
    'application/font-woff': 'woff',
    'application/font-woff2': 'woff2',
  })[t] || '';
};
const extFromUrl = (url = '') => {
  try {
    const ext = path.extname(new URL(url).pathname).replace(/^\./, '').toLowerCase();
    return /^[a-z0-9]{2,5}$/.test(ext) ? ext : '';
  } catch { return ''; }
};
const extFromBytes = (buffer) => {
  if (buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'jpg';
  if (buffer.subarray(0, 6).toString('ascii').startsWith('GIF8')) return 'gif';
  if (buffer.subarray(0, 4).toString('ascii') === 'RIFF' && buffer.subarray(8, 12).toString('ascii') === 'WEBP') return 'webp';
  if (buffer.subarray(0, 4).toString('ascii') === 'wOFF') return 'woff';
  if (buffer.subarray(0, 4).toString('ascii') === 'wOF2') return 'woff2';
  if (buffer.subarray(4, 8).toString('ascii') === 'ftyp') return 'mp4';
  if (/^\s*<svg[\s>]/i.test(buffer.subarray(0, 512).toString('utf8'))) return 'svg';
  return '';
};
const kindFrom = (item, contentType = '') => {
  const type = contentType.toLowerCase();
  if (item.kind === 'font' || type.includes('font') || /\.(woff2?|ttf|otf)(\?|$)/i.test(item.sourceUrl || '')) return 'font';
  if (item.kind === 'video' || type.startsWith('video/') || /\.(mp4|webm|mov|m4v)(\?|$)/i.test(item.sourceUrl || '')) return 'video';
  if (item.kind === 'svg' || type.includes('svg') || /\.svg(\?|$)/i.test(item.sourceUrl || '')) return 'svg';
  return 'image';
};

function addAsset(map, raw) {
  if (!raw) return;
  const key = raw.sourceType === 'inline'
    ? `inline:${sha256(Buffer.from(raw.content || ''))}`
    : `url:${raw.sourceUrl || raw.content || ''}`;
  if (!key.endsWith(':')) {
    const existing = map.get(key);
    const discovery = {
      section: raw.section,
      viewport: raw.viewport,
      mode: raw.mode,
      selector: raw.selector,
      tag: raw.tag,
      attr: raw.attr,
      sourceSelector: raw.sourceSelector,
    };
    if (existing) {
      existing.discovered.push(discovery);
      existing.sections = [...new Set([...existing.sections, raw.section])];
      return;
    }
    map.set(key, {
      sourceType: raw.sourceType || 'url',
      sourceUrl: raw.sourceUrl || null,
      content: raw.content || null,
      kind: raw.kind || 'image',
      sections: [raw.section],
      discovered: [discovery],
    });
  }
}

const EXTRACT_ASSETS = ({ sections, mode, viewport, skipSelectors, skipHosts }) => {
  // Third-party DEFER-to-app embeds (e.g. store locators, marketing forms, chat/cart widgets) inject their
  // own control glyphs/icons (often inline data: SVGs). The theme never ships those bytes — it leaves a
  // mount hook — so they must NOT enter the asset register or they show up as un-fetchable failures.
  // Skip any node inside such a subtree (but never the section root itself).
  const skipSel = (skipSelectors || []).join(',');
  const abs = (u) => {
    if (!u) return '';
    try { return new URL(u, document.baseURI).href; } catch { return u; }
  };
  const cssUrls = (v) => {
    const out = [];
    const re = /url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/g;
    let m;
    while ((m = re.exec(v || ''))) {
      const u = (m[1] || m[2] || m[3] || '').trim();
      if (u) out.push(abs(u));
    }
    return out;
  };
  const srcsetUrls = (v) => String(v || '').split(',').map((part) => abs(part.trim().split(/\s+/)[0])).filter(Boolean);
  const domPath = (el) => {
    const parts = [];
    for (let n = el; n && n.nodeType === 1 && parts.length < 5; n = n.parentElement) {
      let p = n.tagName.toLowerCase();
      if (n.id) p += `#${n.id}`;
      else if (n.className && typeof n.className === 'string') p += `.${n.className.trim().split(/\s+/).slice(0, 2).join('.')}`;
      parts.unshift(p);
    }
    return parts.join(' > ');
  };
  const assetKind = (tag, attr) => {
    if (tag === 'video' || (tag === 'source' && /video/i.test(attr))) return 'video';
    if (tag === 'svg') return 'svg';
    return 'image';
  };
  const pushUrl = (items, base, sourceUrl, attr, kind) => {
    if (!sourceUrl) return;
    const sourceType = sourceUrl.startsWith('data:') ? 'data' : sourceUrl.startsWith('blob:') ? 'blob' : 'url';
    items.push({ ...base, sourceType, sourceUrl, attr, kind: kind || assetKind(base.tag, attr) });
  };

  const items = [];
  const sectionList = sections || [];
  for (const s of sectionList) {
    if ((s.class === 'overlay') !== (mode === 'overlay')) continue;
    const root = document.querySelector(s.sourceSelector);
    if (!root) {
      items.push({ section: s.key, sourceSelector: s.sourceSelector, viewport, mode, missingSection: true });
      continue;
    }
    const nodes = [root, ...root.querySelectorAll('*')];
    for (const el of nodes) {
      if (skipSel && el !== root && el.closest(skipSel)) continue;
      const tag = el.tagName.toLowerCase();
      const base = { section: s.key, sourceSelector: s.sourceSelector, viewport, mode, selector: domPath(el), tag };

      if (tag === 'img') {
        pushUrl(items, base, abs(el.currentSrc || el.src), 'currentSrc', 'image');
        for (const u of srcsetUrls(el.getAttribute('srcset'))) pushUrl(items, base, u, 'srcset', 'image');
      }
      if (tag === 'video') {
        pushUrl(items, base, abs(el.currentSrc || el.src), 'currentSrc', 'video');
        pushUrl(items, base, abs(el.getAttribute('poster')), 'poster', 'image');
      }
      if (tag === 'source') {
        const type = el.getAttribute('type') || '';
        pushUrl(items, { ...base, attr: type }, abs(el.getAttribute('src')), `src ${type}`, /video/i.test(type) ? 'video' : 'image');
        for (const u of srcsetUrls(el.getAttribute('srcset'))) pushUrl(items, base, u, `srcset ${type}`, /video/i.test(type) ? 'video' : 'image');
      }
      if (tag === 'svg') {
        items.push({ ...base, sourceType: 'inline', content: el.outerHTML, attr: 'inline-svg', kind: 'svg' });
      }

      for (const pseudo of [null, '::before', '::after']) {
        const cs = getComputedStyle(el, pseudo);
        const suffix = pseudo || 'element';
        for (const prop of ['backgroundImage', 'maskImage', 'webkitMaskImage', 'borderImageSource', 'listStyleImage']) {
          for (const u of cssUrls(cs[prop])) pushUrl(items, base, u, `${suffix}.${prop}`, 'image');
        }
      }
    }
  }

  for (const e of performance.getEntriesByType('resource')) {
    if (!['img', 'video', 'audio', 'font'].includes(e.initiatorType)) continue;
    let resourceHost = '';
    try { resourceHost = new URL(e.name, document.baseURI).hostname; } catch {}
    if ((skipHosts || []).some((host) => {
      const expected = String(host).toLowerCase();
      return resourceHost === expected || resourceHost.endsWith(`.${expected}`);
    })) continue;
    pushUrl(items, {
      section: '__page_resource__',
      sourceSelector: '__performance__',
      viewport,
      mode,
      selector: 'performance.resource',
      tag: e.initiatorType,
    }, abs(e.name), e.initiatorType, e.initiatorType === 'font' ? 'font' : e.initiatorType === 'video' ? 'video' : 'image');
  }
  return items;
};

async function fetchBytes(url) {
  const res = await fetch(url, {
    headers: {
      'user-agent': 'Mozilla/5.0 (compatible; harness-migration-asset-capture/1.0)',
      'referer': SRC,
    },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return { buffer: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type') || '' };
}

async function materialize(asset, index) {
  let buffer;
  let contentType = '';
  let verification = { method: 'sha256', exact: false };

  if (asset.sourceType === 'inline') {
    buffer = Buffer.from(asset.content || '', 'utf8');
    contentType = 'image/svg+xml';
    verification = { method: 'inline-sha256', exact: true };
  } else if (asset.sourceType === 'data') {
    const m = String(asset.sourceUrl || '').match(/^data:([^;,]+)?(;base64)?,(.*)$/);
    if (!m) throw new Error('invalid data URL');
    contentType = m[1] || 'application/octet-stream';
    buffer = m[2] ? Buffer.from(m[3], 'base64') : Buffer.from(decodeURIComponent(m[3]), 'utf8');
    verification = { method: 'data-url-sha256', exact: true };
  } else if (asset.sourceType === 'blob') {
    throw new Error('blob URL cannot be fetched outside the source browser; replace with the underlying source URL');
  } else {
    const first = await fetchBytes(asset.sourceUrl);
    buffer = first.buffer;
    contentType = first.contentType;
    const hash1 = sha256(buffer);
    const second = await fetchBytes(asset.sourceUrl);
    const hash2 = sha256(second.buffer);
    verification = { method: 'refetch-sha256', first: hash1, second: hash2, exact: hash1 === hash2 };
    if (!verification.exact) throw new Error(`refetch hash mismatch (${hash1.slice(0, 8)} != ${hash2.slice(0, 8)})`);
  }

  const hash = sha256(buffer);
  const kind = kindFrom(asset, contentType);
  const ext = extFromContentType(contentType) || extFromUrl(asset.sourceUrl) || extFromBytes(buffer);
  if (!ext) throw new Error('asset type could not be identified from Content-Type, URL, or bytes');
  let sourceName = 'inline';
  if (/^https?:/i.test(asset.sourceUrl || '')) {
    try { sourceName = slug(path.basename(new URL(asset.sourceUrl).pathname, path.extname(new URL(asset.sourceUrl).pathname))); }
    catch { sourceName = 'remote'; }
  }
  const sectionName = slug(asset.sections.find((s) => s !== '__page_resource__') || 'page');
  const file = `${sectionName}-${kind}-${sourceName || index}-${hash.slice(0, 10)}.${ext}`;
  const absLocal = path.join(assetDir, file);
  writeFileSync(absLocal, buffer);
  // Shopify themes keep EVERY static file (images, SVG, video posters, fonts, CSS, JS) in one flat
  // `assets/` folder and reference it by bare filename: {{ 'file.webp' | asset_url }}. So the
  // destination is theme/assets/<file> and the Liquid reference is just <file> (no sub-folder).
  const publicDir = 'theme/assets';

  return {
    ...asset,
    id: `asset-${String(index).padStart(3, '0')}`,
    kind,
    status: asset.sourceType === 'inline' ? 'inline' : 'downloaded',
    contentType,
    bytes: buffer.length,
    sha256: hash,
    verifiedExact: verification.exact === true,
    verification,
    localPath: posixRel(baseDir, absLocal),
    publicPath: `${publicDir}/${file}`,
    publicAssetUrl: file,
  };
}

const assets = new Map();
const failures = [];
const browser = await launchChromium();
try {
  const hasOverlay = (contract.sections || []).some((s) => s.class === 'overlay');
  const modes = hasOverlay ? ['normal', 'overlay'] : ['normal'];
  for (const mode of modes) {
    for (const vp of viewports) {
      const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
      const page = await ctx.newPage();
      await readyPage(page, SRC, env, {
        keepOverlays: mode === 'overlay', deferredSelectors: contract.capture?.deferredSelectors || [],
      });
      const found = await page.evaluate(EXTRACT_ASSETS, {
        sections: contract.sections || [],
        mode,
        viewport: vp.name,
        // Per-migration: CSS selectors whose SUBTREES are DEFER-to-app embeds (third-party widgets the
        // theme mounts but never ships assets for). Nodes inside these are skipped so their injected
        // control glyphs don't register as un-fetchable asset failures. Empty for a fresh theme;
        // populate per site, e.g.:
        //   '[data-third-party-widget]', 'iframe[src*="widgets.example" i]',
        skipSelectors: contract.capture?.deferredSelectors || [],
        skipHosts: contract.capture?.deferredHosts || [],
      });
      for (const item of found) {
        if (item.missingSection) {
          failures.push({ section: item.section, viewport: item.viewport, mode: item.mode, error: `sourceSelector not found: ${item.sourceSelector}` });
        } else {
          addAsset(assets, item);
        }
      }
      await ctx.close();
      console.log(`asset scan @ ${vp.name}${mode === 'overlay' ? ' overlay' : ''}: ${found.length} candidate(s)`);
    }
  }
} finally { await browser.close(); }

const materialized = [];
let i = 0;
for (const asset of assets.values()) {
  i += 1;
  try {
    materialized.push(await materialize(asset, i));
  } catch (e) {
    failures.push({
      sourceUrl: asset.sourceUrl,
      sourceType: asset.sourceType,
      sections: asset.sections,
      discovered: asset.discovered,
      error: e.message,
    });
  }
}

materialized.sort((a, b) => a.id.localeCompare(b.id));
const register = {
  page: contract.page || path.basename(baseDir),
  contractHash,
  source: SRC,
  generatedAt: new Date().toISOString(),
  exactness: 'sha256 byte-for-byte against the rendered source asset URL at capture time',
  assetPass: failures.length === 0,
  summary: {
    discovered: assets.size,
    captured: materialized.length,
    failed: failures.length,
    byKind: materialized.reduce((acc, a) => { acc[a.kind] = (acc[a.kind] || 0) + 1; return acc; }, {}),
  },
  assets: materialized.map(({ content, ...a }) => a),
  failures,
};
writeFileSync(path.join(baseDir, 'assets.json'), `${JSON.stringify(register, null, 2)}\n`);

console.log(`\nassets.json → ${materialized.length} captured · ${failures.length} failed`);
console.log(`source assets → ${assetDir}/`);
if (failures.length) {
  console.log('\nFAILED ASSETS:');
  for (const f of failures) console.log(`  - ${f.sourceUrl || f.section || '(unknown)'} — ${f.error}`);
  process.exit(1);
}
console.log('✅ all discovered assets captured and byte-verified.');
