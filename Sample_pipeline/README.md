# Harness Engineering Playbook — a real-world example (Shopify theme migration)

This repository is a **teaching-grade, runnable example of harness engineering**: the environment you build *around*
an AI coding agent so it can do a real job — repeatably, with evidence, with brakes — instead of chatting. The job
here is migrating websites onto a Shopify Online Store 2.0 theme, page by page, 1:1. **The theme under `theme/` is the
product. Everything else is the harness.** Shopify is only the worked example: every file is annotated so you (and your
agent) can lift the pattern into any project.

It is a short-form twin of a production harness we run for a different platform; the MDs are condensed, the code is
reused or adapted and explained in comments, and every platform fact carries a trust mark (✅ verified here · ⚠️ doc-derived).

> Companion video: *From chatbots to agents — build the harness* (FlyRank internship, BE track W8). The first video,
> *Build the Systems That Build Software*, introduces the vocabulary used here: agent, MD files, MCP, tools, the Ralph loop.

## The harness in one picture
```
AGENT_GUIDE.md  ── router: job, precedence, access, read-before, read-on-demand, non-negotiables
CLAUDE.md / AGENTS.md ── thin provider adapters → the router          .claude/rules/* ── path-scoped rules that load themselves
docs/ ── principles (read first) · craft · ops · runbooks · contract · trust model · troubleshooting · how-it-works
prompts/ ── PLAN (capture) · PROMPT (the state machine) · PLAN_ALL / IMPLEMENT_ALL (one-go) · FOLLOW_UP
scripts/ ── agent-runner (provider plug) · plan.sh · ralph.sh · migrate.sh · follow-up.sh · retro · self-tests · migration-state
           visual-diff/ (capture → contract-diff = THE GATE → validators · reference server · tagged Chromium)
           theme-baseline (STEP 0: init/snapshot/catalog/push-target/reset) · shopify-admin-token / shopify-admin ·
           create-page|blog|menu|redirects · ensure-admin-cdp · sync-theme-branch
migrations/ ── _queue.tsv (sealed) · _scope.json · _brief.md · _sections.md · <page>/ evidence packs (contract, assets,
           dynamics, visual-deltas, gate.json, interactions, reports)           reference/ ── local sources (design exports, static HTML)
.ralph/ (ignored) ── ACTIVE_PAGE · BLOCKED · runs/<id>/ logs · token cache          tests/ ── back-pressure + offline harness proofs
demo/ ── the control panel (Plan / Execute / Follow-up buttons over the real scripts; DEMO_MODE=1 simulates a run)
theme/ ── Dawn (MIT) + the migrated, brand-neutral sections                        LEARNINGS.md ── the notebook
```

## Quick start
```bash
nvm use && bun install && bunx playwright install chromium     # Node 22, deps, browser for the harness
npm i -g @shopify/cli && shopify auth login                     # CLI (one-time device/browser auth)
cp .env.example .env                                             # store, UNPUBLISHED theme id, app credentials
scripts/theme-baseline.sh snapshot && scripts/theme-baseline.sh catalog > migrations/_sections.md   # STEP 0: the base theme is the baseline + vocabulary
scripts/theme-baseline.sh push-target harness-dev                # push the baseline to a NEW unpublished target → SHOPIFY_THEME_ID
npm run test:orchestration                                       # prove the loop offline (stub agents, every exit path)
```
Then either **one command** — `scripts/migrate.sh https://source-site.com` (Plan, then Execute) — or the phases:
```bash
scripts/plan.sh https://source-site.com            # live URL → discovery → sealed queue → one CAPTURE worker per page
scripts/plan.sh --from-reference my-design          # a design-tool export / static HTML under reference/my-design/
scripts/plan.sh --page https://source-site.com/about
scripts/ralph.sh                                    # BUILD → CONVERGE → INTERACTIONS → GATE → VISUAL-VERIFY per page
scripts/ralph.sh --one-go                           # same contract, one invocation for the whole queue
printf 'Make the hero CTA amber' | scripts/follow-up.sh   # post-migration change through the same gates
scripts/ralph-retro.sh                              # learn from the run logs, improve the harness, commit
```
Or click: `bun dev` → http://localhost:4599 (local-only control panel; `DEMO_MODE=1 bun dev` to watch a simulated run).
Provider: `--provider claude|codex|custom` or `AGENT_PROVIDER` (`scripts/agent-runner.sh`).

## Where to read next
- Non-engineer tour: `docs/how-it-works.md` · Agent entry: `AGENT_GUIDE.md` · Evidence pack: `docs/contract-and-evidence.md`
- Loop + exit codes: `docs/principles/loop-and-exit.md` · Trust model: `docs/validation-status.md`
- Panel: `demo/README.md` · Reference sources: `reference/README.md` · Optional next layer: `docs/fleet/README.md`

## Safety
Work deploys **only** to the unpublished theme in `SHOPIFY_THEME_ID`; publishing is a separate explicit step. Unattended
runs (`AGENT_UNATTENDED=1`) belong in a sandbox/VM. Secrets live in `.env` (ignored) and the `.ralph/` token cache.

License: MIT (see `LICENSE`); Dawn © Shopify, MIT (`theme/LICENSE.md`).
