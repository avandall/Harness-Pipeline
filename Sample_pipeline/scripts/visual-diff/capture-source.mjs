// CAPTURE the live source for one page → fills the contract's per-viewport `targets` and saves the
// reference evidence pack. This makes the SOURCE the source of truth: the exact box + computed styles
// the replica must hit, recorded once, per section, per viewport. See docs/contract-and-evidence.md.
//
// For each viewport in the contract it: loads the source (clears any password gate, dismisses the
// age-gate, scrolls to trigger lazy content, freezes motion), takes a full-page screenshot, then for
// each section screenshots the element BY ITS sourceSelector (drift-proof) and measures its box +
// curated computed styles. It writes those measurements back into contract.json as `targets`.
//
// Usage:  node scripts/visual-diff/capture-source.mjs migrations/<page>/contract.json [--viewport desktop|mobile|all]
// Output: migrations/<page>/source/{<vp>.full.png, sections/<key>.<vp>.png, styles.json, console.json}
//         + contract.json updated in place with targets.
// Requires: Node >= 21 + playwright + pngjs (nvm use 22).
import { launchChromium } from './launch.mjs';
import { loadEnv, requireResolvedHttpUrl, resolveSource, readyPage, measureSection, VIEWPORT_DEFAULTS } from './lib.mjs';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const contractPath = argv.find((a) => !a.startsWith('--'));
if (!contractPath) { console.error('usage: capture-source.mjs <contract.json> [--viewport desktop|mobile|tablet|all]'); process.exit(2); }

const env = loadEnv();
const contract = JSON.parse(readFileSync(contractPath, 'utf8'));
const baseDir = path.dirname(contractPath);
const srcDir = path.join(baseDir, 'source');
const secDir = path.join(srcDir, 'sections');
mkdirSync(secDir, { recursive: true });

const keepOverlays = argv.includes('--keep-overlays');   // capture overlay-class sections (age-gate) WITH the overlay present
const VPH = { desktop: 900, tablet: 1024, mobile: 844 };
const want = flag('--viewport', 'all');
const viewports = Object.entries(contract.viewports || VIEWPORT_DEFAULTS)
  .filter(([name]) => want === 'all' || want === name)
  .map(([name, width]) => ({ name, width: Number(width), height: VPH[name] || 900 }));
if (!viewports.length) { console.error(`no matching viewport for "${want}" in contract`); process.exit(2); }

const SRC = requireResolvedHttpUrl(await resolveSource(contract, env), 'contract.source');

const consoleErr = [];
const missing = [];
const browser = await launchChromium();
try {
  for (const vp of viewports) {
    const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.on('console', (m) => { if (m.type() === 'error') consoleErr.push(`[${vp.name}] ${m.text().slice(0, 200)}`); });
    await readyPage(page, SRC, env, { keepOverlays, deferredSelectors: contract.capture?.deferredSelectors || [] });

    await page.screenshot({ path: path.join(srcDir, `${vp.name}${keepOverlays ? '.overlay' : ''}.full.png`), fullPage: true });

    for (const s of contract.sections || []) {
      // Overlay-class sections are measured only in --keep-overlays mode (the overlay covers the page);
      // every other section is measured only in the normal mode (with the overlay dismissed).
      if ((s.class === 'overlay') !== keepOverlays) continue;
      const meta = await measureSection(page, s.sourceSelector);
      s.targets = s.targets || {};
      if (!meta || !meta.visible) {
        s.targets[vp.name] = null;
        missing.push(`${s.key}@${vp.name} (selector: ${s.sourceSelector})`);
        continue;
      }
      s.targets[vp.name] = { box: meta.box, styles: meta.styles };
      try { await page.locator(s.sourceSelector).first().screenshot({ path: path.join(secDir, `${s.key}.${vp.name}.png`) }); }
      catch (e) { console.error(`  warn: could not screenshot ${s.key}@${vp.name} — ${e.message}`); }
    }
    await ctx.close();
    console.log(`captured source @ ${vp.name} (${vp.width}px): ${(contract.sections || []).length} sections`);
  }
} finally { await browser.close(); }

writeFileSync(contractPath, JSON.stringify(contract, null, 2));
writeFileSync(path.join(srcDir, 'styles.json'), JSON.stringify(
  Object.fromEntries((contract.sections || []).map((s) => [s.key, s.targets])), null, 2));
writeFileSync(path.join(srcDir, 'console.json'), JSON.stringify(consoleErr, null, 2));

console.log(`\ncontract targets filled → ${contractPath}`);
console.log(`source reference → ${srcDir}/`);
if (missing.length) {
  console.log(`\n⚠️ ${missing.length} section(s) NOT found on the source — fix the sourceSelector in the contract and re-run:`);
  for (const m of missing) console.log('  -', m);
  process.exit(1);
}
console.log('✅ all sections measured.');
