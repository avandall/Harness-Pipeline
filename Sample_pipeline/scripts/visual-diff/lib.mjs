// Shared helpers for the visual contract harness (capture-source.mjs, contract-diff.mjs).
// Keeps the password-gate handshake, overlay dismissal, motion-freeze, lazy-scroll, the curated
// computed-style list, and the .env parser in ONE place so the harness scripts behave identically.
export { loadEnv, substituteEnv, unresolvedEnv, requireResolvedHttpUrl } from '../env.mjs';

// Resolve contract.source to a loadable URL. A "__REF__" source points at a LOCAL reference build
// (a provided HTML/CSS/JS folder used as the 1:1 migration source of truth) served by
// serve-reference.mjs — we idempotently ensure that server is up and substitute its base URL, so the
// rest of the harness loads the reference exactly like a live site. Any other source (a live http(s)
// URL) is returned unchanged. Async because it may need to spawn the static server.
export async function resolveSource(contract, env) {
  const raw = (contract && contract.source) || '';
  if (!raw.includes('__REF__')) return raw;
  const { ensureReferenceServer } = await import('./serve-reference.mjs');
  const base = await ensureReferenceServer(env);
  return raw.replace(/__REF__/g, base);
}

export const isShopifyHost = (url, env) =>
  /\.myshopify\.com/i.test(url) || (env.SHOPIFY_STORE && url.includes(env.SHOPIFY_STORE)) ||
  (env.SHOPIFY_PRIMARY_DOMAIN && url.includes(env.SHOPIFY_PRIMARY_DOMAIN));

// The fidelity-relevant computed styles a 1:1 migration must reproduce (section-root level).
export const PROPS = ['font-family', 'font-size', 'font-weight', 'font-style', 'line-height', 'letter-spacing',
  'text-align', 'text-transform', 'color', 'background-color', 'background-image', 'border-top-width',
  'border-bottom-width', 'border-radius', 'margin-top', 'margin-bottom', 'padding-top', 'padding-right',
  'padding-bottom', 'padding-left', 'width', 'height', 'max-width', 'display', 'flex-direction',
  'justify-content', 'align-items', 'gap', 'position', 'aspect-ratio', 'object-fit', 'opacity'];

// Clear the Shopify storefront password gate. A password-protected store 302s every public URL to
// /password; Dawn renders the form inside a collapsed <details> ("Enter using password"), other themes
// show the field inline. We try the known toggles, then the field by SELECTOR (never by URL), and fall
// back to submitting the form from page context. Host-gated (never type the password into a SOURCE
// site's form) + fully wrapped so a gate change can never crash a run. Preview themes share the gate:
// once the password cookie is set, `?preview_theme_id=` renders the unpublished theme normally.
export async function clearGate(page, url, env) {
  if (!env.STOREFRONT_PASSWORD || !isShopifyHost(url, env)) return;
  try {
    const trigger = page.locator('summary.modal__toggle, summary.password-modal__trigger, summary:has-text("Enter using password"), summary:has-text("Login with password")').first();
    if (await trigger.count().catch(() => 0)) await trigger.click().catch(() => {});
    const pw = page.locator('#Password, input[name="password"]').first();
    if (!(await pw.count().catch(() => 0))) return;
    const visible = await pw.waitFor({ state: 'visible', timeout: 8000 }).then(() => true).catch(() => false);
    if (visible) {
      await pw.fill(env.STOREFRONT_PASSWORD);
      await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle', timeout: 60000 }).catch(() => {}), pw.press('Enter')]);
    } else {
      // Field present but hidden (theme-specific markup): submit the password form from page context.
      await page.evaluate((password) => {
        const input = document.querySelector('#Password, input[name="password"]');
        const form = input && input.closest('form');
        if (!input || !form) return;
        input.value = password;
        form.submit();
      }, env.STOREFRONT_PASSWORD).catch(() => {});
      await page.waitForLoadState('networkidle', { timeout: 60000 }).catch(() => {});
    }
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 }).catch(() => {});
  } catch (e) { console.error('warning: storefront gate not cleared —', e.message); }
}

// Dismiss a full-screen age-gate / "enter site" overlay so it doesn't cover the page under test.
export async function dismissOverlays(page) {
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('button,a')].find((x) =>
      /enter\s*(the\s*)?(site|website)|^i am|^yes/i.test((x.textContent || '').trim()));
    if (el) el.click();
  }).catch(() => {});
}

// Hide only widgets explicitly declared by this migration. A persistent stylesheet catches widgets
// injected after initial load. Shopify's theme-preview bar (the iframe it injects when you view an
// unpublished theme via ?preview_theme_id=) is platform chrome and is hidden only on a Shopify host;
// no source-brand selector is baked into the shared harness.
export async function hideDeferredWidgets(page, selectors = [], { hidePreviewBanner = false } = {}) {
  await page.evaluate(({ configured, previewBanner }) => {
    try {
      if (!configured.length && !previewBanner) return;
      const id = 'vd-hide-deferred';
      if (document.getElementById(id)) return;
      const st = document.createElement('style');
      st.id = id;
      const selectors = [...configured, ...(previewBanner ? ['#preview-bar-iframe', '#PBarNextFrameWrapper', '.shopify-preview-bar', '[class*="password-module" i]'] : [])];
      st.textContent = selectors.map((selector) => `:where(${selector}):not(html):not(body)`).join(',') +
        '{display:none !important;visibility:hidden !important;}';
      (document.head || document.documentElement).appendChild(st);
    } catch (e) {}
  }, { configured: selectors, previewBanner: hidePreviewBanner }).catch(() => {});
}

// Scroll through to trigger lazy content, then return to top (so coords line up across sites).
export async function lazyScroll(page) {
  await page.evaluate(async () => {
    await new Promise((r) => { let y = 0; const s = setInterval(() => { window.scrollBy(0, 800); y += 800; if (y >= document.body.scrollHeight) { clearInterval(s); r(); } }, 50); });
  }).catch(() => {});
  await page.waitForTimeout(400);
  await page.evaluate(() => window.scrollTo(0, 0)).catch(() => {});
  try { await page.evaluate(() => document.fonts && document.fonts.ready); } catch { /* noop */ }
}

// Freeze motion: pause videos at frame 0 + kill animations/transitions, so a static capture is
// deterministic (a playing hero would otherwise inflate every diff). Runs in the page.
export async function freezeMotion(page) {
  await page.evaluate(() => {
    try { document.querySelectorAll('video').forEach((v) => { try { v.pause(); v.autoplay = false; v.removeAttribute('autoplay'); v.currentTime = 0; } catch (e) {} }); } catch (e) {}
    try { const s = document.createElement('style'); s.textContent = '*,*::before,*::after{animation:none !important;transition:none !important;animation-duration:0s !important;animation-delay:0s !important;scroll-behavior:auto !important;caret-color:transparent !important}'; document.documentElement.appendChild(s); } catch (e) {}
  }).catch(() => {});
  await page.waitForTimeout(250);
}

// Load a page ready for capture: goto → settle → clear gate → (dismiss overlays) → hide deferred
// widgets → lazy-scroll → freeze. opts.keepOverlays=true SKIPS the age-gate dismissal — used to
// capture/diff an overlay-class section (e.g. a full-screen age-gate), which must stay PRESENT to be
// measured. Contract-declared deferred widgets are hidden in both modes.
export async function readyPage(page, url, env, opts = {}) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await clearGate(page, url, env);
  if (!opts.keepOverlays) await dismissOverlays(page);
  const invalidDeferred = await page.evaluate((selectors) => {
    for (const selector of selectors) {
      try { document.querySelector(selector); } catch (error) { return `${selector}: ${error.message}`; }
    }
    return null;
  }, opts.deferredSelectors || []);
  if (invalidDeferred) throw new Error(`invalid contract.capture.deferredSelector ${invalidDeferred}`);
  await hideDeferredWidgets(page, opts.deferredSelectors || [], { hidePreviewBanner: isShopifyHost(url, env) });
  await page.waitForTimeout(500);
  await lazyScroll(page);
  await freezeMotion(page);
}

// Measure one section root: bounding box (rounded) + curated computed styles. Returns null if absent.
export async function measureSection(page, selector) {
  return page.evaluate(({ sel, props }) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el); const styles = {};
    for (const p of props) styles[p] = cs.getPropertyValue(p);
    return {
      box: { x: Math.round(r.left + scrollX), y: Math.round(r.top + scrollY), w: Math.round(r.width), h: Math.round(r.height) },
      styles,
      visible: r.width > 1 && r.height > 1,
    };
  }, { sel: selector, props: PROPS }).catch(() => null);
}

export const VIEWPORT_DEFAULTS = { desktop: 1440, tablet: 768, mobile: 390 };
