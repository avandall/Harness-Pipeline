#!/usr/bin/env bash
# Provider-neutral post-migration implementation runner.
#
# Reads one operator request from stdin, appends prompts/FOLLOW_UP.md and the
# request to the canonical prompts/PROMPT.md contract, and invokes exactly one
# selected agent. Follow-up is accepted only from a clean,
# fully gate-verified migration and succeeds only when the request lands as a
# pushed commit while the complete sealed queue remains gate-verified.
#
# Usage: printf '%s\n' 'Tweak request' | scripts/follow-up.sh [--provider NAME]
# Tunables: AGENT_PROVIDER AGENT_BIN AGENT_FLAGS FOLLOW_UP_MODEL FOLLOW_UP_EFFORT
#           FOLLOW_UP_BASE_PROMPT FOLLOW_UP_PROMPT FOLLOW_UP_MAX_BYTES

set -uo pipefail

PROVIDER_OVERRIDE=""
usage() { echo "usage: printf '%s\\n' 'request' | scripts/follow-up.sh [--provider claude|codex|custom]" >&2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      PROVIDER_OVERRIDE="$2"; shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[ -z "$PROVIDER_OVERRIDE" ] || export AGENT_PROVIDER="$PROVIDER_OVERRIDE"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AGENT_RUNNER="$ROOT/scripts/agent-runner.sh"
BASE_PROMPT_FILE="${FOLLOW_UP_BASE_PROMPT:-prompts/PROMPT.md}"
PROMPT_FILE="${FOLLOW_UP_PROMPT:-prompts/FOLLOW_UP.md}"
MODEL="${FOLLOW_UP_MODEL:-${AGENT_MODEL:-}}"
EFFORT="${FOLLOW_UP_EFFORT:-${AGENT_EFFORT:-high}}"
MAX_BYTES="${FOLLOW_UP_MAX_BYTES:-65536}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR=".ralph/follow-up-runs/$RUN_ID"
REQUEST_FILE="$RUN_DIR/request.md"
EFFECTIVE_PROMPT="$RUN_DIR/follow-up.prompt.md"
OUTPUT_FILE="$RUN_DIR/follow-up.jsonl"
ERROR_FILE="$RUN_DIR/follow-up.err"
QUEUE_FILE="migrations/_queue.tsv"
SCOPE_FILE="migrations/_scope.json"
mkdir -p "$RUN_DIR"

ESC=$'\033'; C_INFO="${ESC}[36m"; C_OK="${ESC}[32m"; C_WARN="${ESC}[33m"; C_OFF="${ESC}[0m"
log() { printf '%s[follow-up %s]%s %s\n' "$C_INFO" "$(date +%H:%M:%S)" "$C_OFF" "$*"; }
trap 'log "logs kept in $RUN_DIR"' EXIT

file_signature() {
  if [ -f "$1" ]; then
    node -e 'const fs=require("fs"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
  else
    printf 'missing'
  fi
}

worktree_dirty() {
  [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]
}

load_agent_summary() {
  local summary
  summary="$(node scripts/agent-log.mjs "$OUTPUT_FILE" 2>/dev/null || printf '{}')"
  compacted="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.compacted?"1":"0")' "$summary" 2>/dev/null || printf 0)"
  provider_failed="$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.failed?"1":"0")' "$summary" 2>/dev/null || printf 0)"
}

cat > "$REQUEST_FILE"
request_bytes="$(wc -c < "$REQUEST_FILE" | tr -d ' ')"
if [ "$request_bytes" -eq 0 ] 2>/dev/null || ! grep -q '[^[:space:]]' "$REQUEST_FILE"; then
  log "ERROR: follow-up request cannot be empty"; exit 2
fi
if ! [[ "$MAX_BYTES" =~ ^[1-9][0-9]*$ ]] || [ "$request_bytes" -gt "$MAX_BYTES" ]; then
  log "ERROR: follow-up request is $request_bytes bytes; limit is $MAX_BYTES"; exit 2
fi

[ -x "$AGENT_RUNNER" ] || { log "ERROR: provider runner missing or not executable: $AGENT_RUNNER"; exit 2; }
agent_info="$($AGENT_RUNNER --check 2>&1)" || { log "ERROR: $agent_info"; exit 2; }
[ -f "$BASE_PROMPT_FILE" ] || { log "ERROR: canonical implementation prompt '$BASE_PROMPT_FILE' missing"; exit 2; }
[ -f "$PROMPT_FILE" ] || { log "ERROR: prompt file '$PROMPT_FILE' missing"; exit 2; }
[ ! -f .ralph/BLOCKED ] || { log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; }
if worktree_dirty; then
  log "ERROR: worktree changes exist. Commit, stash, remove, or ignore them before starting a follow-up."; exit 2
fi
if ! plan_check="$(node scripts/migration-state.mjs planned migrations 2>&1)"; then
  log "ERROR: follow-up requires a complete validated Plan."; printf '%s\n' "$plan_check" >&2; exit 2
fi
remaining="$(node scripts/migration-state.mjs remaining migrations 2>>"$ERROR_FILE")" || { log "ERROR: invalid migration state"; exit 2; }
if [ "$remaining" -ne 0 ]; then
  log "ERROR: follow-up unlocks only after every queued page is DONE ($remaining work signal(s) remain)."; exit 2
fi

QUEUE_SIGNATURE="$(file_signature "$QUEUE_FILE")"
SCOPE_SIGNATURE="$(file_signature "$SCOPE_FILE")"
HEAD_BEFORE="$(git rev-parse HEAD 2>/dev/null || printf none)"
{
  cat "$BASE_PROMPT_FILE"
  printf '\n\n---\n\n'
  cat "$PROMPT_FILE"
  printf '\n\n---\n\n## Operator follow-up request (implement verbatim)\n\n'
  cat "$REQUEST_FILE"
  printf '\n'
} > "$EFFECTIVE_PROMPT"

log "$plan_check"
log "start | prompt=$BASE_PROMPT_FILE + $PROMPT_FILE provider=${AGENT_PROVIDER:-claude} model=${MODEL:-default} effort=$EFFORT agent=$agent_info"
log "running ONE follow-up implementation agent — live output below:"
"$AGENT_RUNNER" --output "$OUTPUT_FILE" --error "$ERROR_FILE" --model "$MODEL" --effort "$EFFORT" --root "$ROOT" < "$EFFECTIVE_PROMPT" \
  || log "${C_WARN}agent exited non-zero${C_OFF} (see $ERROR_FILE)"
load_agent_summary

[ "$(file_signature "$QUEUE_FILE")" = "$QUEUE_SIGNATURE" ] && [ "$(file_signature "$SCOPE_FILE")" = "$SCOPE_SIGNATURE" ] || {
  log "ERROR: the sealed route inventory changed during follow-up. Restore $QUEUE_FILE and $SCOPE_FILE."; exit 2
}
[ "$compacted" != 1 ] || { log "STOP — follow-up exceeded its context window; partial work is not accepted."; exit 7; }
[ ! -f .ralph/BLOCKED ] || { log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; }
[ "$provider_failed" != 1 ] || { log "STOP — provider/API failure interrupted follow-up."; exit 8; }

remaining="$(node scripts/migration-state.mjs remaining migrations 2>>"$ERROR_FILE")" || { log "ERROR: migration state became invalid"; exit 2; }
[ "$remaining" -eq 0 ] || { log "STOP — follow-up left $remaining migration work signal(s); state is preserved."; exit 6; }
HEAD_AFTER="$(git rev-parse HEAD 2>/dev/null || printf none)"
[ "$HEAD_AFTER" != "$HEAD_BEFORE" ] || { log "STOP — follow-up ended without a new commit."; exit 6; }
if worktree_dirty; then
  log "STOP — follow-up left worktree changes outside its commit."; exit 6
fi

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
[ -n "$UPSTREAM" ] || { log "STOP — the current branch has no configured upstream; push it with --set-upstream."; exit 6; }
if [ "$HEAD_AFTER" != "$(git rev-parse "$UPSTREAM" 2>/dev/null || printf missing)" ]; then
  log "STOP — commit $HEAD_AFTER was not pushed to $UPSTREAM."; exit 6
fi

log "${C_OK}DONE — follow-up implemented, queue re-verified, commit ${HEAD_AFTER:0:9} pushed.${C_OFF}"
