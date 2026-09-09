// CAPTURE dynamic source behaviour for one migration page.
//
// Static section screenshots do not prove first-load overlays, popups, third-party
// widgets, hover menus, videos, forms, or animations. This script opens the live
// source at each contract viewport, records raw first-load state, after primary
// overlay dismissal, and after third-party popup dismissal, then writes a tracked
// migrations/<page>/dynamics.json inventory. PLAN must classify every
// mustClassify item in interactions.md with [dyn:<id>].
//
// Usage: node scripts/visual-diff/capture-dynamics.mjs migrations/<page>/contract.json
// Exit: 0 = inventory written; 1 = scan failed; 2 = bad args.
import { launchChromium } from './launch.mjs';
import { clearGate, dismissOverlays, lazyScroll, loadEnv, requireResolvedHttpUrl, resolveSource, VIEWPORT_DEFAULTS } from './lib.mjs';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const flag = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 ? argv[i + 1] : d;
};
const contractPath = argv.find((a) => !a.startsWith('--'));
if (!contractPath) {
  console.error('usage: capture-dynamics.mjs <contract.json> [--viewport desktop|mobile|tablet|all]');
  process.exit(2);
}

const env = loadEnv();
const contractRaw = readFileSync(contractPath, 'utf8');
const contract = JSON.parse(contractRaw);
const contractHash = createHash('sha256').update(contractRaw).digest('hex');
const baseDir = path.dirname(contractPath);
mkdirSync(baseDir, { recursive: true });

const VPH = { desktop: 900, tablet: 1024, mobile: 844 };
const want = flag('--viewport', 'all');
const viewports = Object.entries(contract.viewports || VIEWPORT_DEFAULTS)
  .filter(([name]) => want === 'all' || want === name)
  .map(([name, width]) => ({ name, width: Number(width), height: VPH[name] || 900 }));
if (!viewports.length) {
  console.error(`no matching viewport for "${want}" in contract`);
  process.exit(2);
}
if (!contract.source) {
  console.error('contract.source is required');
  process.exit(2);
}
const SRC = requireResolvedHttpUrl(await resolveSource(contract, env), 'contract.source');

const slug = (value) => String(value || '')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-|-$/g, '')
  .slice(0, 56) || 'item';

const sourceHost = (() => {
  try { return new URL(SRC).hostname; } catch { return ''; }
})();

const hostOf = (url) => {
  try { return new URL(url, SRC).hostname; } catch { return ''; }
};

async function settleForInventory(page) {
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(900);
  await lazyScroll(page);
  await page.waitForTimeout(300);
}

async function dismissPrimaryOverlays(page) {
  await dismissOverlays(page);
  for (const re of [/enter\s*(the\s*)?(site|website)/i, /^i am/i, /^yes/i]) {
    const loc = page.locator('button,a,[role="button"]').filter({ hasText: re }).first();
    if (await loc.count().catch(() => 0)) {
      await loc.click({ timeout: 2000, force: true }).catch(() => {});
    }
  }
}

async function dismissThirdPartyPopups(page) {
  for (const re of [/no,?\s*thanks/i, /close\s*dialog/i, /^close$/i, /^x$/i, /^×$/]) {
    const loc = page.locator('button,a,[role="button"]').filter({ hasText: re }).first();
    if (await loc.count().catch(() => 0)) {
      await loc.click({ timeout: 2000 }).catch(() => {});
    }
  }
  await page.evaluate(() => {
    const visible = (el) => {
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      return r.width > 2 && r.height > 2 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
    };
    const patterns = [
      /no,?\s*thanks/i,
      /close\s*dialog/i,
      /^close$/i,
      /^x$/i,
      /^×$/,
    ];
    for (const el of [...document.querySelectorAll('button,a,[role="button"]')]) {
      const label = `${el.textContent || ''} ${el.getAttribute('aria-label') || ''}`.trim();
      if (visible(el) && patterns.some((re) => re.test(label))) {
        try { el.click(); } catch (e) {}
      }
    }
  }).catch(() => {});
}

const SCAN_PAGE = ({ sections, viewport, state, sourceHost }) => {
  const norm = (s) => String(s || '').replace(/\s+/g, ' ').trim();
  const roundRect = (r) => ({
    x: Math.round(r.x),
    y: Math.round(r.y),
    w: Math.round(r.width),
    h: Math.round(r.height),
  });
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
  };
  const cssPath = (el) => {
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return `#${CSS.escape(el.id)}`;
    const parts = [];
    for (let node = el; node && node.nodeType === 1 && node !== document; node = node.parentElement) {
      let part = node.tagName.toLowerCase();
      if (node.id) {
        part += `#${CSS.escape(node.id)}`;
        parts.unshift(part);
        break;
      }
      const parent = node.parentElement;
      if (parent) {
        const same = [...parent.children].filter((child) => child.tagName === node.tagName);
        if (same.length > 1) part += `:nth-of-type(${same.indexOf(node) + 1})`;
      }
      parts.unshift(part);
      if (part === 'body') break;
    }
    return parts.join(' > ');
  };
  const shortText = (el, n = 220) => norm(el.innerText || el.textContent || '').slice(0, n);
  const attrs = (el) => {
    const out = {};
    for (const name of ['id', 'class', 'role', 'aria-haspopup', 'aria-expanded', 'aria-modal', 'data-w-id', 'data-wf-element-id', 'data-wf-page', 'data-wf-site']) {
      const v = el.getAttribute(name);
      if (v) out[name] = v;
    }
    return out;
  };
  const cssUrls = (v) => {
    const out = [];
    const re = /url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/g;
    let m;
    while ((m = re.exec(v || ''))) {
      const u = (m[1] || m[2] || m[3] || '').trim();
      if (!u || u === 'none') continue;
      try { out.push(new URL(u, document.baseURI).href); } catch { out.push(u); }
    }
    return out;
  };
  const itemBase = (el) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return {
      selector: cssPath(el),
      tag: el.tagName.toLowerCase(),
      text: shortText(el),
      rect: roundRect(r),
      position: cs.position,
      zIndex: cs.zIndex,
      display: cs.display,
      visibility: cs.visibility,
      opacity: cs.opacity,
      attrs: attrs(el),
    };
  };

  const all = [...document.querySelectorAll('body *')].filter(visible);
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  const sectionsOut = (sections || []).map((s) => {
    const el = document.querySelector(s.sourceSelector);
    if (!el) return { key: s.key, sourceSelector: s.sourceSelector, missing: true };
    return {
      key: s.key,
      class: s.class || 'content',
      sourceSelector: s.sourceSelector,
      text: shortText(el),
      rect: roundRect(el.getBoundingClientRect()),
    };
  });

  const overlays = all
    .map((el) => {
      const base = itemBase(el);
      const z = Number.parseInt(base.zIndex, 10);
      const fullish = base.rect.w >= vw * 0.75 && base.rect.h >= vh * 0.45;
      const classText = `${base.attrs.class || ''} ${base.attrs.id || ''} ${base.attrs.role || ''}`;
      const overlayish = /modal|popup|overlay|dialog|drawer|cart|backdrop|age|popover|toast|sheet/i.test(classText);
      if (base.position !== 'fixed' && base.position !== 'sticky' && !overlayish && !(Number.isFinite(z) && z >= 100)) return null;
      if (!overlayish && !fullish && base.rect.w < 40 && base.rect.h < 40) return null;
      return base;
    })
    .filter(Boolean)
    .filter((item, index, arr) => {
      if (!item.text && item.rect.w < vw * 0.5 && item.rect.h < vh * 0.5) return true;
      return !arr.slice(0, index).some((prev) =>
        prev.text === item.text &&
        Math.abs(prev.rect.x - item.rect.x) <= 2 &&
        Math.abs(prev.rect.y - item.rect.y) <= 2 &&
        Math.abs(prev.rect.w - item.rect.w) <= 2 &&
        Math.abs(prev.rect.h - item.rect.h) <= 2);
    })
    .slice(0, 40);

  const forms = all
    .filter((el) => /^(form|input|select|textarea|button)$/i.test(el.tagName) || el.getAttribute('role') === 'button')
    .map((el) => ({
      ...itemBase(el),
      name: el.getAttribute('name') || '',
      type: el.getAttribute('type') || '',
      placeholder: el.getAttribute('placeholder') || '',
      action: el.getAttribute('action') || '',
      href: el.getAttribute('href') || '',
    }))
    .slice(0, 80);

  const media = [...document.querySelectorAll('img,video,source,picture,svg')]
    .filter((el) => el.tagName.toLowerCase() === 'source' || visible(el))
    .map((el) => ({
      selector: cssPath(el),
      tag: el.tagName.toLowerCase(),
      src: el.currentSrc || el.src || el.getAttribute('src') || '',
      poster: el.getAttribute('poster') || '',
      alt: el.getAttribute('alt') || '',
      type: el.getAttribute('type') || '',
      rect: visible(el) ? roundRect(el.getBoundingClientRect()) : null,
    }))
    .slice(0, 120);

  const backgrounds = all
    .flatMap((el) => {
      const cs = getComputedStyle(el);
      const urls = [...cssUrls(cs.backgroundImage), ...cssUrls(cs.maskImage), ...cssUrls(cs.webkitMaskImage)];
      if (!urls.length) return [];
      return [{
        ...itemBase(el),
        urls,
        backgroundSize: cs.backgroundSize,
        backgroundPosition: cs.backgroundPosition,
        backgroundRepeat: cs.backgroundRepeat,
      }];
    })
    .slice(0, 80);

  const iframes = [...document.querySelectorAll('iframe')]
    .map((el) => ({
      ...itemBase(el),
      src: el.getAttribute('src') || '',
      title: el.getAttribute('title') || '',
      host: (() => { try { return new URL(el.src).hostname; } catch { return ''; } })(),
    }))
    .slice(0, 50);

  const scripts = [...document.querySelectorAll('script[src]')]
    .map((el) => {
      const src = el.src || el.getAttribute('src') || '';
      return { src, host: (() => { try { return new URL(src).hostname; } catch { return ''; } })() };
    })
    .slice(0, 150);

  const resources = performance.getEntriesByType('resource')
    .map((e) => ({
      name: e.name,
      host: (() => { try { return new URL(e.name).hostname; } catch { return ''; } })(),
      initiatorType: e.initiatorType,
      transferSize: Math.round(e.transferSize || 0),
    }))
    .filter((e) => e.host)
    .slice(0, 300);

  const motion = all
    .map((el) => {
      const base = itemBase(el);
      const cs = getComputedStyle(el);
      const dataAttrs = Object.fromEntries([...el.attributes]
        .filter((a) => /^data-w-|^data-animation|^data-aos|^data-swiper/i.test(a.name))
        .map((a) => [a.name, a.value]));
      const classText = `${base.attrs.class || ''} ${base.tag}`;
      const durationText = `${cs.animationDuration} ${cs.transitionDuration}`;
      const hasDuration = !/^0s(?:,\s*0s)* 0s(?:,\s*0s)*$/.test(durationText);
      const motionish = cs.animationName !== 'none' ||
        cs.transitionProperty !== 'all' ||
        hasDuration ||
        Object.keys(dataAttrs).length ||
        /video|slider|carousel|marquee|swiper|dropdown|w-backgroundvideo/i.test(classText);
      if (!motionish) return null;
      return {
        ...base,
        animationName: cs.animationName,
        animationDuration: cs.animationDuration,
        transitionProperty: cs.transitionProperty,
        transitionDuration: cs.transitionDuration,
        transform: cs.transform,
        dataAttrs,
      };
    })
    .filter(Boolean)
    .slice(0, 100);

  const hoverCandidates = all
    .filter((el) => {
      const tag = el.tagName.toLowerCase();
      const c = el.getAttribute('class') || '';
      return tag === 'a' || tag === 'button' || el.getAttribute('role') === 'button' ||
        el.getAttribute('aria-haspopup') || /dropdown|menu|nav|button|link|teaser|cart/i.test(c);
    })
    .map((el) => ({
      ...itemBase(el),
      href: el.href || el.getAttribute('href') || '',
      ariaHaspopup: el.getAttribute('aria-haspopup') || '',
      ariaExpanded: el.getAttribute('aria-expanded') || '',
    }))
    .slice(0, 120);

  const hosts = [...new Set([...scripts.map((s) => s.host), ...resources.map((r) => r.host)]
    .filter((h) => h && h !== sourceHost))].sort();

  return {
    viewport,
    state,
    url: location.href,
    title: document.title,
    viewportSize: { width: vw, height: vh },
    scrollHeight: document.documentElement.scrollHeight,
    sections: sectionsOut,
    overlays,
    forms,
    media,
    backgrounds,
    iframes,
    scripts,
    resources,
    thirdPartyHosts: hosts,
    motion,
    hoverCandidates,
    storage: {
      localStorage: Object.keys(localStorage || {}).sort(),
      sessionStorage: Object.keys(sessionStorage || {}).sort(),
    },
  };
};

const HOVER_SCAN = async (page, scan) => {
  await page.addStyleTag({
    content: '#modal,.modal-backdrop,.needsclick,[role="dialog"]{pointer-events:none!important;}',
  }).catch(() => {});
  const candidates = (scan.hoverCandidates || [])
    .filter((item) => {
      const blob = `${item.text} ${item.attrs?.class || ''} ${item.ariaHaspopup || ''}`;
      return !!item.ariaHaspopup || /dropdown|menu|popover|flyout|submenu|drawer/i.test(blob);
    })
    .slice(0, 25);
  const baseline = await page.evaluate(() => [...document.querySelectorAll('a,button,[role="menu"],[role="menuitem"],[role="button"],nav')]
    .filter((el) => {
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      return r.width > 1 && r.height > 1 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
    })
    .map((el) => `${el.tagName.toLowerCase()}|${(el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()}|${el.getAttribute('href') || ''}`));
  const baseSet = new Set(baseline);
  const out = [];
  for (const item of candidates) {
    try {
      await page.locator(item.selector).first().hover({ timeout: 1500 });
      await page.waitForTimeout(250);
      const after = await page.evaluate(() => [...document.querySelectorAll('a,button,[role="menu"],[role="menuitem"],[role="button"],nav,.w-dropdown-list,[class*="dropdown"],[class*="menu"]')]
        .filter((el) => {
          const r = el.getBoundingClientRect();
          const cs = getComputedStyle(el);
          return r.width > 1 && r.height > 1 && cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0';
        })
        .map((el) => ({
          tag: el.tagName.toLowerCase(),
          text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 140),
          href: el.getAttribute('href') || '',
          className: el.getAttribute('class') || '',
          rect: (() => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }; })(),
        })));
      const revealed = after.filter((el) => !baseSet.has(`${el.tag}|${el.text}|${el.href}`));
      out.push({ candidate: item, revealed: revealed.slice(0, 20) });
    } catch (e) {
      out.push({ candidate: item, error: e.message });
    }
  }
  return out;
};

function titleFor(category, item) {
  const text = String(item.text || item.host || item.src || item.selector || '').trim();
  const blob = `${text} ${item.attrs?.class || ''} ${item.selector || ''} ${item.src || ''}`;
  if (category === 'third-party') {
    return `third-party host ${item.host || hostOf(item.src) || 'unknown'}`;
  }
  if (category === 'form') {
    if (/21\s*years|enter\s*website|age|#modal|modal-backdrop/i.test(blob)) return 'age gate entry';
    const descriptor = item.placeholder || item.name || item.type || text;
    return `form control: ${String(descriptor || item.tag || 'input').slice(0, 48)}`;
  }
  if (/21\s*years|enter\s*website|age/i.test(blob)) return 'age gate';
  if (category === 'overlay') return `overlay: ${(text || item.attrs?.role || item.attrs?.id || item.attrs?.class || item.selector).slice(0, 48)}`;
  if (category === 'hover') return `reveal control: ${(text || item.ariaHaspopup || item.attrs?.class || item.selector).slice(0, 48)}`;
  if (category === 'motion') return `motion: ${(text || item.attrs?.class || item.tag || item.selector).slice(0, 48)}`;
  return text.slice(0, 48) || `${category} item`;
}

function addMust(items, category, item, state, reason) {
  const title = titleFor(category, item);
  const key = `${category}|${title}|${item.selector || item.host || item.src || ''}`;
  if (!items.has(key)) {
    items.set(key, {
      key,
      category,
      title,
      states: [],
      reason,
      evidence: [],
    });
  }
  const entry = items.get(key);
  if (!entry.states.includes(state)) entry.states.push(state);
  entry.evidence.push({
    state,
    viewport: item.viewport,
    selector: item.selector || '',
    text: item.text || '',
    host: item.host || '',
    src: item.src || item.name || '',
    rect: item.rect || null,
  });
}

function buildMustClassify(scans, hoverReveals) {
  const items = new Map();
  for (const scan of scans) {
    for (const item of scan.overlays || []) {
      const blob = `${item.text || ''} ${item.attrs?.class || ''} ${item.attrs?.id || ''}`;
      const semantic = item.attrs?.role === 'dialog' || item.attrs?.['aria-modal'] || /modal|popup|overlay|dialog|drawer|backdrop|age/i.test(blob);
      const fullish = item.rect?.w >= scan.viewportSize.width * 0.65 && item.rect?.h >= scan.viewportSize.height * 0.35;
      if (!semantic && !fullish) continue;
      addMust(items, 'overlay', { ...item, viewport: scan.viewport }, scan.state, 'visible fixed/sticky layer or modal state');
    }
    for (const item of scan.forms || []) {
      const blob = `${item.text || ''} ${item.placeholder || ''} ${item.type || ''} ${item.name || ''} ${item.attrs?.class || ''}`;
      if (!/form|input|textarea|select/i.test(item.tag) && !/enter website|sign me up|no,?\s*thanks|find sips/i.test(blob)) continue;
      addMust(items, 'form', { ...item, viewport: scan.viewport }, scan.state, 'user input or submit flow');
    }
    for (const item of scan.iframes || []) {
      addMust(items, 'third-party', { ...item, viewport: scan.viewport, host: item.host || hostOf(item.src) }, scan.state, 'embedded third-party frame');
    }
    for (const host of scan.thirdPartyHosts || []) {
      if (!host || host === sourceHost) continue;
      if (/^(ajax\.googleapis\.com|fonts\.googleapis\.com|cdn\.prod\.website-files\.com|d3e54v103j8qbb\.cloudfront\.net)$/i.test(host)) continue;
      addMust(items, 'third-party', { host, viewport: scan.viewport }, scan.state, 'external script/resource host loaded by the source');
    }
    for (const item of scan.motion || []) {
      const blob = `${item.text || ''} ${item.attrs?.class || ''} ${JSON.stringify(item.dataAttrs || {})}`;
      if (!/video|dropdown|carousel|slider|marquee|data-w-id|backgroundvideo|fade|animate|transition/i.test(blob) && item.animationName === 'none') continue;
      addMust(items, 'motion', { ...item, viewport: scan.viewport }, scan.state, 'animation, video, Webflow interaction, or transition-driven UI');
    }
    for (const item of scan.hoverCandidates || []) {
      const blob = `${item.text || ''} ${item.attrs?.class || ''} ${item.ariaHaspopup || ''}`;
      if (!item.ariaHaspopup && !/dropdown|menu|popover|flyout|submenu|drawer/i.test(blob)) continue;
      addMust(items, 'hover', { ...item, viewport: scan.viewport }, scan.state, 'hover/click candidate that can reveal UI or change state');
    }
  }
  for (const item of hoverReveals) {
    if ((item.revealed || []).length) {
      addMust(items, 'hover', { ...item.candidate, viewport: item.viewport }, item.state, 'hover revealed additional visible UI');
    }
  }

  return [...items.values()]
    .sort((a, b) => `${a.category}|${a.title}|${a.key}`.localeCompare(`${b.category}|${b.title}|${b.key}`))
    .map((item, index) => {
      const { key, ...rest } = item;
      return {
        id: `dyn-${String(index + 1).padStart(3, '0')}`,
        ...rest,
        suggestedInteractionLine: `- [ ] [dyn:dyn-${String(index + 1).padStart(3, '0')}] ${rest.title} - REBUILD -> tests/<name>.test.js`,
      };
    });
}

const scans = [];
const hoverReveals = [];
const failures = [];
const browser = await launchChromium();
try {
  for (const vp of viewports) {
    const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    try {
      await page.goto(SRC, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await clearGate(page, SRC, env);
      await settleForInventory(page);
      const first = await page.evaluate(SCAN_PAGE, {
        sections: contract.sections || [],
        viewport: vp.name,
        state: 'first-load',
        sourceHost,
      });
      scans.push(first);

      await dismissPrimaryOverlays(page);
      await settleForInventory(page);
      const primaryDismissed = await page.evaluate(SCAN_PAGE, {
        sections: contract.sections || [],
        viewport: vp.name,
        state: 'after-primary-dismiss',
        sourceHost,
      });
      scans.push(primaryDismissed);

      await dismissThirdPartyPopups(page);
      await settleForInventory(page);
      const thirdPartyDismissed = await page.evaluate(SCAN_PAGE, {
        sections: contract.sections || [],
        viewport: vp.name,
        state: 'after-third-party-dismiss',
        sourceHost,
      });
      scans.push(thirdPartyDismissed);

      const reveals = await HOVER_SCAN(page, thirdPartyDismissed);
      for (const reveal of reveals) hoverReveals.push({ ...reveal, viewport: vp.name, state: 'after-third-party-dismiss' });
      console.log(`dynamic scan @ ${vp.name}: ${scans.filter((s) => s.viewport === vp.name).length} state(s), ${reveals.length} hover probe(s)`);
    } catch (e) {
      failures.push({ viewport: vp.name, error: e.message });
    } finally {
      await ctx.close();
    }
  }
} finally {
  await browser.close();
}

const mustClassify = buildMustClassify(scans, hoverReveals);
const summary = {
  viewports: viewports.map((v) => v.name),
  scans: scans.length,
  overlays: scans.reduce((n, s) => n + (s.overlays || []).length, 0),
  forms: scans.reduce((n, s) => n + (s.forms || []).length, 0),
  iframes: scans.reduce((n, s) => n + (s.iframes || []).length, 0),
  thirdPartyHosts: [...new Set(scans.flatMap((s) => s.thirdPartyHosts || []))].sort(),
  motionItems: scans.reduce((n, s) => n + (s.motion || []).length, 0),
  hoverCandidates: scans.reduce((n, s) => n + (s.hoverCandidates || []).length, 0),
  hoverProbes: hoverReveals.length,
  mustClassify: mustClassify.length,
};

const out = {
  page: contract.page || path.basename(baseDir),
  contractHash,
  source: SRC,
  generatedAt: new Date().toISOString(),
  dynamicsPass: failures.length === 0,
  rule: 'Every mustClassify item must appear in interactions.md as [dyn:<id>] with REBUILD, DEFER-to-app, or DROP.',
  summary,
  mustClassify,
  scans,
  hoverReveals,
  failures,
};

writeFileSync(path.join(baseDir, 'dynamics.json'), `${JSON.stringify(out, null, 2)}\n`);
console.log(`\ndynamics.json -> ${summary.mustClassify} required classification(s)`);
console.log(`third-party hosts -> ${summary.thirdPartyHosts.join(', ') || '(none)'}`);
if (failures.length) {
  console.error(`dynamic capture failed (${failures.length})`);
  for (const f of failures) console.error(`  - ${f.viewport}: ${f.error}`);
  process.exit(1);
}
console.log('dynamic inventory captured.');
