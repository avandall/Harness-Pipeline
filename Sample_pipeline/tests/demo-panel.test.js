// Tests for the local Migrate control panel (demo/). Covers the pure stage-derivation
// logic, the companion server's read/validate API, the panel UI, and the ANSI→terminal
// renderer. It never triggers a real plan/execute run (those spawn the CLI) — only the
// validation path and the read endpoints. Run: npx playwright test tests/demo-panel.test.js
import { test, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync, readFileSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AGENT_PROFILES, agentEnvironment, createLineBuffer, FOLLOW_UP_MAX_CHARS, followUpStatus,
  pageState, STAGES, validateFollowUpRequest, validateRunConfig,
} from '../demo/server.mjs';
import { gateEvidence } from '../scripts/migration-state.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(HERE, '..', 'demo', 'server.mjs');
const PORT = 4611;
const BASE = `http://127.0.0.1:${PORT}`;

const contractFor = (page) => JSON.stringify({
  page,
  source: `https://source.example/${page}`,
  preview: `https://preview.example/${page}`,
  viewports: { desktop: 1440 },
  sections: [{
    key: 'main', class: 'content', sourceSelector: 'main',
    replicaSelector: "[data-section-key='main']", mustMatch: ['geometry'],
    targets: { desktop: { box: { x: 0, y: 0, w: 1440, h: 800 }, styles: { display: 'block' } } },
  }],
});
const hash = (value) => createHash('sha256').update(value).digest('hex');

function writeDoneEvidence(dir, contract) {
  const contractHash = hash(contract);
  writeFileSync(path.join(dir, 'assets.json'), JSON.stringify({ page: path.basename(dir), contractHash, assetPass: true, assets: [] }));
  writeFileSync(path.join(dir, 'dynamics.json'), JSON.stringify({ page: path.basename(dir), contractHash, dynamicsPass: true, mustClassify: [] }));
  const evidence = gateEvidence(path.join(dir, 'contract.json'));
  const report = {
    version: 2, contractHash, themeHash: evidence.themeHash, evidenceHash: evidence.evidenceHash,
    viewport: 'desktop', mode: 'normal', overallPass: true, sections: [{ section: 'main', pass: true }],
  };
  const reportText = JSON.stringify(report);
  writeFileSync(path.join(dir, 'reports/desktop.section.json'), reportText);
  const deltas = readFileSync(path.join(dir, 'visual-deltas.md'));
  writeFileSync(path.join(dir, 'gate.json'), JSON.stringify({
    version: 2, page: path.basename(dir), visualPass: true, openDeltas: 0, contractHash, themeHash: evidence.themeHash,
    evidenceHash: evidence.evidenceHash, deltaHash: hash(deltas),
    reports: [{ id: 'desktop:normal', file: 'desktop.section.json', sha256: hash(reportText) }],
  }));
}

// Build a fixture migrations/ dir with one page per stage.
function makeFixture() {
  const root = mkdtempSync(path.join(tmpdir(), 'mig-'));
  const mk = (name, files) => {
    const d = path.join(root, name); mkdirSync(d, { recursive: true });
    for (const [f, c] of Object.entries(files)) { const fp = path.join(d, f); mkdirSync(path.dirname(fp), { recursive: true }); writeFileSync(fp, c); }
    return d;
  };
  const build = contractFor('b-build');
  const converge = contractFor('c-converge');
  const interactions = contractFor('d-interactions');
  const gate = contractFor('e-gate');
  const verify = contractFor('f-verify');
  const done = contractFor('g-done');
  mk('a-capture', {});                                                     // no contract → CAPTURE
  mk('b-build', { 'contract.json': build });                               // contract only → BUILD
  mk('c-converge', { 'contract.json': converge, 'visual-deltas.md': '## desktop\n- [ ] hero off' });
  mk('d-interactions', { 'contract.json': interactions, 'visual-deltas.md': '- [x] ok', 'interactions.md': '- [ ] nav REBUILD' });
  mk('e-gate', { 'contract.json': gate, 'visual-deltas.md': '- [x] ok', 'interactions.md': '- [x] ok' });
  mk('f-verify', { 'contract.json': verify, 'visual-deltas.md': '- [x] ok', 'interactions.md': '- [x] ok', 'reports/final.md': 'done' });
  const doneDir = mk('g-done', { 'contract.json': done, 'visual-deltas.md': '- [x] ok', 'interactions.md': '- [x] ok', 'reports/final.md': 'done', 'reports/visual-verify.md': 'ok' });
  writeDoneEvidence(doneDir, done);
  return root;
}

// ---- 1. pure stage-derivation (mirrors ralph.sh / active-migration-page.mjs) ----
test.describe('stage derivation', () => {
  const root = makeFixture();
  test.afterAll(() => rmSync(root, { recursive: true, force: true }));

  test('STAGES pipeline is the 7-stage machine', () => {
    expect(STAGES).toEqual(['CAPTURE', 'BUILD', 'CONVERGE', 'INTERACTIONS', 'GATE', 'VISUAL-VERIFY', 'DONE']);
  });

  for (const [dir, stage] of [
    ['a-capture', 'CAPTURE'], ['b-build', 'BUILD'], ['c-converge', 'CONVERGE'],
    ['d-interactions', 'INTERACTIONS'], ['e-gate', 'GATE'], ['f-verify', 'VISUAL-VERIFY'], ['g-done', 'DONE'],
  ]) {
    test(`${dir} → ${stage}`, () => {
      const s = pageState(path.join(root, dir));
      expect(s.stage).toBe(stage);
      expect(s.done).toBe(stage === 'DONE');
    });
  }

  test('a missing interactions inventory cannot display as DONE', () => {
    const dir = path.join(root, 'missing-interactions');
    mkdirSync(dir, { recursive: true });
    writeFileSync(path.join(dir, 'contract.json'), contractFor('missing-interactions'));
    writeFileSync(path.join(dir, 'visual-deltas.md'), '- [x] ok');
    expect(pageState(dir).stage).toBe('INTERACTIONS');
  });
});

test('line buffer keeps a monotonic cursor after eviction and does not add chunk blanks', () => {
  const buffer = createLineBuffer(3);
  const writer = buffer.writer();
  writer.write('one\ntwo'); writer.write('\nthree\nfour\n'); writer.flush();
  expect(buffer.read(0)).toMatchObject({ base: 1, next: 4, dropped: true, lines: ['two', 'three', 'four'] });
});

test('agent presets validate provider-specific effort and become child-only environment overrides', () => {
  expect(AGENT_PROFILES.map((profile) => profile.id)).toEqual(['claude', 'codex', 'custom']);
  expect(validateRunConfig({ provider: 'codex', model: 'gpt-5.6-sol', effort: 'max', execution: 'one-go' })).toEqual({
    value: { provider: 'codex', model: 'gpt-5.6-sol', effort: 'max', execution: 'one-go' },
  });
  expect(validateRunConfig({ provider: 'codex', effort: 'ultracode' }).error).toContain('Effort for Codex');
  expect(validateRunConfig({ provider: 'claude', model: 'model with spaces' }).error).toContain('valid model ID');
  expect(validateRunConfig(null).error).toContain('JSON object');
  expect(agentEnvironment({ KEEP: 'yes', AGENT_MODEL: 'configured-default' }, { model: 'gpt-5.6-sol', effort: 'max' }))
    .toMatchObject({ KEEP: 'yes', AGENT_MODEL: 'gpt-5.6-sol', AGENT_EFFORT: 'max' });
  expect(agentEnvironment({ AGENT_MODEL: 'configured-default' }, {})).toMatchObject({ AGENT_MODEL: 'configured-default' });
});

test('follow-up validation requires a bounded request and a fully completed queue', () => {
  expect(validateFollowUpRequest({ prompt: '  tighten mobile spacing  ' })).toEqual({ value: 'tighten mobile spacing' });
  expect(validateFollowUpRequest({ prompt: '   ' }).error).toContain('Enter a follow-up request');
  expect(validateFollowUpRequest({ prompt: 'x'.repeat(FOLLOW_UP_MAX_CHARS + 1) }).error).toContain('characters or fewer');
  const root = makeFixture();
  writeFileSync(path.join(root, '_queue.tsv'), 'g-done\thttps://source.example/g-done\n');
  expect(followUpStatus(root)).toMatchObject({ ready: true, completed: 1, total: 1 });
  expect(followUpStatus(root, { blocked: true })).toMatchObject({ ready: false, completed: 1, total: 1 });
  rmSync(root, { recursive: true, force: true });
});

// ---- 2. server API + UI + ANSI renderer ----
test.describe('panel server + UI', () => {
  let proc, root, refRoot, blockedFile, learnFile, followUpCapture, followUpConfig, tmp, csrf;
  const mutate = (pathname, options = {}) => fetch(`${BASE}${pathname}`, {
    method: 'POST',
    ...options,
    headers: { Origin: BASE, 'X-Migrate-CSRF': csrf, ...(options.headers || {}) },
  });
  test.beforeAll(async () => {
    root = makeFixture();
    tmp = mkdtempSync(path.join(tmpdir(), 'panel-'));
    refRoot = path.join(tmp, 'reference'); blockedFile = path.join(tmp, 'BLOCKED'); learnFile = path.join(tmp, 'LEARNINGS.md');
    followUpCapture = path.join(tmp, 'follow-up-request.txt'); followUpConfig = path.join(tmp, 'follow-up-config.txt');
    const followUpStub = path.join(tmp, 'follow-up-stub.sh');
    writeFileSync(followUpStub, '#!/bin/sh\nprintf "%s\\t%s\\t%s\\n" "$*" "$AGENT_MODEL" "$AGENT_EFFORT" > "$PANEL_FOLLOW_UP_CONFIG"\ncat > "$PANEL_FOLLOW_UP_CAPTURE"\n');
    chmodSync(followUpStub, 0o755);
    proc = spawn('node', [SERVER], { detached: true, env: {
      ...process.env, PORT: String(PORT), PANEL_JSON_LIMIT: '1024', MIGRATIONS_DIR: root, REF_ROOT: refRoot,
      BLOCKED_FILE: blockedFile, LEARNINGS_FILE: learnFile, PANEL_FOLLOW_UP_SCRIPT: followUpStub,
      PANEL_FOLLOW_UP_CAPTURE: followUpCapture, PANEL_FOLLOW_UP_CONFIG: followUpConfig,
    }, stdio: 'ignore' });
    for (let i = 0; i < 50; i++) { try { await fetch(`${BASE}/api/status`); break; } catch { await new Promise((r) => setTimeout(r, 100)); } }
    const html = await (await fetch(BASE)).text();
    csrf = html.match(/name="migrate-csrf" content="([^"]+)"/)?.[1];
    if (!csrf) throw new Error('missing panel CSRF token');
  });
  test.afterAll(() => { try { process.kill(-proc.pid); } catch { try { proc.kill('SIGKILL'); } catch {} } rmSync(root, { recursive: true, force: true }); rmSync(tmp, { recursive: true, force: true }); });

  test('GET /api/status reports pages + stages, not running', async () => {
    const s = await (await fetch(`${BASE}/api/status`)).json();
    expect(s.running).toBe(false);
    expect(s.stages).toHaveLength(7);
    const byPage = Object.fromEntries(s.pages.map((p) => [p.page, p.stage]));
    expect(byPage['b-build']).toBe('BUILD');
    expect(byPage['g-done']).toBe('DONE');
    expect(s.pages.find((p) => p.page === 'g-done').done).toBe(true);
  });

  test('status carries a plan block + a blocked field', async () => {
    const s = await (await fetch(`${BASE}/api/status`)).json();
    expect(s.plan).toMatchObject({ queued: 0, validated: 0, complete: false });
    expect(s).toHaveProperty('blocked');
    expect(s.followUp).toMatchObject({ ready: false, completed: 0, total: 0 });
  });

  test('blocked shows in status and clears via POST /api/unblock', async () => {
    expect((await (await fetch(`${BASE}/api/status`)).json()).blocked).toBeNull();
    writeFileSync(blockedFile, 'BLOCKED: needs a one-time login');
    expect((await (await fetch(`${BASE}/api/status`)).json()).blocked).toContain('one-time login');
    const r = await (await mutate('/api/unblock')).json();
    expect(r.removed).toBe(true);
    expect((await (await fetch(`${BASE}/api/status`)).json()).blocked).toBeNull();
    expect(existsSync(blockedFile)).toBe(false);
  });

  test('GET /api/learnings returns LEARNINGS.md content', async () => {
    writeFileSync(learnFile, '# LEARNINGS\n- keep this lean');
    expect((await (await fetch(`${BASE}/api/learnings`)).json()).content).toContain('keep this lean');
  });

  test('upload-reference writes under reference/ and blocks path traversal', async () => {
    const ok = await mutate(`/api/upload-reference?path=${encodeURIComponent('build/index.html')}`, { body: '<h1>hi</h1>' });
    expect(ok.status).toBe(200);
    expect(readFileSync(path.join(refRoot, 'build', 'index.html'), 'utf8')).toBe('<h1>hi</h1>');
    const bad = await mutate(`/api/upload-reference?path=${encodeURIComponent('../escape.txt')}`, { body: 'x' });
    expect(bad.status).toBe(400);
    expect(existsSync(path.join(tmp, 'escape.txt'))).toBe(false);
  });

  test('upload-reference rejects a symlink escape', async () => {
    const outside = path.join(tmp, 'outside');
    mkdirSync(outside, { recursive: true });
    mkdirSync(refRoot, { recursive: true });
    symlinkSync(outside, path.join(refRoot, 'linked'));
    const response = await mutate(`/api/upload-reference?path=${encodeURIComponent('linked/pwn.txt')}`, { body: 'x' });
    expect(response.status).toBe(400);
    expect(existsSync(path.join(outside, 'pwn.txt'))).toBe(false);
  });

  test('mutations require same-origin CSRF and malformed/oversize JSON cannot crash the server', async () => {
    const untrusted = await fetch(`${BASE}/api/plan`, {
      method: 'POST', headers: { Origin: 'https://evil.example', 'Content-Type': 'text/plain' }, body: '{}',
    });
    expect(untrusted.status).toBe(403);
    const malformed = await mutate('/api/plan', { headers: { 'Content-Type': 'application/json' }, body: '{' });
    expect(malformed.status).toBe(400);
    const oversized = await mutate('/api/plan', {
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ source: 'x'.repeat(2000) }),
    });
    expect(oversized.status).toBe(413);
    expect((await fetch(`${BASE}/api/status`)).status).toBe(200);
  });

  test('plan.complete = every queued route validated (a cut-off is not complete)', async () => {
    const vp = path.join(root, 'z-planned'); mkdirSync(vp, { recursive: true });
    writeFileSync(path.join(vp, 'contract.json'), contractFor('z-planned'));
    const contractHash = hash(readFileSync(path.join(vp, 'contract.json')));
    writeFileSync(path.join(vp, 'assets.json'), JSON.stringify({ page: 'z-planned', contractHash, assetPass: true, assets: [] }));
    writeFileSync(path.join(vp, 'dynamics.json'), JSON.stringify({ page: 'z-planned', contractHash, dynamicsPass: true, mustClassify: [] }));
    writeFileSync(path.join(vp, 'interactions.md'), '# interactions\n');
    writeFileSync(path.join(root, '_queue.tsv'), 'z-planned\thttps://source.example/z-planned');
    let s = await (await fetch(`${BASE}/api/status`)).json();
    expect(s.plan).toMatchObject({ queued: 1, validated: 1, complete: true });
    writeFileSync(path.join(root, '_queue.tsv'), 'z-planned\thttps://source.example/z-planned\nmissing\thttps://x/2');   // cut-off
    s = await (await fetch(`${BASE}/api/status`)).json();
    expect(s.plan.complete).toBe(false);
    rmSync(vp, { recursive: true, force: true }); rmSync(path.join(root, '_queue.tsv'), { force: true });
  });

  test('POST /api/execute rejects a missing/incomplete queue — never spawns', async () => {
    const r = await mutate('/api/execute', { headers: { 'Content-Type': 'application/json' }, body: '{}' });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toContain('Planning is incomplete');
    expect((await (await fetch(`${BASE}/api/status`)).json()).running).toBe(false);
  });

  test('POST /api/execute rejects BLOCKED before any spawn', async () => {
    writeFileSync(blockedFile, 'needs user action');
    const response = await mutate('/api/execute', { headers: { 'Content-Type': 'application/json' }, body: '{}' });
    expect(response.status).toBe(409);
    expect((await response.json()).error).toContain('blocked');
    await mutate('/api/unblock');
  });

  test('POST /api/follow-up validates text and rejects an unfinished migration before spawn', async () => {
    const headers = { 'Content-Type': 'application/json' };
    const empty = await mutate('/api/follow-up', { headers, body: JSON.stringify({ prompt: '  ' }) });
    expect(empty.status).toBe(400);
    expect((await empty.json()).error).toContain('Enter a follow-up request');
    const early = await mutate('/api/follow-up', { headers, body: JSON.stringify({ prompt: 'Tighten mobile spacing.' }) });
    expect(early.status).toBe(409);
    expect((await early.json()).error).toContain('Plan validates every queued page');
    expect((await (await fetch(`${BASE}/api/status`)).json()).running).toBe(false);
  });

  test('POST /api/follow-up streams the request on stdin with the selected provider configuration', async () => {
    writeFileSync(path.join(root, '_queue.tsv'), 'g-done\thttps://source.example/g-done\n');
    const response = await mutate('/api/follow-up', {
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: 'Refine the completed header.', provider: 'codex', model: 'gpt-5.6-sol', effort: 'max' }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ok: true, kind: 'follow-up' });
    await expect.poll(() => existsSync(followUpCapture) ? readFileSync(followUpCapture, 'utf8') : '').toBe('Refine the completed header.');
    expect(readFileSync(followUpConfig, 'utf8')).toBe('--provider codex\tgpt-5.6-sol\tmax\n');
    await expect.poll(async () => (await (await fetch(`${BASE}/api/status`)).json()).running).toBe(false);
    rmSync(path.join(root, '_queue.tsv'), { force: true });
    rmSync(followUpCapture, { force: true }); rmSync(followUpConfig, { force: true });
  });

  test('GET /api/log returns a cursor-consistent buffer', async () => {
    const d = await (await fetch(`${BASE}/api/log?since=0`)).json();
    expect(Array.isArray(d.lines)).toBe(true);
    expect(d.next - d.from).toBe(d.lines.length);
  });

  test('POST /api/plan with no source is rejected (400) — never spawns', async () => {
    const r = await mutate('/api/plan', { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ source: '', mode: 'site' }) });
    expect(r.status).toBe(400);
    expect((await (await fetch(`${BASE}/api/status`)).json()).running).toBe(false);
  });

  test('provider, model, effort, and execution inputs are validated before spawning', async () => {
    const headers = { 'Content-Type': 'application/json' };
    const badProvider = await mutate('/api/plan', { headers, body: JSON.stringify({ source: 'https://source.example', provider: 'unknown', execution: 'loop' }) });
    expect(badProvider.status).toBe(400);
    expect((await badProvider.json()).error).toContain('Provider');
    const badMode = await mutate('/api/execute', { headers, body: JSON.stringify({ provider: 'codex', execution: 'forever-loop' }) });
    expect(badMode.status).toBe(400);
    expect((await badMode.json()).error).toContain('Execution mode');
    const badEffort = await mutate('/api/execute', { headers, body: JSON.stringify({ provider: 'codex', model: 'gpt-5.6-sol', effort: 'ultracode' }) });
    expect(badEffort.status).toBe(400);
    expect((await badEffort.json()).error).toContain('Effort for Codex');
    const configured = await mutate('/api/execute', { headers, body: JSON.stringify({ provider: 'codex', model: 'gpt-5.6-sol', effort: 'max', execution: 'one-go' }) });
    expect(configured.status).toBe(409); // accepted config; stopped only by incomplete Plan preflight
    expect((await (await fetch(`${BASE}/api/status`)).json()).running).toBe(false);
  });

  test('UI renders — hero headline, work controls, stage tracker, tiles', async ({ page }) => {
    await page.goto(BASE);
    await expect(page.locator('#hero h1')).toContainText('Migrate any store to Shopify');
    // the fixture has planned pages, so the work view is shown — check its chrome + tracker
    await expect(page.locator('#wExec')).toBeVisible();
    await expect(page.locator('#wStop')).toBeDisabled();
    await expect(page.locator('#wGuide')).toBeVisible();
    await expect(page.locator('#wLearn')).toBeVisible();
    await expect(page.locator('#provider')).toHaveValue('claude');
    await expect(page.locator('#provider option')).toHaveCount(3);
    await expect(page.locator('#model')).toHaveValue('');
    await expect(page.locator('#model option')).toHaveCount(10);
    await expect(page.locator('#effort')).toHaveValue('');
    await expect(page.locator('#effort option')).toHaveCount(6);
    await expect(page.locator('#execution')).toHaveValue('loop');
    await expect(page.locator('#execution option')).toHaveCount(2);
    await expect(page.locator('#autoExecute')).not.toBeChecked();
    await expect(page.locator('#followUpCard')).toBeVisible();
    await expect(page.locator('#followUpState')).toHaveText('Locked');
    await expect(page.locator('#followUpButton')).toBeDisabled();
    await expect(page.locator('#followUpHelp')).toContainText('Plan validates every queued page');
    await expect(page.locator('#runConfig')).toHaveText('Claude · default model · default effort · loop');
    await page.locator('#wReset').click();
    await page.locator('#provider').selectOption('codex');
    await expect(page.locator('#model option')).toHaveCount(5);
    await expect(page.locator('#effort option')).toHaveCount(7);
    await page.locator('#model').selectOption('gpt-5.6-sol');
    await page.locator('#effort').selectOption('max');
    await page.locator('#execution').selectOption('one-go');
    await page.locator('#autoExecute').check();
    await expect(page.locator('#runConfig')).toHaveText('Codex · 5.6 Sol · max · one go · auto');
    await page.reload();
    await expect(page.locator('#provider')).toHaveValue('codex');
    await expect(page.locator('#model')).toHaveValue('gpt-5.6-sol');
    await expect(page.locator('#effort')).toHaveValue('max');
    await expect(page.locator('#execution')).toHaveValue('one-go');
    await expect(page.locator('#autoExecute')).toBeChecked();
    for (const s of STAGES) await expect(page.locator('#track')).toContainText(s);   // all 7 incl. VISUAL-VERIFY
    await expect(page.locator('#tiles')).toContainText('b-build');
    await expect(page.locator('#tiles')).toContainText('BUILD');
  });

  test('auto-execute starts exactly once after the Plan from this tab becomes complete', async ({ page }) => {
    let planRequested = false, planBody = null, executeBody = null, statusAfterPlan = 0, executeRequests = 0;
    const status = (running, complete) => ({
      running, kind: running ? 'plan' : null, startedAt: running ? Date.now() : null, demo: false,
      stages: STAGES, pages: [], logBase: 0, logLen: 0, blocked: null,
      plan: { queued: complete ? 1 : 0, validated: complete ? 1 : 0, complete }, referenceBuilds: [],
    });
    await page.route(`${BASE}/api/status`, async (route) => {
      if (!planRequested) return route.fulfill({ contentType: 'application/json', body: JSON.stringify(status(false, false)) });
      statusAfterPlan += 1;
      return route.fulfill({ contentType: 'application/json', body: JSON.stringify(status(statusAfterPlan === 1, statusAfterPlan > 1)) });
    });
    await page.route(`${BASE}/api/plan`, async (route) => {
      planBody = route.request().postDataJSON();
      planRequested = true;
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, kind: 'plan' }) });
    });
    await page.route(`${BASE}/api/execute`, async (route) => {
      executeBody = route.request().postDataJSON();
      executeRequests += 1;
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, kind: 'execute' }) });
    });
    await page.goto(BASE);
    await page.locator('#execution').selectOption('one-go');
    await page.locator('#autoExecute').check();
    await page.locator('#url').fill('https://source.example');
    await page.locator('#heroPlan').click();
    await expect.poll(() => executeRequests, { timeout: 6000 }).toBe(1);
    await page.waitForTimeout(1500);
    expect(executeRequests).toBe(1);
    expect(planBody.execution).toBeUndefined(); // Execute mode must never change Plan.
    expect(executeBody.execution).toBe('one-go');
  });

  test('completed migration unlocks one context-aware follow-up request and clears its saved draft', async ({ page }) => {
    let followUpBody = null, followUpRequests = 0;
    const complete = {
      running: false, kind: null, startedAt: null, demo: false, stages: STAGES,
      pages: [{ page: 'home', stage: 'DONE', done: true, gatePass: true }], logBase: 0, logLen: 0, blocked: null,
      plan: { queued: 1, validated: 1, complete: true },
      followUp: { ready: true, completed: 1, total: 1, reason: '' }, referenceBuilds: [],
    };
    await page.route(`${BASE}/api/status`, (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify(complete) }));
    await page.route(`${BASE}/api/follow-up`, async (route) => {
      followUpBody = route.request().postDataJSON(); followUpRequests += 1;
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, kind: 'follow-up' }) });
    });
    await page.goto(BASE);
    await expect(page.locator('#followUpState')).toHaveText('Ready');
    await page.locator('#wReset').click();
    await page.locator('#provider').selectOption('codex');
    await page.locator('#model').selectOption('gpt-5.6-sol');
    await page.locator('#effort').selectOption('max');
    await page.locator('#heroFollowUp').click();
    await page.locator('#followUpPrompt').fill('Tighten the mobile header and verify every route.');
    await expect(page.locator('#followUpCount')).toContainText('49 / 16,000');
    expect(await page.evaluate(() => localStorage.getItem('migrate-follow-up-draft'))).toBe('Tighten the mobile header and verify every route.');
    await expect(page.locator('#followUpButton')).toBeEnabled();
    await page.locator('#followUpButton').click();
    await expect.poll(() => followUpRequests).toBe(1);
    expect(followUpBody).toEqual({ prompt: 'Tighten the mobile header and verify every route.', provider: 'codex', model: 'gpt-5.6-sol', effort: 'max' });
    await expect(page.locator('#followUpPrompt')).toHaveValue('');
    expect(await page.evaluate(() => localStorage.getItem('migrate-follow-up-draft'))).toBeNull();
  });

  test('custom model entry remains usable without mobile horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(BASE);
    let widths = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth }));
    expect(widths.document).toBeLessThanOrEqual(widths.viewport);
    await page.locator('#wReset').click();
    await page.locator('#provider').selectOption('custom');
    await page.locator('#model').selectOption('__custom__');
    await expect(page.locator('#modelCustom')).toBeVisible();
    await page.locator('#modelCustom').fill('adapter/model-v1');
    await expect(page.locator('#runConfig')).toContainText('adapter/model-v1');
    widths = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth }));
    expect(widths.document).toBeLessThanOrEqual(widths.viewport);
  });

  test('guide, setup, and learnings modals open + close', async ({ page }) => {
    await page.goto(BASE);
    await page.locator('#wGuide').click();
    await expect(page.locator('#modal')).toBeVisible();
    await expect(page.locator('#mBody')).toContainText('VISUAL-VERIFY');   // guide lists both phases
    await page.locator('#mClose').click();
    await expect(page.locator('#modal')).toBeHidden();
    await page.locator('#wLearn').click();
    await expect(page.locator('#mBody')).toContainText('Be careful editing the harness');   // the warning
  });

  test('ANSI stream renders as coloured spans (not literal escape codes)', async ({ page }) => {
    await page.goto(BASE);
    const html = await page.evaluate(() => window.ansiToHtml('\x1b[36m🔧 Bash\x1b[0m \x1b[2margs\x1b[0m'));
    expect(html).toContain('color:#5CC8FF');   // cyan tool name
    expect(html).toContain('opacity:.6');       // dim args
    expect(html).toContain('🔧 Bash');
    expect(html).not.toContain('[36m');          // the raw escape must be gone
  });
});
