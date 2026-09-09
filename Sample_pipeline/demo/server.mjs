#!/usr/bin/env node
// Local companion server for the Migrate control panel (demo/index.html).
//
// A browser page can't spawn shell commands, so this tiny dependency-free server does it:
// the panel POSTs to /api/plan, /api/execute, and /api/follow-up, and this process runs the
// SKELETON'S OWN scripts as child processes, streaming their output back
// and reporting real per-page stage state read from migrations/*/. It is bound to 127.0.0.1
// ONLY — it runs YOUR local CLI on YOUR machine; never expose it to a network.
//
//   bun dev                              # → http://localhost:4599   (or: node demo/server.mjs)
//   PORT=5000 bun dev
//   # The panel opts into unattended provider execution. Run it only in a dedicated local repo/VM.
//   # Override provider flags with AGENT_FLAGS, CLAUDE_FLAGS, or CODEX_FLAGS.
//
// Nothing here is committed to the theme; it's a dev-only control panel over the existing scripts.

import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import {
  closeSync, constants, existsSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync,
  statSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { contractHash, gateEvidence, pageComplete, pageGated, readQueue, validatePack } from '../scripts/migration-state.mjs';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '..');            // the skeleton repo root
const PORT = Number(process.env.PORT || 4599);
const MIGRATIONS = process.env.MIGRATIONS_DIR ? path.resolve(process.env.MIGRATIONS_DIR) : path.join(ROOT, 'migrations');
const BLOCKED = process.env.BLOCKED_FILE ? path.resolve(process.env.BLOCKED_FILE) : path.join(ROOT, '.ralph', 'BLOCKED');
const readBlocked = () => { try { return readFileSync(BLOCKED, 'utf8'); } catch { return null; } };
const REFROOT = path.resolve(ROOT, process.env.REF_ROOT || 'reference');
const LEARNINGS = process.env.LEARNINGS_FILE ? path.resolve(process.env.LEARNINGS_FILE) : path.join(ROOT, 'LEARNINGS.md');
const FOLLOW_UP_SCRIPT = process.env.PANEL_FOLLOW_UP_SCRIPT || 'scripts/follow-up.sh';
const CSRF_TOKEN = randomBytes(24).toString('base64url');
const JSON_LIMIT = Number(process.env.PANEL_JSON_LIMIT || 64 * 1024);
const UPLOAD_LIMIT = Number(process.env.PANEL_UPLOAD_LIMIT || 100 * 1024 * 1024);
export const FOLLOW_UP_MAX_CHARS = 16000;

// One server-owned catalog drives both the UI and request validation. Model discovery is
// not portable across provider CLIs, so the panel offers verified presets plus a custom-ID
// escape hatch. Empty values deliberately preserve the server process' environment/defaults.
export const AGENT_PROFILES = Object.freeze([
  {
    id: 'claude', label: 'Claude', defaultModelLabel: 'Environment / CLI default',
    defaultEffortLabel: 'Environment / harness default',
    models: [
      { value: 'best', label: 'Best available', short: 'best' },
      { value: 'fable', label: 'Fable 5', short: 'Fable' },
      { value: 'opus', label: 'Opus', short: 'Opus' },
      { value: 'opus[1m]', label: 'Opus · 1M context', short: 'Opus 1M' },
      { value: 'sonnet', label: 'Sonnet', short: 'Sonnet' },
      { value: 'sonnet[1m]', label: 'Sonnet · 1M context', short: 'Sonnet 1M' },
      { value: 'haiku', label: 'Haiku', short: 'Haiku' },
      { value: 'opusplan', label: 'Opus plan · Sonnet execute', short: 'Opus plan' },
    ],
    efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
  },
  {
    id: 'codex', label: 'Codex', defaultModelLabel: 'Environment / Codex default',
    defaultEffortLabel: 'Environment / harness default',
    models: [
      { value: 'gpt-5.6-sol', label: 'GPT-5.6 Sol · strongest', short: '5.6 Sol' },
      { value: 'gpt-5.6-terra', label: 'GPT-5.6 Terra · balanced', short: '5.6 Terra' },
      { value: 'gpt-5.6-luna', label: 'GPT-5.6 Luna · fastest', short: '5.6 Luna' },
    ],
    efforts: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
  },
  {
    id: 'custom', label: 'Custom · AGENT_BIN', defaultModelLabel: 'Adapter default',
    defaultEffortLabel: 'Adapter default', models: [],
    efforts: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
  },
]);

const SAFE_MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._:/@+\[\]-]{0,127}$/;
export function validateRunConfig(input = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { error: 'Request body must be a JSON object.' };
  }
  const provider = input.provider ?? 'claude';
  const execution = input.execution ?? 'loop';
  const rawModel = input.model ?? '';
  const rawEffort = input.effort ?? '';
  if (typeof provider !== 'string' || !AGENT_PROFILES.some((profile) => profile.id === provider)) {
    return { error: 'Provider must be claude, codex, or custom.' };
  }
  if (typeof execution !== 'string' || !['loop', 'one-go'].includes(execution)) {
    return { error: 'Execution mode must be loop or one-go.' };
  }
  if (typeof rawModel !== 'string') return { error: 'Model must be a string.' };
  if (typeof rawEffort !== 'string') return { error: 'Effort must be a string.' };
  const model = rawModel.trim();
  const effort = rawEffort.trim();
  if (model && (model === '__custom__' || !SAFE_MODEL_ID.test(model))) {
    return { error: 'Model must be a valid model ID (letters, numbers, . _ : / @ + [ ] or -; max 128 characters).' };
  }
  const profile = AGENT_PROFILES.find((candidate) => candidate.id === provider);
  if (effort && !profile.efforts.includes(effort)) {
    return { error: `Effort for ${profile.label} must be ${profile.efforts.join(', ')}, or empty for the configured default.` };
  }
  return { value: { provider, execution, model, effort } };
}

export function agentEnvironment(base, config = {}) {
  const env = { ...base };
  if (config.model) env.AGENT_MODEL = config.model;
  if (config.effort) env.AGENT_EFFORT = config.effort;
  return env;
}

export function validateFollowUpRequest(input, maxChars = FOLLOW_UP_MAX_CHARS) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { error: 'Request body must be a JSON object.' };
  if (typeof input.prompt !== 'string') return { error: 'Follow-up prompt must be a string.' };
  const prompt = input.prompt.trim();
  if (!prompt) return { error: 'Enter a follow-up request.' };
  if (prompt.length > maxChars) return { error: `Follow-up request must be ${maxChars} characters or fewer.` };
  return { value: prompt };
}

// DEMO_MODE=1 replaces the real (hours-long) plan.sh/ralph.sh runs with a fast in-process
// SIMULATION: it streams realistic output and advances the REAL migrations/<page>/ stage files in
// seconds, so the panel exercises every behaviour — plan→capture, execute BUILD→…→DONE, and a
// BLOCKED pause you clear from the UI — end to end, for a walkthrough. It writes ONLY under
// migrations/ + .ralph/BLOCKED, and only when this flag is set. Never enable it for a real run.
const DEMO = process.env.DEMO_MODE === '1';

// ---- single-run state -------------------------------------------------------
let child = null;            // the running plan/execute/follow-up process (one at a time)
let kind = null;             // 'plan' | 'execute' | 'follow-up'
let startedAt = null;
const LOG_CAP = 4000;
export function createLineBuffer(capacity = LOG_CAP) {
  let rows = [];
  let base = 0;
  let next = 0;
  const appendLine = (line) => {
    rows.push({ cursor: next++, line: String(line).replace(/\r$/, '') });
    while (rows.length > capacity) rows.shift();
    base = rows.length ? rows[0].cursor : next;
  };
  const pushText = (value) => {
    const parts = String(value).split('\n');
    if (parts.at(-1) === '') parts.pop();
    for (const line of parts) appendLine(line);
  };
  const writer = () => {
    let pending = '';
    return {
      write(value) {
        const parts = `${pending}${String(value)}`.split('\n');
        pending = parts.pop();
        for (const line of parts) appendLine(line);
      },
      flush() { if (pending) appendLine(pending); pending = ''; },
    };
  };
  return {
    pushText,
    writer,
    reset() { rows = []; base = next; },
    read(since = base) {
      const requested = Number.isFinite(Number(since)) ? Math.max(0, Number(since)) : base;
      const from = Math.max(base, requested);
      return { from, base, next, dropped: requested < base, lines: rows.filter((row) => row.cursor >= from).map((row) => row.line) };
    },
    get base() { return base; },
    get next() { return next; },
  };
}
const outputLog = createLineBuffer();
const push = (line) => outputLog.pushText(line);

// ---- derive real per-page stage from migrations/<page>/ ---------------------
// Mirrors the loop's own "done" logic (scripts/active-migration-page.mjs + ralph.sh).
const STAGES = ['CAPTURE', 'BUILD', 'CONVERGE', 'INTERACTIONS', 'GATE', 'VISUAL-VERIFY', 'DONE'];
function openBoxes(file) { try { return readFileSync(file, 'utf8').split('\n').filter((l) => /^\s*- \[ \]/.test(l)).length; } catch { return 0; } }
function pageState(dir) {
  const p = (f) => path.join(dir, f);
  const has = (f) => existsSync(p(f));
  let stage = 'CAPTURE';
  if (!has('contract.json')) stage = 'CAPTURE';
  else if (!has('visual-deltas.md')) stage = 'BUILD';
  else if (openBoxes(p('visual-deltas.md')) > 0) stage = 'CONVERGE';
  else if (!has('interactions.md') || openBoxes(p('interactions.md')) > 0) stage = 'INTERACTIONS';
  else if (!has('reports/final.md')) stage = 'GATE';
  else if (!has('reports/visual-verify.md')) stage = 'VISUAL-VERIFY';
  else if (!pageGated(dir, { cwd: ROOT })) stage = 'GATE';
  else stage = 'DONE';
  const done = stage === 'DONE' && pageComplete(dir, { cwd: ROOT });
  return { page: path.basename(dir), stage, done: !!done, gatePass: pageGated(dir, { cwd: ROOT }) };
}
function scanPages() {
  if (!existsSync(MIGRATIONS)) return [];
  const queue = readQueue(MIGRATIONS);
  const names = queue.exists && !queue.errors.length
    ? queue.entries.map((entry) => entry.page)
    : readdirSync(MIGRATIONS).filter((n) => !n.startsWith('_') && !n.startsWith('.') && statSync(path.join(MIGRATIONS, n)).isDirectory());
  return names
    .map((n) => pageState(path.join(MIGRATIONS, n)))
    .sort((a, b) => (a.done - b.done) || names.indexOf(a.page) - names.indexOf(b.page));
}

// A route's plan pack is VALIDATED when its evidence pack is complete — the same conditions
// scripts/plan.sh's pack_done() gates on (a valid measured contract + assets + classified dynamics).
// This is how we tell "planning fully finished" apart from "the plan run was cut off mid-way".
function validatedPack(dir, expectedSource) {
  return validatePack(dir, { expectedSource }).pass;
}
function planStatus() {
  const queue = readQueue(MIGRATIONS);
  const queued = queue.entries.length;
  const validated = queue.entries.filter((entry) => validatedPack(path.join(MIGRATIONS, entry.page), entry.source)).length;
  const complete = queue.exists && !queue.errors.length && queued > 0 && validated === queued;
  return { queued, validated, complete, errors: queue.errors };
}

export function followUpStatus(root = MIGRATIONS, { cwd = ROOT, blocked = false } = {}) {
  const queue = readQueue(root);
  const total = queue.entries.length;
  const validated = queue.entries.filter((entry) => validatedPack(path.join(root, entry.page), entry.source)).length;
  const planned = queue.exists && !queue.errors.length && total > 0 && validated === total;
  const completed = queue.entries.filter((entry) => pageComplete(path.join(root, entry.page), { cwd })).length;
  let reason = '';
  if (blocked) reason = 'Resolve the active block before requesting follow-up work.';
  else if (!planned) reason = 'Follow-up unlocks after Plan validates every queued page.';
  else if (completed !== total) reason = `Follow-up unlocks when every page is DONE (${completed}/${total} complete).`;
  return { ready: !blocked && planned && completed === total, completed, total, reason };
}

function listReferenceBuilds() {
  if (!existsSync(REFROOT)) return [];
  return readdirSync(REFROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(entry.name))
    .filter((entry) => existsSync(path.join(REFROOT, entry.name, 'index.html')))
    .map((entry) => entry.name)
    .sort();
}

// ---- DEMO MODE: simulate a full migration in seconds (no real agents) -------
let mockRunning = false, mockAbort = false;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const DEMO_ROUTES = ['home', 'catalog', 'about', 'contact'];
function wf(dir, rel, content) {
  const fp = path.join(dir, rel);
  mkdirSync(path.dirname(fp), { recursive: true });
  writeFileSync(fp, typeof content === 'string' ? content : JSON.stringify(content, null, 2));
}
const demoContract = (page) => ({
  page, source: `https://demo-source.example/${page === 'home' ? '' : page}`,
  preview: `https://preview.example/${page === 'home' ? '' : `pages/${page}`}`,
  viewports: { desktop: 1440, mobile: 390 }, sections: [
    { key: 'header', class: 'structural', sourceSelector: 'header', replicaSelector: "[data-section-key='header']", mustMatch: ['geometry'], targets: { desktop: { box: { x: 0, y: 0, w: 1440, h: 72 }, styles: { display: 'block' } }, mobile: { box: { x: 0, y: 0, w: 390, h: 56 }, styles: { display: 'block' } } } },
    { key: 'hero', class: 'content', sourceSelector: 'main', replicaSelector: "[data-section-key='hero']", mustMatch: ['geometry'], targets: { desktop: { box: { x: 0, y: 72, w: 1440, h: 640 }, styles: { display: 'block' } }, mobile: { box: { x: 0, y: 56, w: 390, h: 520 }, styles: { display: 'block' } } } },
    { key: 'footer', class: 'structural', sourceSelector: 'footer', replicaSelector: "[data-section-key='footer']", mustMatch: ['geometry'], targets: { desktop: { box: { x: 0, y: 712, w: 1440, h: 380 }, styles: { display: 'block' } }, mobile: { box: { x: 0, y: 576, w: 390, h: 520 }, styles: { display: 'block' } } } },
  ],
});
function writeDemoGate(dir) {
  const evidence = gateEvidence(path.join(dir, 'contract.json'), { cwd: ROOT });
  const reports = [];
  for (const viewport of ['desktop', 'mobile']) {
    const file = `${viewport}.section.json`;
    wf(dir, `reports/${file}`, {
      version: 2, contractHash: evidence.contractHash, themeHash: evidence.themeHash,
      evidenceHash: evidence.evidenceHash, viewport, mode: 'normal', overallPass: true,
      sections: [{ section: 'demo', pass: true }],
    });
    reports.push({ id: `${viewport}:normal`, file, sha256: contractHash(path.join(dir, 'reports', file)) });
  }
  wf(dir, 'gate.json', {
    version: 2, page: path.basename(dir), contractHash: evidence.contractHash, themeHash: evidence.themeHash,
    evidenceHash: evidence.evidenceHash, reports, deltaHash: contractHash(path.join(dir, 'visual-deltas.md')),
    openDeltas: 0, visualPass: true,
  });
}
async function mockPlan(source, options = {}) {
  push(`$ scripts/plan.sh --provider ${options.provider || 'claude'} ${source}   \x1b[2m# ${runConfigLabel(options)} · DEMO MODE — simulated, no real crawl\x1b[0m`);
  await sleep(700);
  push(`\x1b[36m[plan]\x1b[0m opening ${source} with Chrome DevTools MCP — reading sitemap + nav + footer…`);
  await sleep(1500); if (mockAbort) return;
  const queueText = `# demo queue for ${source}\n` + DEMO_ROUTES.map((r) => `${r}\t${source.replace(/\/+$/, '')}/${r === 'home' ? '' : r}`).join('\n') + '\n';
  wf(MIGRATIONS, '_queue.tsv', queueText);
  wf(MIGRATIONS, '_scope.json', { version: 1, mode: 'site', source, queueHash: contractHash(path.join(MIGRATIONS, '_queue.tsv')), createdAt: new Date().toISOString() });
  push(`\x1b[36m[plan]\x1b[0m discovered \x1b[1m${DEMO_ROUTES.length}\x1b[0m in-scope routes → migrations/_queue.tsv`);
  await sleep(900);
  for (let i = 0; i < DEMO_ROUTES.length; i++) {
    if (mockAbort) return;
    const r = DEMO_ROUTES[i], d = path.join(MIGRATIONS, r);
    push(`\n\x1b[36m[plan]\x1b[0m \x1b[1m${r}\x1b[0m (${i + 1}/${DEMO_ROUTES.length}) — CAPTURE: measuring sections desktop+mobile, capturing assets, classifying dynamics`);
    await sleep(1600); if (mockAbort) return;
    wf(d, 'contract.json', demoContract(r));
    const hash = contractHash(path.join(d, 'contract.json'));
    wf(d, 'assets.json', { page: r, contractHash: hash, assetPass: true, assets: [] });
    wf(d, 'dynamics.json', { page: r, contractHash: hash, dynamicsPass: true, mustClassify: [] });
    wf(d, 'interactions.md', `# ${r} interactions\n`);
    push(`\x1b[32m  ✓ ${r}: contract + assets + dynamics validated\x1b[0m`);
    await sleep(700);
  }
  push(`\n\x1b[32m[plan] DONE\x1b[0m — every route has a validated evidence pack. Planning complete; Execute is unlocked.`);
}
async function mockExecute(options = {}) {
  let routes = [];
  try { routes = readFileSync(path.join(MIGRATIONS, '_queue.tsv'), 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')).map((l) => l.split('\t')[0]).filter(Boolean); } catch {}
  if (!routes.length) routes = DEMO_ROUTES;
  push(`$ scripts/ralph.sh${options.oneGo ? ' --one-go' : ''} --provider ${options.provider || 'claude'}   \x1b[2m# ${runConfigLabel(options)} · DEMO MODE — simulated, no real agents\x1b[0m`);
  for (let i = 0; i < routes.length; i++) {
    if (mockAbort) return;
    const r = routes[i], d = path.join(MIGRATIONS, r);
    push(`\n\x1b[35m━━ ${r} ━━━━━━━━━━━━━━━━━━━━\x1b[0m`);
    push(`\x1b[36m[ralph]\x1b[0m BUILD ${r}: scaffolding sections + wiring assets, deploying to preview theme`);
    await sleep(1600); if (mockAbort) return;
    wf(d, 'visual-deltas.md', `# ${r} visual deltas\n## desktop\n- [ ] hero: height 812 vs source 800 (+12)\n- [ ] header: logo 8px low\n`);
    push(`\x1b[33m[ralph]\x1b[0m CONVERGE ${r}: contract-diff found 2 deltas → nudging tokens…`);
    await sleep(1700); if (mockAbort) return;
    wf(d, 'visual-deltas.md', `# ${r} visual deltas\n## desktop\n- [x] hero within tolerance\n- [x] header within tolerance\n## mobile\n- [x] all sections within tolerance\n`);
    wf(d, 'interactions.md', `# ${r} interactions\n- [ ] [dyn] nav dropdown — REBUILD + verify motion\n`);
    push(`\x1b[36m[ralph]\x1b[0m INTERACTIONS ${r}: rebuilding nav dropdown, testing open/close + focus`);
    await sleep(1500); if (mockAbort) return;
    wf(d, 'interactions.md', `# ${r} interactions\n- [x] nav dropdown verified (motion + a11y)\n`);
    push(`\x1b[34m[ralph]\x1b[0m GATE ${r}: running contract-diff + tests…`);
    await sleep(1500); if (mockAbort) return;
    if (i === 1) { // demo a BLOCKED pause on the 2nd page — cleared from the UI
      mkdirSync(path.dirname(BLOCKED), { recursive: true });
      writeFileSync(BLOCKED, `BLOCKED — ${r}\n\nGATE needs a custom page record at /${r} before it can pass. Creating one is a one-time\nadmin action (session login), so the loop paused instead of guessing.\n\nRESOLVE:\n  1) node scripts/ensure-admin-cdp.mjs         # log in once\n  2) node scripts/create-page.mjs "${r}" ${r}   # create the /${r} route record\nThen click “I fixed it — clear & continue”.\n`);
      push(`\n\x1b[31m[ralph] ✋ BLOCKED on ${r}\x1b[0m — needs a one-time admin page-record. Loop paused; clear it in the panel to resume.`);
      while (existsSync(BLOCKED) && !mockAbort) await sleep(400);
      if (mockAbort) return;
      push(`\x1b[32m[ralph]\x1b[0m unblocked — resuming ${r}`);
      await sleep(500);
    }
    wf(d, 'reports/final.md', `# ${r} gate\nvisualPass=true — all deltas within tolerance, tests green.\n`);
    push(`\x1b[36m[ralph]\x1b[0m VISUAL-VERIFY ${r}: eye-level side-by-side vs source (desktop + mobile)`);
    await sleep(1500); if (mockAbort) return;
    wf(d, 'reports/visual-verify.md', `# ${r} visual-verify\nPASS — indistinguishable from source at a glance.\n`);
    writeDemoGate(d);
    push(`\x1b[32m  ✓ ${r} DONE — parity reached, gate green\x1b[0m`);
    await sleep(700);
  }
  if (mockAbort) return;
  push(`\n\x1b[32m[ralph] DONE\x1b[0m — all ${routes.length} pages migrated + gate-verified. 🎉`);
}
async function mockFollowUp(request, options = {}) {
  push(`$ scripts/follow-up.sh --provider ${options.provider || 'claude'}   \x1b[2m# ${runConfigLabel(options)} · DEMO MODE — simulated\x1b[0m`);
  await sleep(600); if (mockAbort) return;
  push(`\x1b[36m[follow-up]\x1b[0m loading AGENT_GUIDE.md, migration evidence, tests, and affected implementation…`);
  await sleep(900); if (mockAbort) return;
  push(`\x1b[36m[follow-up]\x1b[0m request: ${request.replace(/\s+/g, ' ').slice(0, 180)}`);
  await sleep(1100); if (mockAbort) return;
  push(`\x1b[34m[follow-up]\x1b[0m deploying preview, running focused tests, then re-gating the sealed queue…`);
  await sleep(1200); if (mockAbort) return;
  push(`\x1b[32m[follow-up] DONE\x1b[0m — request implemented, queue re-verified, commit pushed.`);
}
function startMock(res, k, source, options = {}) {
  if (child || mockRunning) { res.writeHead(409, json()).end(JSON.stringify({ error: 'A run is already in progress. Stop it first.' })); return; }
  kind = k; startedAt = Date.now(); outputLog.reset(); mockRunning = true; mockAbort = false;
  (k === 'plan' ? mockPlan(source, options) : k === 'execute' ? mockExecute(options) : mockFollowUp(source, options))
    .catch((e) => push(`[demo error] ${e.message}`))
    .finally(() => { mockRunning = false; kind = null; startedAt = null; });
  res.writeHead(200, json()).end(JSON.stringify({ ok: true, kind, demo: true }));
}

// ---- spawn a skeleton script, stream its output -----------------------------
function runConfigLabel(options = {}) {
  return `model=${options.model || 'environment/default'} · effort=${options.effort || 'environment/default'}`;
}

function run(res, k, cmd, args, options = {}, stdinText = null) {
  if (child || mockRunning) { res.writeHead(409, json()).end(JSON.stringify({ error: 'A run is already in progress. Stop it first.' })); return; }
  kind = k; startedAt = Date.now(); outputLog.reset();
  // A clicked run cannot answer permission prompts. The centralized provider runner
  // maps this opt-in to the selected CLI. Use the panel only in a dedicated repo/VM.
  const env = agentEnvironment(process.env, options);
  if (!env.AGENT_UNATTENDED) env.AGENT_UNATTENDED = '1';
  push(`$ ${cmd} ${args.join(' ')}   # ${runConfigLabel(options)}`);
  const launchedKind = k;
  const launched = spawn(cmd, args, { cwd: ROOT, env, detached: true }); // own process group → Stop kills script + selected agent + formatter
  child = launched;
  const stdout = outputLog.writer();
  const stderr = outputLog.writer();
  launched.stdout.on('data', (data) => stdout.write(data));
  launched.stderr.on('data', (data) => stderr.write(data));
  if (stdinText != null) {
    launched.stdin.on('error', (error) => { if (error.code !== 'EPIPE') push(`[stdin error] ${error.message}`); });
    launched.stdin.end(stdinText);
  }
  launched.on('error', (error) => push(`[spawn error] ${error.message} — is the command on PATH?`));
  launched.on('close', (code) => {
    stdout.flush(); stderr.flush();
    push(`[${launchedKind} exited with code ${code}]`);
    if (child === launched) child = null;
    kind = null;
    startedAt = null;
  });
  res.writeHead(200, json()).end(JSON.stringify({ ok: true, kind }));
}
const json = () => ({ 'Content-Type': 'application/json' });

// ---- HTTP -------------------------------------------------------------------
class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let settled = false;
    req.on('data', (chunk) => {
      if (settled) return;
      size += chunk.length;
      if (size > limit) {
        settled = true;
        reject(new HttpError(413, `request body exceeds ${limit} bytes`));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => { if (!settled) resolve(Buffer.concat(chunks)); });
    req.on('error', (error) => { if (!settled) reject(error); });
  });
}
async function jsonBody(req) {
  if (!String(req.headers['content-type'] || '').toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'Content-Type must be application/json');
  }
  const raw = (await readBody(req, JSON_LIMIT)).toString('utf8');
  try { return JSON.parse(raw || '{}'); } catch { throw new HttpError(400, 'Malformed JSON body'); }
}
function allowedHost(value) {
  try {
    const parsed = new URL(`http://${value}`);
    return ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname) && Number(parsed.port || 80) === PORT;
  } catch { return false; }
}
function requireMutationAuth(req) {
  if (!allowedHost(req.headers.host || '')) throw new HttpError(403, 'Invalid Host header');
  const origin = String(req.headers.origin || '');
  let validOrigin = false;
  try {
    const parsed = new URL(origin);
    validOrigin = ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname) &&
      Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80)) === PORT && parsed.protocol === 'http:';
  } catch {}
  if (!validOrigin) throw new HttpError(403, 'Same-origin request required');
  if (req.headers['x-migrate-csrf'] !== CSRF_TOKEN) throw new HttpError(403, 'Invalid CSRF token');
}
function sendError(res, error) {
  if (res.headersSent) { res.end(); return; }
  const status = error instanceof HttpError ? error.status : 500;
  res.writeHead(status, json()).end(JSON.stringify({ error: status === 500 ? 'Internal server error' : error.message }));
  if (status === 500) console.error(error);
}

async function handleRequest(req, res) {
  if (!allowedHost(req.headers.host || '')) throw new HttpError(403, 'Invalid Host header');
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const p = url.pathname;

  if (req.method === 'POST') requireMutationAuth(req);

  if (p === '/' || p === '/index.html') {
    try {
      const profileJson = JSON.stringify(AGENT_PROFILES).replace(/</g, '\\u003c');
      const html = readFileSync(path.join(DIR, 'index.html'), 'utf8')
        .replace('__MIGRATE_CSRF_TOKEN__', CSRF_TOKEN)
        .replace('__MIGRATE_AGENT_PROFILES__', profileJson);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }).end(html);
    }
    catch { res.writeHead(500).end('index.html missing'); }
    return;
  }

  if (p === '/api/status') {
    const blocked = readBlocked();
    res.writeHead(200, json()).end(JSON.stringify({
      running: !!child || mockRunning, kind: (child || mockRunning) ? kind : null, startedAt, demo: DEMO,
      stages: STAGES, pages: scanPages(), logBase: outputLog.base, logLen: outputLog.next,
      blocked, plan: planStatus(), followUp: followUpStatus(MIGRATIONS, { cwd: ROOT, blocked: !!blocked }),
      referenceBuilds: listReferenceBuilds(),
    }));
    return;
  }

  if (p === '/api/log') {
    const since = Math.max(0, Number(url.searchParams.get('since') || 0));
    res.writeHead(200, json()).end(JSON.stringify(outputLog.read(since)));
    return;
  }

  if (p === '/api/learnings') {
    let content = null; try { content = readFileSync(LEARNINGS, 'utf8'); } catch {}
    res.writeHead(200, json()).end(JSON.stringify({ content }));
    return;
  }

  if (req.method === 'POST' && p === '/api/plan') {
    const body = await jsonBody(req);
    const checked = validateRunConfig(body);
    if (checked.error) { res.writeHead(400, json()).end(JSON.stringify({ error: checked.error })); return; }
    const { source = '', mode = 'site', referenceBuild = '' } = body;
    const { provider, model, effort } = checked.value;
    const cleanSource = typeof source === 'string' ? source.trim() : '';
    if (!['site', 'reference', 'resume'].includes(mode)) { res.writeHead(400, json()).end(JSON.stringify({ error: 'Mode must be site, reference, or resume.' })); return; }
    const options = { provider, model, effort };
    if (DEMO) return startMock(res, 'plan', mode === 'reference' ? `reference/${referenceBuild || '<local build>'}` : (cleanSource || 'https://demo-source.example'), options);
    const args = ['--provider', provider];
    if (mode === 'reference') {
      if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(referenceBuild) || !listReferenceBuilds().includes(referenceBuild)) {
        res.writeHead(400, json()).end(JSON.stringify({ error: 'Choose a valid reference build.' }));
        return;
      }
      return run(res, 'plan', 'scripts/plan.sh', [...args, '--from-reference', referenceBuild], options);
    }
    if (mode === 'resume') return run(res, 'plan', 'scripts/plan.sh', args, options);
    if (!cleanSource) { res.writeHead(400, json()).end(JSON.stringify({ error: 'Enter a source URL.' })); return; }
    return run(res, 'plan', 'scripts/plan.sh', [...args, cleanSource], options);
  }

  if (req.method === 'POST' && p === '/api/execute') {
    const checked = validateRunConfig(await jsonBody(req));
    if (checked.error) { res.writeHead(400, json()).end(JSON.stringify({ error: checked.error })); return; }
    const { provider, execution, model, effort } = checked.value;
    if (readBlocked()) {
      res.writeHead(409, json()).end(JSON.stringify({ error: 'Execution is blocked. Resolve .ralph/BLOCKED and clear it first.' }));
      return;
    }
    const planned = planStatus();
    if (!planned.complete) {
      res.writeHead(409, json()).end(JSON.stringify({ error: `Planning is incomplete (${planned.validated}/${planned.queued} queued pages validated). Run Plan first.` }));
      return;
    }
    const options = { provider, model, effort, oneGo: execution === 'one-go' };
    if (DEMO) return startMock(res, 'execute', '', options);
    return run(res, 'execute', 'scripts/ralph.sh', ['--provider', provider, ...(options.oneGo ? ['--one-go'] : [])], options);
  }

  if (req.method === 'POST' && p === '/api/follow-up') {
    const body = await jsonBody(req);
    const checked = validateRunConfig(body);
    if (checked.error) { res.writeHead(400, json()).end(JSON.stringify({ error: checked.error })); return; }
    const request = validateFollowUpRequest(body);
    if (request.error) { res.writeHead(400, json()).end(JSON.stringify({ error: request.error })); return; }
    const blocked = readBlocked();
    const readiness = followUpStatus(MIGRATIONS, { cwd: ROOT, blocked: !!blocked });
    if (!readiness.ready) {
      res.writeHead(409, json()).end(JSON.stringify({ error: readiness.reason }));
      return;
    }
    const { provider, model, effort } = checked.value;
    const options = { provider, model, effort };
    if (DEMO) return startMock(res, 'follow-up', request.value, options);
    return run(res, 'follow-up', FOLLOW_UP_SCRIPT, ['--provider', provider], options, request.value);
  }

  // Drag-and-drop a local reference build: the browser posts one file at a time with its relative
  // path; we write it under reference/<build>/… (path-traversal guarded, binary-safe).
  if (req.method === 'POST' && p === '/api/upload-reference') {
    const rel = String(url.searchParams.get('path') || '').replace(/^\/+/, '');
    const dest = path.resolve(REFROOT, rel);
    const segments = rel.split('/');
    if (!rel || segments.some((segment) => !segment || segment === '.' || segment === '..') || !dest.startsWith(path.resolve(REFROOT) + path.sep)) {
      res.writeHead(400, json()).end(JSON.stringify({ error: 'bad path' })); return;
    }
    const buf = await readBody(req, UPLOAD_LIMIT);
    mkdirSync(REFROOT, { recursive: true });
    let current = REFROOT;
    for (const segment of segments.slice(0, -1)) {
      current = path.join(current, segment);
      if (existsSync(current)) {
        const stat = lstatSync(current);
        if (stat.isSymbolicLink() || !stat.isDirectory()) throw new HttpError(400, 'upload path contains a symlink or non-directory');
      } else {
        mkdirSync(current);
      }
    }
    if (existsSync(dest) && lstatSync(dest).isSymbolicLink()) throw new HttpError(400, 'upload target is a symlink');
    const fd = openSync(dest, constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | (constants.O_NOFOLLOW || 0), 0o600);
    try { writeFileSync(fd, buf); } finally { closeSync(fd); }
    res.writeHead(200, json()).end(JSON.stringify({ ok: true, path: rel, bytes: buf.length }));
    return;
  }

  if (req.method === 'POST' && p === '/api/unblock') {
    let removed = false;
    try { unlinkSync(BLOCKED); removed = true; push('\n[.ralph/BLOCKED cleared — you confirmed it is resolved]'); } catch {}
    res.writeHead(200, json()).end(JSON.stringify({ ok: true, removed }));
    return;
  }

  if (req.method === 'POST' && p === '/api/stop') {
    if (mockRunning) { mockAbort = true; push('\n[stop requested — demo run aborted]'); }
    if (child) {
      const target = child;
      const pid = target.pid;
      push('\n[stop requested — terminating process group]');
      // negative pid = the whole process group (runner + selected agent + formatter)
      try { process.kill(-pid, 'SIGTERM'); } catch { try { target.kill('SIGTERM'); } catch {} }
      setTimeout(() => {
        if (child !== target || target.exitCode != null) return;
        try { process.kill(-pid, 'SIGKILL'); } catch {}
      }, 2500);
    }
    res.writeHead(200, json()).end(JSON.stringify({ ok: true }));
    return;
  }

  res.writeHead(404, json()).end(JSON.stringify({ error: 'not found' }));
}

const server = createServer((req, res) => {
  handleRequest(req, res).catch((error) => sendError(res, error));
});

// Only start listening when run directly (so tests can import the pure helpers below).
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`\n  Migrate control panel → http://localhost:${PORT}   (local-only, bound to 127.0.0.1)\n  serving the skeleton at ${ROOT}\n  Ctrl-C to stop.\n`);
  });
}

export { pageState, scanPages, STAGES };
