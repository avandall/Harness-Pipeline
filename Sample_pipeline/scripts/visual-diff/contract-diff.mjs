// Selector-anchored visual gate. Pixel comparison uses the live source image; deterministic style
// and geometry assertions use the frozen targets captured in contract.json. Reports are bound to the
// contract, current theme tree, and resolved preview identity. A run invalidates gate.json before
// opening a browser, so an interrupted run can never leave an old PASS active.
//
// Usage: node scripts/visual-diff/contract-diff.mjs migrations/<page>/contract.json
//        [--viewport desktop|mobile|tablet|all] [--keep-overlays]
// Exit: 0 = the complete fresh gate is green; 1 = deltas/missing reports; 2 = invalid input.
import { launchChromium } from './launch.mjs';
import {
  loadEnv, requireResolvedHttpUrl, resolveSource, readyPage, measureSection, PROPS, VIEWPORT_DEFAULTS,
} from './lib.mjs';
import {
  gateEvidence, requiredReportIds, themeFingerprint, validateContract,
} from '../migration-state.mjs';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const flag = (name, fallback) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : fallback; };
const contractPath = argv.find((arg) => !arg.startsWith('--'));
if (!contractPath) {
  console.error('usage: contract-diff.mjs <contract.json> [--viewport ..] [--keep-overlays]');
  process.exit(2);
}

const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const atomicWrite = (file, value) => {
  const temp = `${file}.tmp-${process.pid}`;
  writeFileSync(temp, value);
  renameSync(temp, file);
};
const atomicJson = (file, value) => atomicWrite(file, `${JSON.stringify(value, null, 2)}\n`);
const baseDir = path.dirname(contractPath);
const reportsDir = path.join(baseDir, 'reports');
mkdirSync(reportsDir, { recursive: true });

let contractRaw = '';
let contract;
try {
  contractRaw = readFileSync(contractPath, 'utf8');
  contract = JSON.parse(contractRaw);
} catch (error) {
  atomicJson(path.join(baseDir, 'gate.json'), {
    version: 2, page: path.basename(baseDir), visualPass: false, openDeltas: 1,
    reason: `INVALID_CONTRACT: ${error.message}`, generatedAt: new Date().toISOString(),
  });
  console.error(`invalid contract: ${error.message}`);
  process.exit(2);
}

const contractHash = sha256(contractRaw);
const initialThemeHash = themeFingerprint();
const invalidateGate = (reason, extra = {}) => atomicJson(path.join(baseDir, 'gate.json'), {
  version: 2,
  page: contract.page || path.basename(baseDir),
  contractHash,
  themeHash: initialThemeHash,
  evidenceHash: null,
  generatedAt: new Date().toISOString(),
  requiredViewports: Object.keys(contract.viewports || {}),
  viewports: {},
  reports: [],
  openDeltas: 1,
  visualPass: false,
  reason,
  ...extra,
});
invalidateGate('RUNNING');
atomicWrite(path.join(baseDir, 'visual-deltas.md'), `# ${contract.page || path.basename(baseDir)} — visual deltas\n\n- [ ] gate — RUNNING_OR_INTERRUPTED\n`);

const contractValidation = validateContract(contractPath);
if (!contractValidation.pass) {
  invalidateGate('INVALID_CONTRACT');
  console.error('contract validation failed');
  for (const failure of contractValidation.failures) console.error(`  - ${failure}`);
  process.exit(2);
}

const env = loadEnv();
let evidence;
let sourceUrl;
try {
  evidence = gateEvidence(contractPath, { env });
  sourceUrl = requireResolvedHttpUrl(await resolveSource(contract, env), 'contract.source');
} catch (error) {
  invalidateGate(`INVALID_TARGET: ${error.message}`);
  console.error(error.message);
  process.exit(2);
}
const replicaUrl = evidence.preview;
const keepOverlays = argv.includes('--keep-overlays');
const inThisRun = (section) => (section.class === 'overlay') === keepOverlays;
if (!(contract.sections || []).some(inThisRun)) {
  invalidateGate(keepOverlays ? 'NO_OVERLAY_SECTIONS' : 'NO_NORMAL_SECTIONS', { evidenceHash: evidence.evidenceHash });
  console.error(`contract has no ${keepOverlays ? 'overlay' : 'normal'} sections to compare`);
  process.exit(2);
}

const CEILING = { structural: 0.02, overlay: 0.02, content: 0.025 };
const VPH = { desktop: 900, tablet: 1024, mobile: 844 };
const want = flag('--viewport', 'all');
const viewports = Object.entries(contract.viewports || VIEWPORT_DEFAULTS)
  .filter(([name]) => want === 'all' || want === name)
  .map(([name, width]) => ({ name, width: Number(width), height: VPH[name] || 900 }));
if (!viewports.length) {
  invalidateGate(`UNKNOWN_VIEWPORT: ${want}`, { evidenceHash: evidence.evidenceHash });
  console.error(`no matching viewport for "${want}"`);
  process.exit(2);
}

const norm = (value) => String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
const hasBackground = (value) => !!value && value !== 'none';
function styleDeltas(expected, actual) {
  const deltas = [];
  for (const property of PROPS) {
    if (property === 'background-image') continue;
    if (norm(expected[property]) !== norm(actual[property])) {
      deltas.push({ prop: property, source: norm(expected[property]), replica: norm(actual[property]) });
    }
  }
  if (hasBackground(expected['background-image']) !== hasBackground(actual['background-image'])) {
    deltas.push({
      prop: 'background-image',
      source: hasBackground(expected['background-image']) ? 'present' : 'none',
      replica: hasBackground(actual['background-image']) ? 'present' : 'none',
    });
  }
  return deltas;
}

function geometryDeltas(expected, actual, boxCeiling) {
  const deltas = [];
  const tolerance = Math.max(4, typeof boxCeiling === 'number' ? boxCeiling : 0);
  for (const dimension of ['x', 'y', 'w', 'h']) {
    if (Math.abs(Number(expected[dimension]) - Number(actual[dimension])) > tolerance) {
      deltas.push({
        prop: `box.${dimension}`,
        source: `${expected[dimension]}px`,
        replica: `${actual[dimension]}px`,
      });
    }
  }
  return deltas;
}

function CHILD_CHECKS(checks) {
  const out = [];
  for (const check of checks) {
    try {
      const elements = document.querySelectorAll(check.selector);
      const first = elements[0];
      const expected = check.expect || {};
      if (expected.count != null && elements.length !== expected.count) out.push({ selector: check.selector, prop: 'count', expect: expected.count, actual: elements.length });
      if (expected.text != null) {
        const text = (first ? first.textContent : '').replace(/\s+/g, ' ').trim();
        if (!text.includes(expected.text)) out.push({ selector: check.selector, prop: 'text', expect: expected.text, actual: text.slice(0, 60) });
      }
      if (expected.hrefEndsWith != null) {
        const href = first ? (first.getAttribute('href') || '') : '';
        if (!href.endsWith(expected.hrefEndsWith)) out.push({ selector: check.selector, prop: 'href', expect: `…${expected.hrefEndsWith}`, actual: href.slice(0, 60) });
      }
      if (first && (expected.minHeight != null || expected.maxHeight != null || expected.aspect != null)) {
        const rect = first.getBoundingClientRect();
        const height = Math.round(rect.height);
        if (expected.minHeight != null && height < expected.minHeight) out.push({ selector: check.selector, prop: 'minHeight', expect: expected.minHeight, actual: height });
        if (expected.maxHeight != null && height > expected.maxHeight) out.push({ selector: check.selector, prop: 'maxHeight', expect: expected.maxHeight, actual: height });
        if (expected.aspect != null && rect.height) {
          const aspect = +(rect.width / rect.height).toFixed(2);
          if (Math.abs(aspect - expected.aspect) > 0.05) out.push({ selector: check.selector, prop: 'aspect', expect: expected.aspect, actual: aspect });
        }
      }
    } catch (error) {
      out.push({ selector: check.selector, prop: 'evaluation', expect: 'successful evaluation', actual: error.message });
    }
  }
  return out;
}

function checksForViewport(section, viewport) {
  if (!Array.isArray(section.checks)) return [];
  return section.checks.flatMap((check) => {
    if (Array.isArray(check.viewports) && !check.viewports.includes(viewport)) return [];
    return [{ ...check, expect: check.expectByViewport?.[viewport] ?? check.expect }];
  });
}

const fit = (png, width, height) => {
  const output = new PNG({ width, height });
  output.data.fill(255);
  const copyWidth = Math.min(width, png.width);
  const copyHeight = Math.min(height, png.height);
  for (let y = 0; y < copyHeight; y++) for (let x = 0; x < copyWidth; x++) {
    const source = (y * png.width + x) * 4;
    const target = (y * width + x) * 4;
    for (let channel = 0; channel < 4; channel++) output.data[target + channel] = png.data[source + channel];
  }
  return output;
};

function pixelScore(sourceBuffer, replicaBuffer, diffPath) {
  const source = PNG.sync.read(sourceBuffer);
  const replica = PNG.sync.read(replicaBuffer);
  const width = Math.min(source.width, replica.width);
  const height = Math.max(source.height, replica.height, 1);
  const a = fit(source, width, height);
  const b = fit(replica, width, height);
  const diff = new PNG({ width, height });
  const mismatched = pixelmatch(a.data, b.data, diff.data, width, height, { threshold: 0.1 });
  writeFileSync(diffPath, PNG.sync.write(diff));
  return mismatched / (width * height);
}

async function snap(browser, url, viewport, selectorKey, runChecks) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height }, deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  await readyPage(page, url, env, {
    keepOverlays,
    deferredSelectors: contract.capture?.deferredSelectors || [],
  });
  const map = {};
  for (const section of contract.sections || []) {
    if (!inThisRun(section)) continue;
    const selector = section[selectorKey];
    const meta = await measureSection(page, selector);
    let png = null;
    let checks = [];
    if (meta?.visible) {
      try { png = await page.locator(selector).first().screenshot(); } catch {}
    }
    const activeChecks = checksForViewport(section, viewport.name);
    if (runChecks && activeChecks.length) {
      checks = await page.evaluate(CHILD_CHECKS, activeChecks).catch((error) => [{
        selector: '<checks>', prop: 'evaluation', expect: 'successful evaluation', actual: error.message,
      }]);
    }
    map[section.key] = { meta, png, checks, found: !!(meta?.visible && png) };
  }
  await context.close();
  return map;
}

const browser = await launchChromium();
try {
  for (const viewport of viewports) {
    const source = await snap(browser, sourceUrl, viewport, 'sourceSelector', false);
    const replica = await snap(browser, replicaUrl, viewport, 'replicaSelector', true);
    const results = [];
    for (const section of contract.sections || []) {
      if (!inThisRun(section)) continue;
      const live = source[section.key];
      const built = replica[section.key];
      if (!built.found) {
        results.push({ section: section.key, status: 'MISSING_IN_REPLICA', pass: false, deltas: [] });
        continue;
      }
      if (!live.found) {
        results.push({ section: section.key, status: 'SOURCE_SELECTOR_NOT_FOUND', pass: false, deltas: [], note: section.sourceSelector });
        continue;
      }
      const target = section.targets[viewport.name];
      const sourceDrift = [
        ...styleDeltas(target.styles, live.meta.styles),
        ...geometryDeltas(target.box, live.meta.box, section.boxCeiling),
      ];
      if (sourceDrift.length) {
        results.push({
          section: section.key,
          status: 'SOURCE_DRIFT_FROM_CAPTURE',
          pass: false,
          deltas: sourceDrift,
          note: `${sourceDrift.length} frozen-target delta(s); recapture intentionally or restore the source`,
        });
        continue;
      }
      const score = Number(pixelScore(live.png, built.png, path.join(reportsDir, `${section.key}.${viewport.name}.diff.png`)).toFixed(4));
      const ceiling = typeof section.pixelCeiling === 'number' ? section.pixelCeiling : (CEILING[section.class] ?? CEILING.content);
      const checkDeltas = built.checks.map((check) => ({
        prop: `check ${check.selector} ${check.prop}`, source: String(check.expect), replica: String(check.actual),
      }));
      const deltas = [
        ...styleDeltas(target.styles, built.meta.styles),
        ...geometryDeltas(target.box, built.meta.box, section.boxCeiling),
        ...checkDeltas,
      ];
      const pass = score <= ceiling && deltas.length === 0;
      results.push({
        section: section.key, class: section.class || 'content', score, ceiling, pass, deltas,
        mustMatch: section.mustMatch || [], baseline: 'contract.targets',
      });
    }
    const mode = keepOverlays ? 'overlay' : 'normal';
    const overallPass = results.length > 0 && results.every((result) => result.pass);
    const reportFile = `${viewport.name}${keepOverlays ? '.overlay' : ''}.section.json`;
    atomicJson(path.join(reportsDir, reportFile), {
      version: 2,
      contractHash: evidence.contractHash,
      themeHash: evidence.themeHash,
      evidenceHash: evidence.evidenceHash,
      generatedAt: new Date().toISOString(),
      viewport: viewport.name,
      mode,
      source: sourceUrl,
      replica: replicaUrl,
      overallPass,
      sections: results,
    });
    console.log(`\ncontract-diff [${viewport.name}${keepOverlays ? ' · overlay' : ''}] → ${overallPass ? 'PASS' : 'FAIL'}`);
    for (const result of results) {
      const detail = result.status || `score=${result.score} (≤${result.ceiling})${result.deltas.length ? ` · ${result.deltas.length} delta(s)` : ''}`;
      console.log(`  ${result.pass ? 'ok ' : 'XX '} ${String(result.section).padEnd(20)} ${detail}`);
    }
  }
} finally {
  await browser.close();
}

const freshReports = [];
for (const file of readdirSync(reportsDir).filter((name) => /\.section\.json$/.test(name))) {
  try {
    const report = JSON.parse(readFileSync(path.join(reportsDir, file), 'utf8'));
    if (report.version === 2 && report.evidenceHash === evidence.evidenceHash) freshReports.push({ ...report, file });
  } catch {}
}
const reportById = new Map(freshReports.map((report) => [`${report.viewport}:${report.mode || 'normal'}`, report]));
const requiredIds = requiredReportIds(contract);

let open = 0;
let markdown = `# ${contract.page || path.basename(baseDir)} — visual deltas\n`;
markdown += `_generated by contract-diff.mjs; fix code and rerun—do not hand-edit · evidence ${evidence.evidenceHash.slice(0, 12)}_\n`;
for (const id of requiredIds) {
  const [viewport, mode] = id.split(':');
  const report = reportById.get(id);
  markdown += `\n## ${viewport}${mode === 'overlay' ? ' (overlay)' : ''}\n`;
  if (!report) {
    markdown += `- [ ] gate — MISSING_OR_STALE_${mode.toUpperCase()}_REPORT\n`;
    open++;
    continue;
  }
  if (!Array.isArray(report.sections) || !report.sections.length) {
    markdown += '- [ ] gate — EMPTY_SECTION_REPORT\n';
    open++;
    continue;
  }
  const failures = report.sections.filter((section) => !section.pass);
  if (!failures.length) {
    markdown += '- [x] all sections within tolerance\n';
    continue;
  }
  for (const failure of failures) {
    if (failure.status) {
      markdown += `- [ ] ${failure.section} — ${failure.status}${failure.note ? ` (${failure.note})` : ''}\n`;
      open++;
      continue;
    }
    if (failure.score > failure.ceiling) {
      markdown += `- [ ] ${failure.section} — pixel ${failure.score} > ${failure.ceiling} ceiling\n`;
      open++;
    }
    for (const delta of failure.deltas || []) {
      markdown += `- [ ] ${failure.section} — ${delta.prop} ${delta.replica} vs target ${delta.source}\n`;
      open++;
    }
  }
}
atomicWrite(path.join(baseDir, 'visual-deltas.md'), markdown);

const viewportsStatus = {};
for (const viewport of Object.keys(contract.viewports || VIEWPORT_DEFAULTS)) {
  const ids = requiredIds.filter((id) => id.startsWith(`${viewport}:`));
  const modes = Object.fromEntries(ids.map((id) => {
    const mode = id.split(':')[1];
    const report = reportById.get(id);
    return [mode, !!(report?.overallPass && report.sections?.length)];
  }));
  viewportsStatus[viewport] = { ...modes, pass: ids.length > 0 && Object.values(modes).every(Boolean) };
}

const visualPass = requiredIds.length > 0 && open === 0 && requiredIds.every((id) => {
  const report = reportById.get(id);
  return report?.overallPass === true && report.sections?.length > 0;
});
const reportManifest = requiredIds.flatMap((id) => {
  const report = reportById.get(id);
  if (!report) return [];
  const bytes = readFileSync(path.join(reportsDir, report.file));
  return [{ id, file: report.file, sha256: sha256(bytes) }];
});
const deltaHash = sha256(readFileSync(path.join(baseDir, 'visual-deltas.md')));
atomicJson(path.join(baseDir, 'gate.json'), {
  version: 2,
  page: contract.page || path.basename(baseDir),
  contractHash: evidence.contractHash,
  themeHash: evidence.themeHash,
  evidenceHash: evidence.evidenceHash,
  preview: evidence.preview,
  generatedAt: new Date().toISOString(),
  requiredViewports: Object.keys(contract.viewports || VIEWPORT_DEFAULTS),
  viewports: viewportsStatus,
  reports: reportManifest,
  deltaHash,
  openDeltas: open,
  visualPass,
});

console.log(`\nvisual-deltas.md → ${open} open · gate.json visualPass=${visualPass} · reports → ${reportsDir}/`);
process.exit(visualPass ? 0 : 1);
