// Static file server for a LOCAL reference build used as a 1:1 migration source of truth.
//
// When you migrate from a provided HTML/CSS/JS bundle (not a live competitor URL), drop it under
// REF_ROOT/<page>/ (default: reference/<page>/) and set the contract's source to the __REF__
// placeholder, e.g. "source": "__REF__/home/index.html". The visual-diff scripts resolve __REF__ to
// this server's base URL (scripts/visual-diff/lib.mjs → resolveSource) and load the reference exactly
// like any live source — so capture-source / capture-assets / capture-dynamics / contract-diff all run
// UNCHANGED, and the match is byte-stable and offline (no CDN, no password gate, no third-party popups).
//
// Mirrors scripts/ensure-admin-cdp.mjs: idempotent reuse-or-launch on a fixed port.
//
// Modes:
//   node scripts/visual-diff/serve-reference.mjs           → ensure the server is up; print base URL; exit 0
//   node scripts/visual-diff/serve-reference.mjs --serve    → run the blocking static server (foreground)
//
// Env (.env): REF_PORT (default 9540) · REF_ROOT (default "reference", resolved from CWD)
// Requires: Node >= 21 (global fetch). Use nvm 22.
import http from 'node:http';
import { existsSync, statSync, createReadStream } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from './lib.mjs';

const env = loadEnv();
const PORT = Number(env.REF_PORT || 9540);
const ROOT = path.resolve(env.REF_ROOT || 'reference');

export const refBaseUrl = (e = env) => `http://127.0.0.1:${Number(e.REF_PORT || 9540)}`;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.webp': 'image/webp', '.gif': 'image/gif', '.avif': 'image/avif', '.ico': 'image/x-icon',
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.ogg': 'video/ogg',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf', '.eot': 'application/vnd.ms-fontobject',
  '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml; charset=utf-8', '.webmanifest': 'application/manifest+json',
};

// the blocking static server, rooted at ROOT, with a path-traversal guard.
function runServer() {
  const server = http.createServer((req, res) => {
    try {
      const urlPath = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
      if (urlPath === '/__harness_reference_health__') {
        res.writeHead(200, { 'content-type': 'application/json', 'x-harness-reference-server': '1', 'cache-control': 'no-store' });
        return res.end(JSON.stringify({ ok: true, root: ROOT }));
      }
      let fp = path.normalize(path.join(ROOT, urlPath));
      if (fp !== ROOT && !fp.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end('forbidden'); }
      if (existsSync(fp) && statSync(fp).isDirectory()) fp = path.join(fp, 'index.html');
      if (!existsSync(fp) || !statSync(fp).isFile()) {
        res.writeHead(404, { 'content-type': 'text/html; charset=utf-8' });
        return res.end(`<!doctype html><h1>404 — reference not found</h1><p>${urlPath}</p>`);
      }
      res.writeHead(200, {
        'content-type': MIME[path.extname(fp).toLowerCase()] || 'application/octet-stream',
        'access-control-allow-origin': '*',
        'cache-control': 'no-store',
      });
      createReadStream(fp).pipe(res);
    } catch (e) { res.writeHead(500); res.end('serve-reference error: ' + e.message); }
  });
  server.on('error', (e) => { console.error('serve-reference: listen failed —', e.message); process.exit(2); });
  server.listen(PORT, '127.0.0.1', () => console.log(`serve-reference: serving ${ROOT} at ${refBaseUrl()}`));
}

// Reuse only this harness's server. A random process listening on REF_PORT is not a valid source.
const portUp = async (port = PORT, expectedRoot = ROOT) => {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/__harness_reference_health__`);
    const body = await response.json();
    return response.ok && response.headers.get('x-harness-reference-server') === '1' && body.root === expectedRoot;
  } catch { return false; }
};

// Idempotent: reuse the running server, else spawn `--serve` detached and wait for the port. Returns the base URL.
export async function ensureReferenceServer(e = env) {
  const port = Number(e.REF_PORT || 9540);
  const expectedRoot = path.resolve(e.REF_ROOT || 'reference');
  if (await portUp(port, expectedRoot)) return refBaseUrl(e);
  const self = fileURLToPath(import.meta.url);
  spawn(process.execPath, [self, '--serve'], {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, REF_PORT: String(port), REF_ROOT: expectedRoot },
  }).unref();
  for (let i = 0; i < 50; i++) { if (await portUp(port, expectedRoot)) return refBaseUrl(e); await new Promise((r) => setTimeout(r, 200)); }
  throw new Error(`serve-reference: server did not come up on port ${port} within 10s`);
}

// --- run as a script (not when imported) ---
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  if (process.argv.includes('--serve')) {
    runServer();
  } else {
    ensureReferenceServer()
      .then((url) => { console.log(url); process.exit(0); })
      .catch((err) => { console.error(err.message); process.exit(2); });
  }
}
