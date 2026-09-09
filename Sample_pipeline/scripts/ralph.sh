#!/usr/bin/env bash
# Provider-neutral Execute runner for Shopify theme migrations (the "Ralph loop": a bounded loop of fresh agent invocations).
#
# Default mode repeatedly runs prompts/PROMPT.md in fresh invocations. --one-go sends
# that same canonical prompt plus prompts/IMPLEMENT_ALL.md as one combined prompt, exactly
# once, and requires that invocation to finish the queue.
#
# Exit conditions (priority order):
#   1. Done       — every queued page gated (gate.json + final + visual verify) -> exit 0
#   2. Blocked    — .ralph/BLOCKED exists                          -> exit 3
#   3. Max iters  — RALPH_MAX_ITERATIONS reached (default 200)     -> exit 4
#   4. Budget     — cumulative cost > RALPH_MAX_BUDGET_USD ($500)  -> exit 5
#   5. Stuck      — no new commit for RALPH_NO_PROGRESS loops (200)-> exit 6
#   6. Compacted  — task auto-compacted mid-run (context exhausted) -> exit 7
#   7. Provider/API failure — failed turn/process, or repeated 5xx -> exit 8
#
# Transient provider/API errors do NOT count toward the stuck breaker — the loop
# backs off and retries; only a sustained run of them (RALPH_API_MAX) stops it (exit 8).
#
# Usage:  scripts/ralph.sh [--provider claude|codex|custom] [--one-go]
# Tunables (env): AGENT_PROVIDER AGENT_BIN AGENT_FLAGS RALPH_MAX_ITERATIONS RALPH_MAX_BUDGET_USD
#                 RALPH_MAX_TOKENS RALPH_NO_PROGRESS RALPH_API_MAX RALPH_API_BACKOFF
#                 RALPH_PROMPT RALPH_ONE_GO_PROMPT
#
# UNATTENDED PERMISSIONS: a Ralph loop cannot answer permission prompts. Before an
# unattended run, opt in ONLY inside a sandbox/VM + dedicated repo:
#   export AGENT_UNATTENDED=1

set -uo pipefail

ONE_GO="${RALPH_ONE_GO:-0}"
PROVIDER_OVERRIDE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --one-go) ONE_GO=1; shift ;;
    --provider)
      [ "$#" -ge 2 ] || { echo "usage: scripts/ralph.sh [--provider NAME] [--one-go]" >&2; exit 2; }
      PROVIDER_OVERRIDE="$2"; shift 2
      ;;
    -h|--help) echo "usage: scripts/ralph.sh [--provider NAME] [--one-go]"; exit 0 ;;
    *) echo "usage: scripts/ralph.sh [--provider NAME] [--one-go]" >&2; exit 2 ;;
  esac
done
[ -z "$PROVIDER_OVERRIDE" ] || export AGENT_PROVIDER="$PROVIDER_OVERRIDE"

# --- config ---------------------------------------------------------------
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-200}"
MAX_BUDGET_USD="${RALPH_MAX_BUDGET_USD:-500}"
MAX_TOKENS="${RALPH_MAX_TOKENS:-0}"
NO_PROGRESS_MAX="${RALPH_NO_PROGRESS:-200}"
API_MAX="${RALPH_API_MAX:-5}"                       # consecutive transient API/5xx errors before stopping (exit 8)
API_BACKOFF="${RALPH_API_BACKOFF:-30}"              # seconds to back off after a transient API error before retrying
PROMPT_FILE="${RALPH_PROMPT:-prompts/PROMPT.md}"
ONE_GO_PROMPT_FILE="${RALPH_ONE_GO_PROMPT:-prompts/IMPLEMENT_ALL.md}"
MODEL="${RALPH_MODEL:-${AGENT_MODEL:-}}"
EFFORT="${RALPH_EFFORT:-${AGENT_EFFORT:-high}}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AGENT_RUNNER="$ROOT/scripts/agent-runner.sh"
mkdir -p .ralph
RUN_ID="$(date +%Y%m%d-%H%M%S)"; RUN_DIR=".ralph/runs/$RUN_ID"; mkdir -p "$RUN_DIR"   # keep every run's logs for retro
trap 'echo "[ralph] logs kept in $RUN_DIR — analyze + auto-improve with: scripts/ralph-retro.sh $RUN_DIR"' EXIT

# Run-scoped tag stamped onto every Chromium our visual-diff harness launches (scripts/visual-diff/
# launch.mjs reads it). It's inherited all the way down to the agent's `node …/capture.mjs` calls,
# so reap_chromium below can kill THIS run's orphaned browsers (left by a crashed/killed iteration)
# WITHOUT ever touching the chrome-devtools MCP's Chrome, the user's browser, or another loop's run.
export RALPH_CHROMIUM_TAG="ralph-managed-chromium-$RUN_ID"

ESC=$'\033'; C_INFO="${ESC}[36m"; C_OK="${ESC}[32m"; C_WARN="${ESC}[33m"; C_OFF="${ESC}[0m"
log() { printf '%s[ralph %s]%s %s\n' "$C_INFO" "$(date +%H:%M:%S)" "$C_OFF" "$*"; }

run_agent() {
  local out="$1" prompt="${2:-$PROMPT_FILE}"
  "$AGENT_RUNNER" --output "$out" --error "$RUN_DIR/ralph.err" --model "$MODEL" --effort "$EFFORT" --root "$ROOT" < "$prompt" \
    || log "${C_WARN}agent exited non-zero${C_OFF} (see $RUN_DIR/ralph.err)"
}

compose_one_go_prompt() {
  local target="$1"
  {
    cat "$PROMPT_FILE"
    printf '\n\n---\n\n'
    cat "$ONE_GO_PROMPT_FILE"
  } > "$target"
}

load_agent_summary() {
  local out="$1" summary
  summary="$(node scripts/agent-log.mjs "$out" 2>/dev/null || printf '{}')"
  cost="$(node -e 'const s=JSON.parse(process.argv[1]);if(s.costUsd!=null)process.stdout.write(String(s.costUsd))' "$summary" 2>/dev/null || true)"
  tokens="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(String(s.tokens||0))' "$summary" 2>/dev/null || printf 0)"
  compacted="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.compacted?"1":"0")' "$summary" 2>/dev/null || printf 0)"
  retryable="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.retryableApiError?"1":"0")' "$summary" 2>/dev/null || printf 0)"
  provider_failed="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.failed?"1":"0")' "$summary" 2>/dev/null || printf 0)"
}

# Work is queue-authoritative. Missing/unvalidated packs are rejected by preflight; remaining work is open
# delta/interaction boxes plus queued pages without a fresh machine gate and both final reports. This prevents
# an incomplete Plan (for example only home/ exists) from becoming a false successful migration.
open_tasks() {
  node scripts/migration-state.mjs remaining migrations
}

file_signature() {
  if [ -f "$1" ]; then
    node -e 'const fs=require("fs"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
  else
    printf 'missing'
  fi
}

QUEUE_FILE="migrations/_queue.tsv"
SCOPE_FILE="migrations/_scope.json"
inventory_unchanged() {
  [ "$(file_signature "$QUEUE_FILE")" = "$QUEUE_SIGNATURE" ] \
    && [ "$(file_signature "$SCOPE_FILE")" = "$SCOPE_SIGNATURE" ]
}

# Reap any visual-diff Chromium THIS run left orphaned (an iteration that crashed/was killed
# before its `finally { browser.close() }` could run). Scoped to our run tag, so it can only
# ever match browsers this loop spawned — never the chrome-devtools MCP, the user's browser, or
# another run. Safe at the iteration boundary: the loop is serial, so nothing of ours is
# legitimately running between tasks. `pkill` returns non-zero when there's nothing to kill (fine).
reap_chromium() {
  if pkill -f "$RALPH_CHROMIUM_TAG" 2>/dev/null; then
    log "${C_WARN}reaped orphaned harness Chromium from a previous iteration (tag $RALPH_CHROMIUM_TAG)${C_OFF}"
  fi
}

# --- preflight ------------------------------------------------------------
[ -x "$AGENT_RUNNER" ] || { log "ERROR: provider runner missing or not executable: $AGENT_RUNNER"; exit 2; }
agent_info="$($AGENT_RUNNER --check 2>&1)" || { log "ERROR: $agent_info"; exit 2; }
[ -f "$PROMPT_FILE" ] || { log "ERROR: prompt file '$PROMPT_FILE' missing"; exit 2; }
if [ "$ONE_GO" = "1" ] && [ ! -f "$ONE_GO_PROMPT_FILE" ]; then
  log "ERROR: one-go prompt overlay '$ONE_GO_PROMPT_FILE' missing"; exit 2
fi
if ! plan_check="$(node scripts/migration-state.mjs planned migrations 2>&1)"; then
  log "ERROR: Execute requires a complete, validated migrations/_queue.tsv — Plan every route first."
  printf '%s\n' "$plan_check" >&2
  exit 2
fi
log "$plan_check"
QUEUE_SIGNATURE="$(file_signature "$QUEUE_FILE")"
SCOPE_SIGNATURE="$(file_signature "$SCOPE_FILE")"

log "start | mode=$([ "$ONE_GO" = 1 ] && printf one-go || printf loop) provider=${AGENT_PROVIDER:-claude} budget=\$$MAX_BUDGET_USD token_cap=$MAX_TOKENS"
if [ "$ONE_GO" = "1" ]; then
  log "prompt=$PROMPT_FILE + $ONE_GO_PROMPT_FILE queue=migrations/_queue.tsv model=${MODEL:-default} effort=$EFFORT agent=$agent_info"
else
  log "prompt=$PROMPT_FILE queue=migrations/_queue.tsv model=${MODEL:-default} effort=$EFFORT agent=$agent_info"
fi

spent=0
spent_tokens=0
no_progress=0
api_errors=0
iter=0

if [ "$ONE_GO" = "1" ]; then
  if [ -f .ralph/BLOCKED ]; then
    log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3
  fi
  remaining="$(open_tasks 2>>"$RUN_DIR/ralph.err")" || { log "ERROR: invalid migration state"; exit 2; }
  if [ "$remaining" -eq 0 ]; then
    rm -f .ralph/ACTIVE_PAGE
    log "DONE — every queued page is already gate-verified. Full migration complete."; exit 0
  fi
  active_page="$(node scripts/active-migration-page.mjs 2>>"$RUN_DIR/ralph.err" || true)"
  [ -z "$active_page" ] || printf '%s\n' "$active_page" > .ralph/ACTIVE_PAGE
  head_before="$(git rev-parse HEAD 2>/dev/null || echo none)"
  out="$RUN_DIR/one-go.jsonl"
  effective_prompt="$RUN_DIR/one-go.prompt.md"
  compose_one_go_prompt "$effective_prompt"
  log "running ONE implementation agent for the complete queue — live output below:"
  run_agent "$out" "$effective_prompt"
  load_agent_summary "$out"
  reap_chromium
  inventory_unchanged || { log "ERROR: the sealed route inventory changed during one-go Execute. Restore $QUEUE_FILE and $SCOPE_FILE before resuming."; exit 2; }

  if [ "$compacted" = "1" ]; then
    log "${C_WARN}STOP — the one-go implementation exceeded its context window; work is preserved but not accepted.${C_OFF}"; exit 7
  fi
  remaining="$(open_tasks 2>>"$RUN_DIR/ralph.err")" || { log "ERROR: migration state became invalid"; exit 2; }
  if [ "$remaining" -eq 0 ]; then
    head_after="$(git rev-parse HEAD 2>/dev/null || echo none)"
    if [ "$head_after" != "$head_before" ] && [ "${RALPH_SYNC_LIVE:-0}" = "1" ] && [ -x scripts/sync-theme-branch.sh ]; then
      if scripts/sync-theme-branch.sh >>"$RUN_DIR/ralph.err" 2>&1; then log "mirrored completed theme -> shopify-theme (LIVE)"; else log "WARN: shopify-theme sync failed (see $RUN_DIR/ralph.err)"; fi
    fi
    rm -f .ralph/ACTIVE_PAGE
    log "${C_OK}DONE — every queued page was gate-verified in one implementation invocation.${C_OFF}"; exit 0
  fi
  if [ -f .ralph/BLOCKED ]; then
    log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3
  fi
  if [ "$retryable" = "1" ] || [ "$provider_failed" = "1" ]; then
    log "STOP — provider/API failure interrupted one-go implementation. Re-run with --one-go to resume."; exit 8
  fi
  if [ -n "$cost" ] && awk "BEGIN{exit !($cost >= $MAX_BUDGET_USD)}"; then
    log "STOP — one-go invocation used \$$cost, reaching the \$$MAX_BUDGET_USD budget."; exit 5
  fi
  if [ "$MAX_TOKENS" -gt 0 ] 2>/dev/null && [ "$tokens" -ge "$MAX_TOKENS" ]; then
    log "STOP — one-go invocation used $tokens tokens, reaching the $MAX_TOKENS token cap."; exit 5
  fi
  head_after="$(git rev-parse HEAD 2>/dev/null || echo none)"
  [ "$head_after" != "$head_before" ] && log "progress was committed through ${head_after:0:9}, but $remaining work signal(s) remain"
  log "${C_WARN}STOP — the single implementation invocation ended before the full queue passed. State is preserved; inspect $out.${C_OFF}"
  exit 6
fi

while :; do
  iter=$((iter + 1))
  reap_chromium          # clean up any browser the PREVIOUS iteration leaked before starting this one
  if ! remaining="$(open_tasks 2>>"$RUN_DIR/ralph.err")"; then
    log "ERROR: migration queue/state became invalid during the run (see $RUN_DIR/ralph.err)"; exit 2
  fi
  active_page="$(node scripts/active-migration-page.mjs 2>>"$RUN_DIR/ralph.err" || true)"
  if [ -n "$active_page" ]; then
    printf '%s\n' "$active_page" > .ralph/ACTIVE_PAGE
    log "active_page=$active_page"
  else
    rm -f .ralph/ACTIVE_PAGE
  fi
  log "iteration $iter — ${remaining} open task(s); spent \$$spent / ${spent_tokens} tokens"

  # --- exit checks (BEFORE doing work) ---
  if [ -f .ralph/BLOCKED ]; then
    log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; log "stopping — needs a human. Resolve it, then 'rm .ralph/BLOCKED' to resume."; exit 3
  fi
  if [ "$remaining" -eq 0 ]; then
    log "DONE — every queued page is gate-verified. Full migration complete."; exit 0
  fi
  if [ "$iter" -gt "$MAX_ITERATIONS" ]; then
    log "STOP — max iterations ($MAX_ITERATIONS) reached."; exit 4
  fi
  if awk "BEGIN{exit !($spent >= $MAX_BUDGET_USD)}"; then
    log "STOP — budget \$$MAX_BUDGET_USD reached (spent \$$spent)."; exit 5
  fi
  if [ "$MAX_TOKENS" -gt 0 ] 2>/dev/null && [ "$spent_tokens" -ge "$MAX_TOKENS" ]; then
    log "STOP — token cap $MAX_TOKENS reached (used $spent_tokens)."; exit 5
  fi
  if [ "$no_progress" -ge "$NO_PROGRESS_MAX" ]; then
    log "STOP — circuit-breaker: $no_progress loops with no new commit. Re-narrow the task or tune the prompt (docs/principles/loop-and-exit.md)."; exit 6
  fi

  # --- run ONE fresh-context iteration ---
  head_before="$(git rev-parse HEAD 2>/dev/null || echo none)"
  out="$RUN_DIR/iter-${iter}.jsonl"
  log "running agent (fresh context) — live output below:"
  run_agent "$out"
  load_agent_summary "$out"
  inventory_unchanged || { log "ERROR: the sealed route inventory changed during Execute. Restore $QUEUE_FILE and $SCOPE_FILE before resuming."; exit 2; }

  if [ -z "$cost" ]; then
    [ "$tokens" -gt 0 ] || log "${C_WARN}WARN: provider stream contained no usage event; budget accounting may under-count.${C_OFF}"
    cost=0
  fi
  spent="$(awk "BEGIN{printf \"%.4f\", $spent + $cost}")"
  spent_tokens=$((spent_tokens + tokens))

  # --- HARD FAIL: did this task exhaust the selected provider's context and auto-compact mid-run? ---
  # One task must sit well under the window (docs/principles/loop-and-exit.md). If the session
  # auto-compacted ("ran out of context" / a compact_boundary event), quality has already
  # degraded — stop hard so the task gets RE-NARROWED instead of shipping degraded work.
  if [ "$compacted" = "1" ]; then
    log "${C_WARN}STOP — task auto-compacted after exhausting the provider context. This loop's work is degraded and NOT trusted. Re-narrow the task into smaller pieces (docs/principles/loop-and-exit.md).${C_OFF}"
    exit 7
  fi

  # --- outcome: a commit? a transient API error? or genuinely stuck? ---
  head_after="$(git rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$head_after" != "$head_before" ]; then
    no_progress=0; api_errors=0
    log "${C_OK}progress: new commit ${head_after:0:9}${C_OFF} (+\$$cost, total \$$spent) — diff:"
    git -c color.ui=always show "$head_after" 2>/dev/null | sed 's/^/    /' | head -200
    # mirror to the GitHub-connect branch = the LIVE theme. OFF by default so dev builds
    # stay on the unpublished preview target; set RALPH_SYNC_LIVE=1 for a go-live run.
    if [ "${RALPH_SYNC_LIVE:-0}" = "1" ] && [ -x scripts/sync-theme-branch.sh ]; then
      if scripts/sync-theme-branch.sh >>$RUN_DIR/ralph.err 2>&1; then log "mirrored theme -> shopify-theme (LIVE)"; else log "WARN: shopify-theme sync failed (see $RUN_DIR/ralph.err)"; fi
    else
      log "live-sync skipped (RALPH_SYNC_LIVE!=1) — building on the preview target only"
    fi
  elif [ "$retryable" = "1" ]; then
    # A transient server-side API/5xx error killed the iteration with no commit. Do NOT count it toward
    # the stuck breaker (that's for a genuinely unproductive agent) — back off and retry. A real outage
    # trips its own cap (exit 8); a brief blip just recovers. See docs/principles/loop-and-exit.md.
    api_errors=$((api_errors + 1))
    log "${C_WARN}transient API/5xx error, no commit (api-error ${api_errors}/${API_MAX}) — NOT counted as no-progress${C_OFF}"
    if [ "$api_errors" -ge "$API_MAX" ]; then
      log "STOP — ${api_errors} consecutive API errors (likely a server-side outage). State is on disk; re-run later: scripts/ralph.sh"; exit 8
    fi
    [ "${API_BACKOFF:-0}" -gt 0 ] 2>/dev/null && { log "backing off ${API_BACKOFF}s before retrying…"; sleep "$API_BACKOFF"; }
  elif [ "$provider_failed" = "1" ]; then
    log "STOP — provider process/turn failed without a commit. State is on disk; inspect $out and $RUN_DIR/ralph.err."
    exit 8
  else
    no_progress=$((no_progress + 1))
    log "no new commit this loop (no-progress ${no_progress}/${NO_PROGRESS_MAX})"
  fi
done
