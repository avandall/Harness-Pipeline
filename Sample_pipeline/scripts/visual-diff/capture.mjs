// Capture a full-page screenshot of a URL at a given viewport, scrolling to
// trigger lazy-loaded content first. WHY: visual QA needs both the source and
// the new Shopify page captured identically (same viewport, same scroll) so
// compare.mjs can place them side by side and pixel-diff them.
//
// Storefront password gate: a fresh browser hitting a Shopify preview sees an
// "Opening soon"/password splash instead of the real page (docs/troubleshooting.md
// says don't anonymous-fetch a gated store). So when the target is a Shopify host
// and STOREFRONT_PASSWORD is set in .env, we submit it first, then re-fetch the page.
//
// Usage: node scripts/visual-diff/capture.mjs <url> <label> <desktop|mobile|WIDTHxHEIGHT>
// Output: scripts/visual-diff/out/<label>/<viewport>.png
//
// Requires: npm i -D playwright   (then: npx playwright install chromium)
import { launchChromium } from './launch.mjs';
import { loadEnv } from '../env.mjs';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const [, , url, label = 'capture', viewport = 'desktop'] = process.argv;
if (!url) {
  console.error('usage: node capture.mjs <url> <label> <desktop|mobile|WIDTHxHEIGHT>');
  process.exit(1);
}
const PRESETS = { desktop: { width: 1440, height: 900 }, mobile: { width: 390, height: 844 } };
const vp = PRESETS[viewport] ?? (() => { const [w, h] = viewport.split('x').map(Number); return { width: w, height: h || 900 }; })();

const env = loadEnv();
const { STOREFRONT_PASSWORD, SHOPIFY_STORE, SHOPIFY_PRIMARY_DOMAIN } = env;

const outDir = path.join('scripts', 'visual-diff', 'out', label);
mkdirSync(outDir, { recursive: true });

const browser = await launchChromium();
try {
  const page = await browser.newPage({ viewport: vp, deviceScaleFactor: 1 });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });

  // Clear the Shopify storefront password gate if present. The store redirects a gated
  // preview to /password, where the password field sits inside a COLLAPSED <details>
  // ("Login with password") — so we open that toggle first, then fill + submit. Host-gated
  // (never type the password into a source-site form) and fully wrapped: a gate change must
  // never crash the capture — on failure we log and screenshot whatever rendered.
  // The gate redirects to /password where the `#Password` field is HIDDEN inside a
  // collapsed <details> whose <summary class="password-modal__trigger"> reads "Login with
  // password" — click that trigger FIRST, then wait for the field to be visible before filling
  // (an old `/\/password/` url-guard + a too-tight timing also worked by luck elsewhere; this is
  // the verified flow). Host-gated; never type the password into a source-site form.
  const isShopifyHost = /\.myshopify\.com/i.test(url)
    || (SHOPIFY_STORE && url.includes(SHOPIFY_STORE))
    || (SHOPIFY_PRIMARY_DOMAIN && url.includes(SHOPIFY_PRIMARY_DOMAIN));
  if (STOREFRONT_PASSWORD && isShopifyHost) {
    const trigger = page.locator('summary.modal__toggle, summary.password-modal__trigger, summary:has-text("Enter using password"), summary:has-text("Login with password")').first();
    if (await trigger.count().catch(() => 0)) await trigger.click().catch(() => {});   // reveal the password form
    const pw = page.locator('#Password, input[name="password"]').first();
    if (await pw.count().catch(() => 0)) {
      try {
        await pw.waitFor({ state: 'visible', timeout: 8000 });            // bounded wait, not fill's 30s hang
        await pw.fill(STOREFRONT_PASSWORD);
        await Promise.all([
          page.waitForNavigation({ waitUntil: 'networkidle', timeout: 60000 }).catch(() => {}),
          pw.press('Enter'),
        ]);
        await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 }).catch(() => {}); // re-fetch, now authed
      } catch (e) {
        console.error('warning: storefront password gate not cleared —', e.message);
      }
    }
  }

  // scroll through the page so lazy images/sections render, then return to top
  await page.evaluate(async () => {
    await new Promise((resolve) => {
      let y = 0;
      const step = setInterval(() => {
        window.scrollBy(0, 800); y += 800;
        if (y >= document.body.scrollHeight) { clearInterval(step); resolve(); }
      }, 100);
    });
  });
  await page.waitForTimeout(500);
  await page.evaluate(() => window.scrollTo(0, 0));

  const file = path.join(outDir, `${viewport}.png`);
  await page.screenshot({ path: file, fullPage: true });
  console.log('saved', file);
} finally {
  await browser.close();   // ALWAYS close — even if capture throws above — so no zombie Chromium leaks
}
