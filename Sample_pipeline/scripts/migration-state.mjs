#!/usr/bin/env node
// Shared, queue-authoritative migration state used by Plan, Ralph, and the control panel.
// Keeping these checks in one module prevents the UI from calling a pack/page complete when
// the shell runners would reject it.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { validateAssets } from './visual-diff/validate-assets.mjs';
import { validateDynamics } from './visual-diff/validate-dynamics.mjs';
import { loadEnv, requireResolvedHttpUrl, substituteEnv } from './env.mjs';

const PAGE_KEY = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
// The THEME FINGERPRINT: every gate verdict is bound to a hash of the theme files that existed when the
// gate ran, so editing the theme after a page passed invalidates that page's "done" until the gate is
// re-run. In this repo the product lives under theme/ (Shopify theme folders); the harness stays outside it.
const THEME_ROOTS = ['theme/assets', 'theme/blocks', 'theme/config', 'theme/layout', 'theme/locales', 'theme/sections', 'theme/snippets', 'theme/templates'];
const THEME_FILES = [];
const EXPECT_KEYS = new Set(['text', 'hrefEndsWith', 'count', 'minHeight', 'maxHeight', 'aspect']);

function validateExpectation(value, label, failures) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    failures.push(`${label} must be an object`);
    return;
  }
  const entries = Object.entries(value);
  if (!entries.length) failures.push(`${label} must contain at least one assertion`);
  for (const [key, expected] of entries) {
    if (!EXPECT_KEYS.has(key)) {
      failures.push(`${label}: unsupported expectation "${key}"`);
    } else if (['text', 'hrefEndsWith'].includes(key) && typeof expected !== 'string') {
      failures.push(`${label}.${key} must be a string`);
    } else if (!['text', 'hrefEndsWith'].includes(key) && !Number.isFinite(Number(expected))) {
      failures.push(`${label}.${key} must be numeric`);
    } else if (key === 'count' && (!Number.isInteger(Number(expected)) || Number(expected) < 0)) {
      failures.push(`${label}.count must be a non-negative integer`);
    } else if (['minHeight', 'maxHeight'].includes(key) && Number(expected) < 0) {
      failures.push(`${label}.${key} must be non-negative`);
    } else if (key === 'aspect' && Number(expected) <= 0) {
      failures.push(`${label}.aspect must be positive`);
    }
  }
}

export function requiredReportIds(contract) {
  const sections = Array.isArray(contract?.sections) ? contract.sections : [];
  const modes = [];
  if (sections.some((section) => section?.class !== 'overlay')) modes.push('normal');
  if (sections.some((section) => section?.class === 'overlay')) modes.push('overlay');
  return Object.keys(contract?.viewports || {}).flatMap((viewport) => modes.map((mode) => `${viewport}:${mode}`));
}

export function openBoxes(file) {
  if (!existsSync(file)) return 0;
  return readFileSync(file, 'utf8').split('\n').filter((line) => /^\s*- \[ \]/.test(line)).length;
}

export function readQueue(root = 'migrations') {
  const file = path.join(root, '_queue.tsv');
  const scopeFile = path.join(root, '_scope.json');
  const errors = [];
  const entries = [];
  if (!existsSync(file)) return { exists: false, file, entries, errors: [`missing route queue: ${file}`] };

  if (existsSync(scopeFile)) {
    try {
      const scope = JSON.parse(readFileSync(scopeFile, 'utf8'));
      if (!scope || typeof scope !== 'object' || Array.isArray(scope)) throw new Error('scope root must be an object');
      if (scope.queueHash && scope.queueHash !== sha256(readFileSync(file))) {
        errors.push(`route queue does not match the sealed inventory in ${scopeFile}`);
      }
    } catch (error) {
      errors.push(`invalid migration scope ${scopeFile}: ${error.message}`);
    }
  }

  const seen = new Set();
  for (const [index, raw] of readFileSync(file, 'utf8').split('\n').entries()) {
    const content = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
    const line = content.trim();
    if (!line || line.startsWith('#')) continue;
    const columns = content.split('\t');
    const [rawPage = '', rawSource = ''] = columns;
    const page = rawPage.trim();
    const source = rawSource.trim();
    if (columns.length !== 2) errors.push(`queue line ${index + 1}: expected exactly two tab-separated columns`);
    if (rawPage !== page || rawSource !== source) errors.push(`queue line ${index + 1}: surrounding whitespace is not allowed`);
    if (!PAGE_KEY.test(page)) errors.push(`queue line ${index + 1}: invalid page key "${page}"`);
    if (!source) errors.push(`queue line ${index + 1}: missing source for "${page || '(missing page)'}"`);
    if (seen.has(page)) errors.push(`queue line ${index + 1}: duplicate page key "${page}"`);
    seen.add(page);
    entries.push({ page, source, line: index + 1 });
  }
  if (!entries.length) errors.push(`route queue has no pages: ${file}`);
  return { exists: true, file, entries, errors };
}

export function validateContract(contractPath) {
  const failures = [];
  if (!existsSync(contractPath)) return { pass: false, failures: [`missing contract: ${contractPath}`] };
  let contract;
  try {
    contract = JSON.parse(readFileSync(contractPath, 'utf8'));
  } catch (error) {
    return { pass: false, failures: [`invalid contract JSON: ${error.message}`] };
  }

  if (!contract || typeof contract !== 'object' || Array.isArray(contract)) {
    return { pass: false, failures: ['contract root must be an object'] };
  }

  if (!contract.page || typeof contract.page !== 'string') failures.push('contract.page must be a non-empty string');
  if (!contract.source || typeof contract.source !== 'string') failures.push('contract.source must be a non-empty string');
  if (!contract.preview || typeof contract.preview !== 'string') failures.push('contract.preview must be a non-empty string');
  const viewportsValid = contract.viewports && typeof contract.viewports === 'object' && !Array.isArray(contract.viewports);
  if (!viewportsValid) failures.push('contract.viewports must be an object');
  const viewportEntries = viewportsValid ? Object.entries(contract.viewports) : [];
  const viewportNames = new Set(viewportEntries.map(([name]) => name));
  if (!viewportEntries.length) failures.push('contract.viewports must contain at least one viewport');
  for (const [name, width] of viewportEntries) {
    if (!name || !Number.isFinite(Number(width)) || Number(width) <= 0) failures.push(`viewport "${name}" must have a positive numeric width`);
  }

  if (!Array.isArray(contract.sections) || !contract.sections.length) {
    failures.push('contract.sections must contain at least one section');
  } else {
    const keys = new Set();
    for (const [index, section] of contract.sections.entries()) {
      const label = section?.key || `#${index + 1}`;
      if (!section?.key || typeof section.key !== 'string') failures.push(`section ${label}: key is required`);
      if (keys.has(section?.key)) failures.push(`section ${label}: duplicate key`);
      keys.add(section?.key);
      if (!['structural', 'content', 'overlay'].includes(section?.class)) failures.push(`section ${label}: invalid class`);
      if (!section?.sourceSelector || typeof section.sourceSelector !== 'string') failures.push(`section ${label}: sourceSelector is required`);
      if (!section?.replicaSelector || typeof section.replicaSelector !== 'string') failures.push(`section ${label}: replicaSelector is required`);
      if (!Array.isArray(section?.mustMatch)) failures.push(`section ${label}: mustMatch must be an array`);
      if (section?.pixelCeiling != null) {
        if (typeof section.pixelCeiling !== 'number' || !Number.isFinite(section.pixelCeiling) || section.pixelCeiling < 0 || section.pixelCeiling > 1) failures.push(`section ${label}: pixelCeiling must be a number between 0 and 1`);
        if (typeof section._pixelCeilingReason !== 'string' || !section._pixelCeilingReason.trim()) failures.push(`section ${label}: pixelCeiling requires _pixelCeilingReason`);
      }
      if (section?.boxCeiling != null) {
        if (typeof section.boxCeiling !== 'number' || !Number.isFinite(section.boxCeiling) || section.boxCeiling < 0) failures.push(`section ${label}: boxCeiling must be a non-negative number`);
        if (typeof section._boxCeilingReason !== 'string' || !section._boxCeilingReason.trim()) failures.push(`section ${label}: boxCeiling requires _boxCeilingReason`);
      }
      for (const [viewport] of viewportEntries) {
        const target = section?.targets?.[viewport];
        if (!target || typeof target !== 'object') failures.push(`section ${label}: missing measured target for ${viewport}`);
        else {
          for (const dimension of ['x', 'y', 'w', 'h']) {
            const n = Number(target.box?.[dimension]);
            if (!Number.isFinite(n) || (['w', 'h'].includes(dimension) && n <= 0)) {
              failures.push(`section ${label}: ${viewport} target must contain numeric box.x/box.y and positive box.w/box.h`);
              break;
            }
          }
          if (!target.styles || typeof target.styles !== 'object' || Array.isArray(target.styles) || !Object.keys(target.styles).length) {
            failures.push(`section ${label}: ${viewport} target.styles must be a non-empty object`);
          }
        }
      }
      if (section?.checks != null && !Array.isArray(section.checks)) {
        failures.push(`section ${label}: checks must be an array`);
      }
      for (const [checkIndex, check] of (Array.isArray(section?.checks) ? section.checks : []).entries()) {
        const checkLabel = `section ${label}: check #${checkIndex + 1}`;
        if (!check || typeof check !== 'object' || Array.isArray(check)) {
          failures.push(`${checkLabel} must be an object`);
          continue;
        }
        if (!check.selector || typeof check.selector !== 'string') failures.push(`${checkLabel}: selector is required`);
        const appliesTo = Array.isArray(check.viewports) ? check.viewports : [...viewportNames];
        if (check.viewports != null && !Array.isArray(check.viewports)) failures.push(`${checkLabel}: viewports must be an array`);
        if (!appliesTo.length) failures.push(`${checkLabel}: viewports must not be empty`);
        for (const viewport of appliesTo) {
          if (!viewportNames.has(viewport)) failures.push(`${checkLabel}: unknown viewport "${viewport}"`);
        }
        if (check.expect != null) validateExpectation(check.expect, `${checkLabel}.expect`, failures);
        if (check.expectByViewport != null) {
          if (!check.expectByViewport || typeof check.expectByViewport !== 'object' || Array.isArray(check.expectByViewport)) {
            failures.push(`${checkLabel}.expectByViewport must be an object`);
          } else {
            for (const [viewport, expectation] of Object.entries(check.expectByViewport)) {
              if (!viewportNames.has(viewport)) failures.push(`${checkLabel}: unknown expectByViewport key "${viewport}"`);
              validateExpectation(expectation, `${checkLabel}.expectByViewport.${viewport}`, failures);
            }
          }
        }
        for (const viewport of appliesTo) {
          if (check.expect == null && check.expectByViewport?.[viewport] == null) {
            failures.push(`${checkLabel}: missing expectation for viewport "${viewport}"`);
          }
        }
      }
    }
  }
  if (contract.capture != null && (!contract.capture || typeof contract.capture !== 'object' || Array.isArray(contract.capture))) {
    failures.push('contract.capture must be an object');
  } else {
    for (const key of ['deferredSelectors', 'deferredHosts']) {
      if (contract.capture?.[key] != null && (!Array.isArray(contract.capture[key]) || contract.capture[key].some((value) => typeof value !== 'string' || !value.trim()))) {
        failures.push(`contract.capture.${key} must be an array of non-empty strings`);
      }
    }
  }
  return { pass: failures.length === 0, failures, contract };
}

export function validatePack(dir, { expectedSource } = {}) {
  const contract = validateContract(path.join(dir, 'contract.json'));
  const hash = contract.pass ? contractHash(path.join(dir, 'contract.json')) : null;
  const expectedPage = path.basename(dir);
  const assets = validateAssets(path.join(dir, 'assets.json'), { expectedContractHash: hash, expectedPage });
  const dynamics = validateDynamics(path.join(dir, 'dynamics.json'), {
    interactionsPath: path.join(dir, 'interactions.md'), expectedContractHash: hash, expectedPage,
  });
  const failures = [
    ...contract.failures.map((failure) => `contract: ${failure}`),
    ...assets.failures.map((failure) => `assets: ${failure}`),
    ...dynamics.failures.map((failure) => `dynamics: ${failure}`),
  ];
  if (contract.contract?.page && contract.contract.page !== path.basename(dir)) {
    failures.push(`contract: page "${contract.contract.page}" does not match directory "${path.basename(dir)}"`);
  }
  if (expectedSource && contract.contract?.source !== expectedSource) {
    failures.push(`contract: source "${contract.contract?.source || ''}" does not match queued source "${expectedSource}"`);
  }
  return { pass: failures.length === 0, failures, contract: contract.contract };
}

export function contractHash(contractPath) {
  return sha256(readFileSync(contractPath));
}

export function themeFingerprint(root = process.cwd()) {
  const rows = [];
  const add = (absolute) => {
    if (!existsSync(absolute)) return;
    const stat = statSync(absolute);
    if (stat.isDirectory()) {
      for (const entry of readdirSync(absolute).sort()) add(path.join(absolute, entry));
    } else if (stat.isFile()) {
      rows.push(`${path.relative(root, absolute).split(path.sep).join('/')}\0${sha256(readFileSync(absolute))}`);
    }
  };
  for (const name of THEME_ROOTS) add(path.join(root, name));
  for (const name of THEME_FILES) add(path.join(root, name));
  return sha256(rows.join('\n'));
}

export function gateEvidence(contractPath, { cwd = process.cwd(), env = loadEnv(path.join(cwd, '.env')) } = {}) {
  const raw = readFileSync(contractPath);
  const contract = JSON.parse(raw);
  const contractDigest = sha256(raw);
  const themeHash = themeFingerprint(cwd);
  const preview = requireResolvedHttpUrl(substituteEnv(contract.preview, env), 'contract.preview');
  const identity = { preview };
  const evidenceHash = sha256(JSON.stringify({ contractHash: contractDigest, themeHash, identity }));
  return { contractHash: contractDigest, themeHash, evidenceHash, preview, identity };
}

export function pageGated(dir, { cwd = process.cwd() } = {}) {
  const contract = path.join(dir, 'contract.json');
  const gate = path.join(dir, 'gate.json');
  const final = path.join(dir, 'reports', 'final.md');
  const verify = path.join(dir, 'reports', 'visual-verify.md');
  if (![contract, gate, final, verify].every(existsSync)) return false;
  if (statSync(final).size === 0 || statSync(verify).size === 0) return false;
  try {
    const validated = validateContract(contract);
    if (!validated.pass) return false;
    const evidence = gateEvidence(contract, { cwd });
    const verdict = JSON.parse(readFileSync(gate, 'utf8'));
    if (verdict.version !== 2 || verdict.page !== path.basename(dir) || verdict.visualPass !== true || verdict.openDeltas !== 0 ||
      verdict.contractHash !== evidence.contractHash || verdict.themeHash !== evidence.themeHash ||
      verdict.evidenceHash !== evidence.evidenceHash || !Array.isArray(verdict.reports)) return false;
    const deltasPath = path.join(dir, 'visual-deltas.md');
    if (!existsSync(deltasPath) || verdict.deltaHash !== sha256(readFileSync(deltasPath))) return false;
    const reports = new Map(verdict.reports.map((report) => [report?.id, report]));
    const required = requiredReportIds(validated.contract);
    if (reports.size !== required.length || verdict.reports.length !== required.length) return false;
    for (const id of required) {
      const report = reports.get(id);
      if (!report || typeof report.file !== 'string' || !/^[a-z0-9.-]+\.section\.json$/i.test(report.file)) return false;
      const reportPath = path.join(dir, 'reports', report.file);
      if (!existsSync(reportPath) || sha256(readFileSync(reportPath)) !== report.sha256) return false;
      const data = JSON.parse(readFileSync(reportPath, 'utf8'));
      const [viewport, mode] = id.split(':');
      if (data.version !== 2 || data.contractHash !== evidence.contractHash || data.themeHash !== evidence.themeHash ||
        data.evidenceHash !== evidence.evidenceHash || data.viewport !== viewport || (data.mode || 'normal') !== mode ||
        data.overallPass !== true || !Array.isArray(data.sections) || !data.sections.length ||
        data.sections.some((section) => section?.pass !== true)) return false;
    }
    if (!validateAssets(path.join(dir, 'assets.json'), {
      checkPublic: true, cwd, expectedContractHash: evidence.contractHash, expectedPage: path.basename(dir),
    }).pass) return false;
    if (!validateDynamics(path.join(dir, 'dynamics.json'), {
      interactionsPath: path.join(dir, 'interactions.md'), expectedContractHash: evidence.contractHash, expectedPage: path.basename(dir),
    }).pass) return false;
    return true;
  } catch {
    return false;
  }
}

export function pageComplete(dir, { cwd = process.cwd() } = {}) {
  return existsSync(path.join(dir, 'visual-deltas.md'))
    && existsSync(path.join(dir, 'interactions.md'))
    && pageGated(dir, { cwd })
    && openBoxes(path.join(dir, 'visual-deltas.md')) === 0
    && openBoxes(path.join(dir, 'interactions.md')) === 0;
}

export function queuedPages(root = 'migrations') {
  const queue = readQueue(root);
  return { ...queue, pages: queue.entries.map((entry) => ({ ...entry, dir: path.join(root, entry.page) })) };
}

export function validatePlannedQueue(root = 'migrations') {
  const queue = queuedPages(root);
  const errors = [...queue.errors];
  for (const item of queue.pages) {
    const result = validatePack(item.dir, { expectedSource: item.source });
    if (!result.pass) errors.push(...result.failures.map((failure) => `${item.page}: ${failure}`));
  }
  return { pass: errors.length === 0, errors, entries: queue.entries };
}

export function remainingWork(root = 'migrations') {
  const queue = queuedPages(root);
  if (queue.errors.length) return { pass: false, errors: queue.errors, count: 0 };
  let count = 0;
  for (const item of queue.pages) {
    count += openBoxes(path.join(item.dir, 'visual-deltas.md'));
    count += openBoxes(path.join(item.dir, 'interactions.md'));
    if (!pageComplete(item.dir)) count += 1;
  }
  return { pass: true, errors: [], count };
}

export function activePage(root = 'migrations') {
  const queue = queuedPages(root);
  if (queue.errors.length) return { pass: false, errors: queue.errors, dir: null };
  const active = queue.pages.find((item) => !pageComplete(item.dir));
  return { pass: true, errors: [], dir: active?.dir || null };
}

export function packFingerprint(dir) {
  if (!existsSync(dir)) return 'missing';
  const rows = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const absolute = path.join(current, entry.name);
      const relative = path.relative(dir, absolute);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.isFile()) {
        const stat = statSync(absolute);
        if (/\.(json|md)$/i.test(entry.name)) rows.push(`${relative}\0${sha256(readFileSync(absolute))}`);
        else rows.push(`${relative}\0${stat.size}\0${stat.mtimeMs}`);
      }
    }
  };
  walk(dir);
  return sha256(rows.join('\n'));
}

function printErrors(errors) {
  for (const error of errors) console.error(`  - ${error}`);
}

function main() {
  const [command, target = 'migrations'] = process.argv.slice(2);
  if (command === 'queue') {
    const result = readQueue(target);
    if (result.errors.length) { console.error('queue validation failed'); printErrors(result.errors); process.exit(1); }
    console.log(JSON.stringify(result.entries));
    return;
  }
  if (command === 'pack') {
    const result = validatePack(target, { expectedSource: process.argv[4] });
    if (!result.pass) { console.error(`pack validation failed: ${target}`); printErrors(result.failures); process.exit(1); }
    console.log(`pack validation passed: ${target}`);
    return;
  }
  if (command === 'planned') {
    const result = validatePlannedQueue(target);
    if (!result.pass) { console.error('planning is incomplete'); printErrors(result.errors); process.exit(1); }
    console.log(`planning validation passed: ${result.entries.length} queued page(s)`);
    return;
  }
  if (command === 'remaining') {
    const result = remainingWork(target);
    if (!result.pass) { console.error('cannot calculate remaining work'); printErrors(result.errors); process.exit(1); }
    process.stdout.write(String(result.count));
    return;
  }
  if (command === 'active') {
    const result = activePage(target);
    if (!result.pass) { printErrors(result.errors); process.exit(1); }
    if (result.dir) process.stdout.write(result.dir);
    return;
  }
  if (command === 'fingerprint') {
    process.stdout.write(packFingerprint(target));
    return;
  }
  console.error('usage: migration-state.mjs <queue|pack|planned|remaining|active|fingerprint> [path]');
  process.exit(2);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
