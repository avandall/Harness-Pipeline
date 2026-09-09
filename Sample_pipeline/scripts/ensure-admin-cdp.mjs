// Ensure a LOGGED-IN Shopify admin Chrome is available on the CDP port — the prerequisite for
// the few ADMIN-ONLY settings that have no public Admin API (the classic example: the homepage
// title/meta description under Online Store > Preferences). Everything with a documented Admin
// API (pages, blogs, menus, redirects, themes) goes through the token path first — see
// docs/ops/environment-setup.md "Access & capabilities". These last-resort tasks drive the real
// admin UI in a browser, so they need the admin's session COOKIES — not SHOPIFY_ADMIN_TOKEN. The
// agent cannot log itself in (no admin creds in .env, and login is interactive); it reuses a
// human's session. This script makes that reuse automatic and self-healing on local:
//   1. if the CDP port is already up → reuse it (idempotent — never relaunches);
//   2. else launch an isolated Chrome on $CDP_PORT with $CDP_PROFILE, opening the admin;
//   3. probe whether that profile's admin session is still valid.
//
// Exit codes (so ralph.sh / the agent can branch deterministically):
//   0  → admin session READY (proceed with the internal-admin task)
//   10 → CDP up but NOT logged in → a Chrome window is open at the admin login; a HUMAN must
//        log in once. The agent should write .ralph/BLOCKED only after documented REST/token
//        paths have already been exhausted.
//   2  → error (Chrome binary missing, port never came up, probe failed)
//
// LOCAL ONLY: this opens a real Chrome window and relies on a desktop + a human login. A hosted
// version of this harness would broker the admin session differently (no desktop at the box).
//
// Usage:  node scripts/ensure-admin-cdp.mjs            (reads SHOPIFY_STORE / CDP_PORT / CDP_PROFILE from .env)
// Requires: Node >= 21 (global WebSocket; use nvm 22 — see LEARNINGS).
import process from 'node:process';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { loadEnv } from './env.mjs';

const env = loadEnv();
const STORE = (env.SHOPIFY_STORE || '').replace(/^https?:\/\//, '').replace(/\/+$/, '');
const PORT = env.CDP_PORT || '9333';
const PROFILE = env.CDP_PROFILE || '/tmp/harness-validate-profile';
const CHROME = env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ADMIN_URL = `https://${STORE}/admin`;

if (!STORE) { console.error('ensure-admin-cdp: SHOPIFY_STORE not set in .env'); process.exit(2); }
if (typeof WebSocket === 'undefined') {
  console.error('ensure-admin-cdp: needs Node >= 21 (global WebSocket). Run: source ~/.nvm/nvm.sh && nvm use 22');
  process.exit(2);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const portUp = async () => { try { return (await fetch(`http://localhost:${PORT}/json/version`)).ok; } catch { return false; } };

// --- 1/2. reuse-or-launch the CDP Chrome ---
if (await portUp()) {
  console.log(`ensure-admin-cdp: reusing existing CDP Chrome on port ${PORT}`);
} else {
  if (!existsSync(CHROME)) { console.error(`ensure-admin-cdp: Chrome not found at "${CHROME}". Set CHROME_BIN in .env.`); process.exit(2); }
  console.log(`ensure-admin-cdp: launching Chrome (profile ${PROFILE}, port ${PORT}) → ${ADMIN_URL}`);
  // Detached + unref'd so the browser outlives this process. A DEDICATED --user-data-dir means a
  // separate Chrome instance that actually honours --remote-debugging-port (the default profile,
  // if already running, would otherwise swallow the args via Chrome's singleton).
  spawn(CHROME, [`--remote-debugging-port=${PORT}`, `--user-data-dir=${PROFILE}`,
    '--no-first-run', '--no-default-browser-check', ADMIN_URL],
    { detached: true, stdio: 'ignore' }).unref();
  let up = false;
  for (let i = 0; i < 30; i++) { if (await portUp()) { up = true; break; } await sleep(1000); }
  if (!up) { console.error('ensure-admin-cdp: CDP port did not come up within 30s'); process.exit(2); }
  await sleep(1500); // let the admin tab begin loading
}

// --- pick (or create) an admin tab ---
const tabs = await (await fetch(`http://localhost:${PORT}/json`)).json();
let tab = tabs.find((t) => t.type === 'page' && /\/admin|admin\.shopify\.com/.test(t.url) && /myshopify\.com|admin\.shopify\.com/.test(t.url))
  || tabs.find((t) => t.type === 'page');
if (!tab) {
  try { tab = await (await fetch(`http://localhost:${PORT}/json/new?${encodeURIComponent(ADMIN_URL)}`, { method: 'PUT' })).json(); }
  catch { tab = await (await fetch(`http://localhost:${PORT}/json/new?${encodeURIComponent(ADMIN_URL)}`)).json(); }
}
if (!tab?.webSocketDebuggerUrl) { console.error('ensure-admin-cdp: no debuggable admin tab on CDP'); process.exit(2); }

// --- 3. probe the session over CDP (plain Chrome DevTools Protocol over WebSocket) ---
const ws = new WebSocket(tab.webSocketDebuggerUrl);
let id = 0; const pend = new Map(); const waiters = new Map();
const send = (m, p = {}) => new Promise((r) => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
const onceEvent = (method, ms) => new Promise((res) => { const to = setTimeout(() => res(false), ms); waiters.set(method, () => { clearTimeout(to); waiters.delete(method); res(true); }); });
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
  else if (m.method && waiters.has(m.method)) waiters.get(m.method)();
};
ws.onerror = () => {};
const opened = await Promise.race([new Promise((r) => { ws.onopen = () => r(true); }), sleep(8000).then(() => false)]);
if (!opened) { console.error('ensure-admin-cdp: WebSocket to the admin tab did not open'); process.exit(2); }

await send('Page.enable');
await send('Runtime.enable');
const loaded = onceEvent('Page.loadEventFired', 10000);
await send('Page.navigate', { url: ADMIN_URL });
await loaded;
await sleep(1800); // SPA settle (admin may client-redirect to a login screen)
const r = await send('Runtime.evaluate', {
  expression: `JSON.stringify({href:location.href,hasPw:!!document.querySelector('input[type=password],input[name=password]'),title:(document.title||'').slice(0,80)})`,
  returnByValue: true,
});
const info = r?.result?.value ? JSON.parse(r.result.value) : {};
ws.close();

// --- verdict ---
const href = info.href || '';
// Shopify redirects <store>.myshopify.com/admin to the unified admin at admin.shopify.com/store/<handle>;
// both count as "on the admin". A login wall lands on accounts.shopify.com or shows a password field.
const onAdmin = new RegExp(`${STORE.replace(/\./g, '\\.')}/admin`).test(href) || /admin\.shopify\.com\/store\//.test(href);
const looksLogin = /accounts\.shopify\.com|login|sign-?in|oauth|sso/i.test(href) || info.hasPw;
if (onAdmin && !looksLogin) {
  console.log(`✅ ensure-admin-cdp: admin session READY on port ${PORT}  (${href})`);
  process.exit(0);
}
console.log(`⚠️ ensure-admin-cdp: NOT logged in — landed on "${href || '?'}"${info.hasPw ? ' (login form present)' : ''}.`);
console.log(`   A Chrome window is open at ${ADMIN_URL}. Log in once, then re-run this script (it will reuse the session).`);
process.exit(10);
