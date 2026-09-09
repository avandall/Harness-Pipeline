# Migrate — local control panel

Choose a provider, model, effort, and execution mode; click **Plan**, then **Execute** (or enable auto-execute), and
watch real page progress plus the selected CLI's live stream. It's a thin web UI over the skeleton's own scripts —
no mocked magic, nothing new to learn.

```
┌─ SETUP (once) ─────────────┐   ┌─ RUN ───────────┐   ┌─ USE (in the browser) ──────────────┐
│ .env · store · app · sl    │ → │ bun dev         │ → │ ① paste URL / pick reference build   │
│ login · SHOPIFY_THEME_ID · deps │   │ (→ :4599)       │   │ ② click Plan   → CAPTURE per page    │
└────────────────────────────┘   └─────────────────┘   │ ③ click Execute→ BUILD→…→VISUAL-VERIFY│
                                                        │ ④ after DONE, add follow-up tweaks  │
                                                        │ ⑤ watch stages + live stream        │
                                                        └─────────────────────────────────────┘
```

---

## 1. Setup (once)

```bash
# a) deps (from the repo root)
nvm use                                 # Node 22 (`nvm install` once if needed)
bun install                             # or: npm install
bunx playwright install chromium        # or: npx playwright install chromium
npm i -g @shopify/cli                   # the Shopify CLI (binary: `shopify`)
cp .env.example .env

# b) Shopify store + Admin API access  → fill .env
#    - a store (a dev/test store is fine)     → SHOPIFY_STORE, STOREFRONT_PASSWORD
#    - an app in the Dev Dashboard with the content/pages/navigation/themes write scopes
#                                             → SHOPIFY_CLIENT_ID, SHOPIFY_CLIENT_SECRET (token minted by scripts/shopify-admin-token.mjs)
shopify auth login                          # browser/device OAuth for the CLI (separate from the Admin API token)
shopify theme list --store $SHOPIFY_STORE   # pick an UNPUBLISHED theme id → SHOPIFY_THEME_ID in .env
#    (no unpublished theme yet?  shopify theme push --unpublished --theme harness-dev --path theme --store $SHOPIFY_STORE)
```

At least one provider CLI must be installed and logged in. Verify with `claude --version` or `codex --version`.
The shared launcher can resolve shell-managed CLIs even when a GUI starts the panel with a reduced `PATH`.
If the panel still cannot resolve a CLI that your terminal can, set `CLAUDE_BIN` or `CODEX_BIN` to the absolute
path printed by `command -v claude` or `command -v codex` before launching the panel.
For another JSONL/stdin CLI, launch the panel with `AGENT_PROVIDER=custom AGENT_BIN=/path/to/cli` and configure
`AGENT_FLAGS`.

## 2. Run

```bash
bun dev                # → http://localhost:4599   (or: bun demo/server.mjs  /  npm run panel)
```

Open **<http://localhost:4599>** (local-only — bound to `127.0.0.1`, not your network). The **First-time
setup** drawer in the UI repeats the checklist above.

## 3. Use

| You do | It runs | You see |
|---|---|---|
| Choose **Claude / Codex / Custom**, model, and effort | `scripts/agent-runner.sh` with per-run `AGENT_MODEL` / `AGENT_EFFORT` | one provider-neutral stream and result contract; provider presets plus a custom model ID |
| Choose **Loop / One go** | `scripts/ralph.sh` per-page invocations / one full-queue invocation | Plan stays unchanged; only Execute switches mode |
| Enable **Auto-execute after Plan** | starts `scripts/ralph.sh` once the entire sealed Plan validates | one click for Plan → Execute; an old complete plan never triggers it by itself |
| Paste a URL → **Plan** | `scripts/plan.sh <url>` | crawl → queue → a CAPTURE evidence pack per route; pages appear as tiles |
| **Local reference build** → choose build → **Plan** | `scripts/plan.sh --from-reference <build>` | plans the selected `reference/<build>/` (no URL) |
| **Execute** | `scripts/ralph.sh` | the runner advances each page **BUILD → CONVERGE → INTERACTIONS → GATE → VISUAL-VERIFY → DONE** |
| Enter **Follow-up tweaks** after every page is DONE | `scripts/follow-up.sh` with `prompts/PROMPT.md` + the follow-up override + request | one context-complete implementation run; tests/re-gates, commits, and pushes before success |
| **Stop** | kills the whole process tree | run halts immediately |

- **Pages** tiles + **Stage pipeline** are read live from `migrations/<page>/` — the same `gate.json` /
  `visual-deltas.md` signals `ralph.sh` itself gates on. Progress is real, not a timer.
- **Execute is locked until Plan is complete:** `migrations/_queue.tsv` must exist and every queued evidence pack
  must pass the same shared validator used by `plan.sh` and `ralph.sh`.
- **Follow-up is locked until every queued page is machine-complete.** Its textarea autosaves a local browser draft;
  submission uses the currently selected provider/model/effort and never changes the sealed route scope.
- **Live output** is the child's actual stdout — the selected provider's JSONL stream (via `agent-format.mjs`), rendered
  as a colored terminal.

## How it works (and why a server)

A browser page can't spawn `plan.sh`/`ralph.sh`/`follow-up.sh`, so `demo/server.mjs` — a tiny **dependency-free** Node/Bun
process **bound to `127.0.0.1` only** (that's why the URL is `localhost`, never a network address) — runs them as children and exposes `/api/status`, `/api/log`,
`/api/plan`, `/api/execute`, `/api/follow-up`, `/api/stop`. It runs **your** CLI on **your** machine; never expose it.
Mutation endpoints also require an exact local Host/Origin plus a per-process CSRF token; request bodies are bounded,
and reference uploads reject traversal and symlink escapes.
It opts the centralized adapter into unattended provider execution so a click does not stall on a permission prompt.
Provider/model/effort choices are remembered in the browser. Empty model/effort selections preserve values exported
when the panel started (or the runner's defaults); explicit UI selections override them only for the spawned run.
Run the panel only in a dedicated repo/VM; override with `AGENT_FLAGS`, `CLAUDE_FLAGS`, or `CODEX_FLAGS`. It is not
part of the theme and never deploys itself.

## Troubleshooting

- **Execute is blocked:** resolve the instructions shown from `.ralph/BLOCKED`, then use **clear & continue**.
- **"not found for provider":** verify the CLI in a terminal. If needed, export `CLAUDE_BIN` or `CODEX_BIN`
  to its absolute path (see Setup). The panel's shared launcher automatically checks your login-shell PATH.
- **"spawn error … command not found":** a non-agent dependency such as `sl` is not on PATH (see Setup).
- **Preview shows nothing:** the store's plan is inactive/frozen — the storefront must be live to render.
- **Stop leaves nothing running:** verify with `pgrep -fl "scripts/ralph.sh"` (should be empty).

## Tests

`bunx playwright test tests/demo-panel.test.js` (or `npm test`) — covers stage derivation, the API, the UI,
and the ANSI→terminal renderer.
