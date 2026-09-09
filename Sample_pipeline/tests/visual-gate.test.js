import { test, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pageComplete, pageGated, validatePack } from '../scripts/migration-state.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const script = (name) => path.join(REPO, 'scripts', 'visual-diff', name);
const goodHtml = `<!doctype html><meta charset="utf-8"><style>
  html,body{margin:0}main{width:100%;height:400px;display:flex;align-items:center;justify-content:center;
  color:rgb(255,255,255);background-color:rgb(18,52,86);font:700 32px/1.2 Arial,sans-serif}
</style><main><h1>Frozen target</h1></main>`;

function runNode(args, cwd) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, args, { cwd, env: { PATH: process.env.PATH } });
    let stdout = '', stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

test('real browser gate passes identical pages and fails a deliberate regression', async () => {
  test.setTimeout(120_000);
  let replicaHtml = goodHtml;
  const server = createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(req.url?.startsWith('/replica') ? replicaHtml : goodHtml);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const root = mkdtempSync(path.join(tmpdir(), 'visual-gate-'));
  const pageDir = path.join(root, 'migrations', 'home');
  mkdirSync(path.join(pageDir, 'reports'), { recursive: true });
  const contractPath = path.join(pageDir, 'contract.json');
  writeFileSync(contractPath, JSON.stringify({
    page: 'home',
    source: `http://127.0.0.1:${port}/source`,
    preview: `http://127.0.0.1:${port}/replica`,
    viewports: { desktop: 800 },
    sections: [{
      key: 'main', class: 'content', sourceSelector: 'main', replicaSelector: 'main',
      mustMatch: ['geometry', 'type', 'color'], targets: {},
    }],
  }, null, 2));

  try {
    for (const command of [
      [script('capture-source.mjs'), contractPath],
      [script('capture-assets.mjs'), contractPath],
      [script('capture-dynamics.mjs'), contractPath],
    ]) {
      const result = await runNode(command, root);
      expect(result.code, `${command[0]}\n${result.stdout}\n${result.stderr}`).toBe(0);
    }
    writeFileSync(path.join(pageDir, 'interactions.md'), '# interactions\n');
    writeFileSync(path.join(pageDir, 'reports', 'final.md'), 'PASS\n');
    writeFileSync(path.join(pageDir, 'reports', 'visual-verify.md'), 'PASS\n');
    expect(validatePack(pageDir, { expectedSource: `http://127.0.0.1:${port}/source` }).pass).toBe(true);

    const passing = await runNode([script('contract-diff.mjs'), contractPath], root);
    expect(passing.code, `${passing.stdout}\n${passing.stderr}`).toBe(0);
    expect(JSON.parse(readFileSync(path.join(pageDir, 'gate.json'), 'utf8')).visualPass).toBe(true);
    expect(pageGated(pageDir, { cwd: root })).toBe(true);
    expect(pageComplete(pageDir, { cwd: root })).toBe(true);

    replicaHtml = goodHtml.replace('rgb(18,52,86)', 'rgb(160,20,20)');
    const failing = await runNode([script('contract-diff.mjs'), contractPath], root);
    expect(failing.code, `${failing.stdout}\n${failing.stderr}`).toBe(1);
    expect(JSON.parse(readFileSync(path.join(pageDir, 'gate.json'), 'utf8')).visualPass).toBe(false);
    expect(readFileSync(path.join(pageDir, 'visual-deltas.md'), 'utf8')).toContain('background-color');
    expect(pageGated(pageDir, { cwd: root })).toBe(false);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    rmSync(root, { recursive: true, force: true });
  }
});
