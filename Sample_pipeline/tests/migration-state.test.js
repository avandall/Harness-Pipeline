import { test, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  contractHash, gateEvidence, pageGated, requiredReportIds, validateContract, validatePack,
} from '../scripts/migration-state.mjs';
import { loadEnv, parseEnv, substituteEnv } from '../scripts/env.mjs';

const sha = (value) => createHash('sha256').update(value).digest('hex');
const target = { box: { x: 0, y: 0, w: 1200, h: 600 }, styles: { display: 'block' } };

function contractFor(page = 'home') {
  return {
    page,
    source: 'https://source.example/',
    preview: 'https://preview.example/',
    viewports: { desktop: 1200 },
    sections: [{
      key: 'main', class: 'content', sourceSelector: 'main', replicaSelector: 'main',
      mustMatch: ['geometry'], targets: { desktop: structuredClone(target) },
    }],
  };
}

function makePack() {
  const root = mkdtempSync(path.join(tmpdir(), 'state-'));
  const dir = path.join(root, 'migrations', 'home');
  mkdirSync(path.join(dir, 'reports'), { recursive: true });
  mkdirSync(path.join(dir, 'source', 'assets'), { recursive: true });
  mkdirSync(path.join(root, 'theme', 'assets'), { recursive: true });
  writeFileSync(path.join(dir, 'contract.json'), `${JSON.stringify(contractFor(), null, 2)}\n`);
  const digest = contractHash(path.join(dir, 'contract.json'));
  const bytes = Buffer.from('asset');
  writeFileSync(path.join(dir, 'source', 'assets', 'asset.png'), bytes);
  writeFileSync(path.join(root, 'theme', 'assets', 'asset.png'), bytes);
  writeFileSync(path.join(dir, 'assets.json'), JSON.stringify({
    page: 'home', contractHash: digest, assetPass: true, assets: [{
      id: 'asset-001', localPath: 'source/assets/asset.png', publicPath: 'theme/assets/asset.png',
      sha256: sha(bytes), verifiedExact: true,
    }],
  }));
  writeFileSync(path.join(dir, 'dynamics.json'), JSON.stringify({
    page: 'home', contractHash: digest, dynamicsPass: true, mustClassify: [],
  }));
  writeFileSync(path.join(dir, 'interactions.md'), '- [ ] restore the drop shadow\n');
  writeFileSync(path.join(dir, 'visual-deltas.md'), '- [x] all sections within tolerance\n');
  writeFileSync(path.join(dir, 'reports', 'final.md'), 'PASS\n');
  writeFileSync(path.join(dir, 'reports', 'visual-verify.md'), 'PASS\n');
  return { root, dir };
}

function seal(root, dir) {
  const contract = JSON.parse(readFileSync(path.join(dir, 'contract.json'), 'utf8'));
  const evidence = gateEvidence(path.join(dir, 'contract.json'), { cwd: root, env: {} });
  const reports = [];
  for (const id of requiredReportIds(contract)) {
    const [viewport, mode] = id.split(':');
    const file = `${viewport}${mode === 'overlay' ? '.overlay' : ''}.section.json`;
    const data = {
      version: 2, contractHash: evidence.contractHash, themeHash: evidence.themeHash,
      evidenceHash: evidence.evidenceHash, viewport, mode, overallPass: true,
      sections: [{ section: 'main', pass: true }],
    };
    const text = `${JSON.stringify(data, null, 2)}\n`;
    writeFileSync(path.join(dir, 'reports', file), text);
    reports.push({ id, file, sha256: sha(text) });
  }
  writeFileSync(path.join(dir, 'gate.json'), JSON.stringify({
    version: 2, page: contract.page, contractHash: evidence.contractHash, themeHash: evidence.themeHash,
    evidenceHash: evidence.evidenceHash, reports,
    deltaHash: sha(readFileSync(path.join(dir, 'visual-deltas.md'))), openDeltas: 0, visualPass: true,
  }));
}

test('env parsing preserves spaces and explicit environment wins', () => {
  expect(parseEnv('NAME=value with spaces # comment\nMY_ID_2="quoted # value"')).toEqual({
    NAME: 'value with spaces', MY_ID_2: 'quoted # value',
  });
  const root = mkdtempSync(path.join(tmpdir(), 'env-'));
  const file = path.join(root, '.env');
  writeFileSync(file, 'SHOPIFY_STORE=file.example\n');
  expect(loadEnv(file, { SHOPIFY_STORE: 'shell.example' }).SHOPIFY_STORE).toBe('shell.example');
  expect(substituteEnv('https://__SHOPIFY_STORE__/', {})).toBe('https://__SHOPIFY_STORE__/');
  rmSync(root, { recursive: true, force: true });
});

test('contract validation rejects incomplete targets and typoed viewport checks', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'contract-'));
  const file = path.join(root, 'contract.json');
  const contract = contractFor();
  delete contract.sections[0].targets.desktop.box.x;
  contract.sections[0].checks = [{ selector: 'a', expectByViewport: { Desktop: { count: 1 } } }];
  writeFileSync(file, JSON.stringify(contract));
  const result = validateContract(file);
  expect(result.pass).toBe(false);
  expect(result.failures.join('\n')).toContain('box.x/box.y');
  expect(result.failures.join('\n')).toContain('unknown expectByViewport key "Desktop"');
  expect(result.failures.join('\n')).toContain('missing expectation for viewport "desktop"');
  rmSync(root, { recursive: true, force: true });
});

test('DONE requires fresh theme-bound reports, public assets, and untampered deltas', () => {
  const { root, dir } = makePack();
  seal(root, dir);
  expect(validatePack(dir).pass).toBe(true);
  expect(pageGated(dir, { cwd: root })).toBe(true);

  writeFileSync(path.join(root, 'theme', 'assets', 'theme.css'), 'changed');
  expect(pageGated(dir, { cwd: root })).toBe(false);
  seal(root, dir);
  expect(pageGated(dir, { cwd: root })).toBe(true);

  writeFileSync(path.join(dir, 'visual-deltas.md'), '- [x] hand edited\n');
  expect(pageGated(dir, { cwd: root })).toBe(false);
  writeFileSync(path.join(dir, 'visual-deltas.md'), '- [x] all sections within tolerance\n');
  seal(root, dir);
  unlinkSync(path.join(dir, 'reports', 'desktop.section.json'));
  expect(pageGated(dir, { cwd: root })).toBe(false);

  rmSync(root, { recursive: true, force: true });
});

test('unresolved preview placeholders cannot produce a valid gate', () => {
  const { root, dir } = makePack();
  const contract = JSON.parse(readFileSync(path.join(dir, 'contract.json'), 'utf8'));
  contract.preview = 'https://__SHOPIFY_STORE__/?themeId=__SHOPIFY_THEME_ID__';
  writeFileSync(path.join(dir, 'contract.json'), JSON.stringify(contract));
  expect(() => gateEvidence(path.join(dir, 'contract.json'), { cwd: root, env: {} })).toThrow(/unresolved/);
  expect(pageGated(dir, { cwd: root })).toBe(false);
  rmSync(root, { recursive: true, force: true });
});

test('a failed gate start overwrites an older green verdict before browser work', () => {
  const { root, dir } = makePack();
  const contract = JSON.parse(readFileSync(path.join(dir, 'contract.json'), 'utf8'));
  contract.preview = 'https://__SHOPIFY_STORE__/?themeId=__SHOPIFY_THEME_ID__';
  writeFileSync(path.join(dir, 'contract.json'), JSON.stringify(contract));
  writeFileSync(path.join(dir, 'gate.json'), JSON.stringify({ version: 2, visualPass: true, openDeltas: 0 }));
  const script = path.resolve('scripts/visual-diff/contract-diff.mjs');
  const result = spawnSync(process.execPath, [script, path.join(dir, 'contract.json')], {
    cwd: root, env: { PATH: process.env.PATH }, encoding: 'utf8',
  });
  expect(result.status).toBe(2);
  expect(JSON.parse(readFileSync(path.join(dir, 'gate.json'), 'utf8'))).toMatchObject({
    version: 2, visualPass: false, openDeltas: 1,
  });
  expect(readFileSync(path.join(dir, 'visual-deltas.md'), 'utf8')).toContain('RUNNING_OR_INTERRUPTED');
  rmSync(root, { recursive: true, force: true });
});
