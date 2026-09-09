#!/usr/bin/env bash
# Queue-authoritative CAPTURE runner. It creates one route inventory, then invokes a
# fresh agent for each unvalidated page until every queued evidence pack passes.
#
# Usage:
#   scripts/plan.sh [--provider NAME] <source-url>
#   scripts/plan.sh --from-reference [dir] [--url backup] # enumerate a reference build, then plan every page
#   scripts/plan.sh --page <url> [page-key] # explicit single-page queue + evidence pack
#   scripts/plan.sh                         # resume the existing queue
#
# Tunables: AGENT_PROVIDER AGENT_BIN AGENT_FLAGS PLAN_MAX_ITERATIONS PLAN_NO_PROGRESS
#           PLAN_MAX_BUDGET_USD PLAN_MAX_TOKENS PLAN_API_MAX PLAN_API_BACKOFF
#           PLAN_PROMPT PLAN_MODEL PLAN_EFFORT REF_ROOT

set -uo pipefail

PROVIDER_OVERRIDE=""
POSITIONAL=()
usage() {
  echo "usage: scripts/plan.sh [--provider NAME] <source-url>" >&2
  echo "       scripts/plan.sh [--provider NAME] --from-reference [dir] [--url backup]" >&2
  echo "       scripts/plan.sh [--provider NAME] --page <url> [page-key]" >&2
  echo "       scripts/plan.sh [--provider NAME]" >&2
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --one-go) usage; exit 2 ;;
    --provider)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      PROVIDER_OVERRIDE="$2"; shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
# Bash 3.2 (the macOS system Bash) treats an empty-array expansion as unbound
# under `set -u`, even when the array was initialized. Resume has no positionals.
set +u
set -- "${POSITIONAL[@]}"
set -u
[ -z "$PROVIDER_OVERRIDE" ] || export AGENT_PROVIDER="$PROVIDER_OVERRIDE"

MODE="resume"; SOURCE_URL=""; BUILD_ARG=""; PAGE_KEY=""; BACKUP_URL=""
case "${1:-}" in
  --from-reference)
    MODE="reference"; shift
    if [ "$#" -gt 0 ] && [ "${1:-}" != "--url" ]; then BUILD_ARG="$1"; shift; fi
    if [ "${1:-}" = "--url" ]; then
      [ "$#" -ge 2 ] || { echo "usage: scripts/plan.sh --from-reference [dir] [--url <backup-url>]" >&2; exit 2; }
      BACKUP_URL="$2"; shift 2
    fi
    [ "$#" -eq 0 ] || { echo "usage: scripts/plan.sh --from-reference [dir] [--url <backup-url>]" >&2; exit 2; }
    ;;
  --page)
    MODE="page"; shift
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "usage: scripts/plan.sh --page <url> [page-key]" >&2; exit 2; }
    SOURCE_URL="$1"; PAGE_KEY="${2:-}"
    ;;
  '') [ "$#" -eq 0 ] || exit 2 ;;
  *)
    [ "$#" -eq 1 ] || { echo "usage: scripts/plan.sh <source-url>" >&2; exit 2; }
    MODE="site"; SOURCE_URL="$1"
    ;;
esac

REF_ROOT="${REF_ROOT:-reference}"
MAX_ITERATIONS="${PLAN_MAX_ITERATIONS:-100}"
NO_PROGRESS_MAX="${PLAN_NO_PROGRESS:-3}"
MAX_BUDGET_USD="${PLAN_MAX_BUDGET_USD:-500}"
MAX_TOKENS="${PLAN_MAX_TOKENS:-0}"
API_MAX="${PLAN_API_MAX:-5}"
API_BACKOFF="${PLAN_API_BACKOFF:-30}"
PROMPT_FILE="${PLAN_PROMPT:-prompts/PLAN.md}"
MODEL="${PLAN_MODEL:-${AGENT_MODEL:-}}"
EFFORT="${PLAN_EFFORT:-${AGENT_EFFORT:-high}}"
QUEUE="migrations/_queue.tsv"
SCOPE_FILE="migrations/_scope.json"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 2
AGENT_RUNNER="$ROOT/scripts/agent-runner.sh"
ESC=$'\033'; C_INFO="${ESC}[36m"; C_OK="${ESC}[32m"; C_WARN="${ESC}[33m"; C_OFF="${ESC}[0m"
log() { printf '%s[plan %s]%s %s\n' "$C_INFO" "$(date +%H:%M:%S)" "$C_OFF" "$*"; }

run_agent() {
  local out="$1"
  "$AGENT_RUNNER" --output "$out" --error "$RUN_DIR/plan.err" --model "$MODEL" --effort "$EFFORT" --root "$ROOT" \
    || log "${C_WARN}agent exited non-zero (see $RUN_DIR/plan.err)${C_OFF}"
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

record_usage() {
  local used_cost="${cost:-0}"
  [ -n "$used_cost" ] || used_cost=0
  spent="$(awk "BEGIN{printf \"%.4f\", $spent + $used_cost}")"
  spent_tokens=$((spent_tokens + ${tokens:-0}))
}

[ -x "$AGENT_RUNNER" ] || { log "ERROR: provider runner missing or not executable: $AGENT_RUNNER"; exit 2; }
agent_info="$($AGENT_RUNNER --check 2>&1)" || { log "ERROR: $agent_info"; exit 2; }
[ -f "$PROMPT_FILE" ] || { log "ERROR: prompt file '$PROMPT_FILE' missing"; exit 2; }
[ "$MODE" != "page" ] || [ -n "$SOURCE_URL" ] || { log "ERROR: --page requires a source URL"; exit 2; }

spent=0
spent_tokens=0
api_errors=0

mkdir -p .ralph
RUN_ID="$(date +%Y%m%d-%H%M%S)"; RUN_DIR=".ralph/plan-runs/$RUN_ID"; mkdir -p "$RUN_DIR"
trap 'log "logs kept in $RUN_DIR"' EXIT

# Resolve reference scope before checking an existing queue. Multiple builds require an explicit name;
# silently picking the first directory makes a rerun non-deterministic.
BUILD_REL=""
if [ "$MODE" = "reference" ]; then
  BUILD_REL="$BUILD_ARG"
  if [ -z "$BUILD_REL" ]; then
    found=0
    for d in "$REF_ROOT"/*/; do
      [ -f "${d}index.html" ] || continue
      BUILD_REL="$(basename "$d")"; found=$((found + 1))
    done
    [ "$found" -le 1 ] || { log "ERROR: multiple reference builds contain index.html; pass one explicitly: scripts/plan.sh --from-reference <dir>"; exit 2; }
  fi
  BUILD_DIR="$REF_ROOT/$BUILD_REL"
  [ -n "$BUILD_REL" ] && [ -d "$BUILD_DIR" ] || { log "ERROR: no reference build under $REF_ROOT/ (need REF_ROOT/<dir>/*.html)"; exit 2; }
fi

SCOPE_VALUE="$SOURCE_URL"
[ "$MODE" != "reference" ] || SCOPE_VALUE="$BUILD_REL|backup=$BACKUP_URL"
SCOPE_VALUE="${SCOPE_VALUE%/}"

hash_file() {
  node -e 'const fs=require("fs"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

hash_queue() {
  hash_file "$QUEUE"
}

write_scope() {
  local queue_hash="$1"
  node -e 'const fs=require("fs"),path=require("path");const [file,mode,source,queueHash]=process.argv.slice(1);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify({version:1,mode,source,queueHash,createdAt:new Date().toISOString()},null,2)+"\n")' "$SCOPE_FILE" "$MODE" "$SCOPE_VALUE" "$queue_hash"
}

scope_matches() {
  [ -f "$SCOPE_FILE" ] || return 1
  node -e 'const fs=require("fs");const [file,mode,source]=process.argv.slice(1);try{const s=JSON.parse(fs.readFileSync(file,"utf8"));process.exit(s.mode===mode&&s.source===source?0:1)}catch{process.exit(1)}' "$SCOPE_FILE" "$MODE" "$SCOPE_VALUE"
}

# Explicit invocations may only resume the same source. An argument-less invocation deliberately resumes
# legacy queues too. Starting a different migration requires archiving the old queue/scope first.
if [ -f "$QUEUE" ] && [ "$MODE" != "resume" ] && ! scope_matches; then
  log "ERROR: $QUEUE belongs to a different or legacy scope. Run 'scripts/plan.sh' to resume it, or archive migrations/_queue.tsv + migrations/_scope.json before starting a new source."
  exit 2
fi

if [ ! -f "$QUEUE" ]; then
  [ "$MODE" != "resume" ] || { log "ERROR: no queue — start with a URL, --from-reference, or --page"; exit 2; }
  mkdir -p migrations

  if [ "$MODE" = "reference" ]; then
    log "no queue yet — enumerating reference build $BUILD_DIR (home first)"
    {
      printf '# <page-key>\t<source> — reference build: %s/%s\n' "$REF_ROOT" "$BUILD_REL"
      [ -f "$BUILD_DIR/index.html" ] && printf 'home\t__REF__/%s/index.html\n' "$BUILD_REL"
      find "$BUILD_DIR" -type f \( -iname '*.html' -o -iname '*.htm' \) -print | LC_ALL=C sort | while IFS= read -r f; do
        rel="${f#"$BUILD_DIR"/}"
        [ "$rel" != index.html ] || continue
        base="$(basename "$rel")"; name="${rel%.*}"
        case "$base" in *[Ss]tandalone*) continue ;; esac
        case "$name" in */index) name="${name%/index}" ;; esac
        key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
        [ -n "$key" ] || continue
        printf '%s\t__REF__/%s/%s\n' "$key" "$BUILD_REL" "$rel"
      done
    } > "$QUEUE"
  elif [ "$MODE" = "page" ]; then
    if [ -z "$PAGE_KEY" ]; then
      PAGE_KEY="$(node -e 'try{const u=new URL(process.argv[1]);const bits=u.pathname.split("/").filter(Boolean);const raw=bits.at(-1)||"home";const key=raw.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"");if(!key)throw Error("empty page key");process.stdout.write(key)}catch(e){console.error(`invalid --page URL: ${e.message}`);process.exit(1)}' "$SOURCE_URL")" || exit 2
    fi
    [[ "$PAGE_KEY" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { log "ERROR: invalid page key '$PAGE_KEY' (use lowercase kebab-case)"; exit 2; }
    printf '# <page-key>\t<source> — explicit single-page scope\n%s\t%s\n' "$PAGE_KEY" "$SOURCE_URL" > "$QUEUE"
  else
    log "no queue yet — discovering routes from $SOURCE_URL (crawl + write $QUEUE)"
    printf 'Read prompts/PLAN.md for context. TASK = full-site route DISCOVERY ONLY for %s: crawl the source (fetch <origin>/sitemap.xml and read the rendered nav + footer links via the chrome-devtools MCP), dedupe to DISTINCT page-types (one representative product, one collection, each standalone page; skip duplicate instances), and WRITE the route list to %s as tab-separated "<page-key>\t<url>" lines with home FIRST. Do NOT plan/capture any page and write NO theme code — only create the queue file. NON-INTERACTIVE: do not interview; read migrations/_brief.md if present.\n' "$SOURCE_URL" "$QUEUE" \
      | run_agent "$RUN_DIR/bootstrap.jsonl"
    load_agent_summary "$RUN_DIR/bootstrap.jsonl"
    record_usage
    if [ -f .ralph/BLOCKED ]; then log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; fi
    [ "$compacted" != "1" ] || { log "${C_WARN}STOP — route discovery exhausted its context.${C_OFF}"; exit 7; }
    [ "$retryable" != "1" ] && [ "$provider_failed" != "1" ] \
      || { log "STOP — provider/API failure interrupted route discovery."; exit 8; }
  fi

  if [ ! -s "$QUEUE" ]; then
    if [ -f .ralph/BLOCKED ]; then log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; fi
    log "${C_WARN}STOP — discovery produced no $QUEUE. See $RUN_DIR/plan.err.${C_OFF}"; exit 2
  fi
  write_scope "$(hash_queue)"
  log "${C_OK}discovered $(grep -cvE '^[[:space:]]*(#|$)' "$QUEUE") route(s) → $QUEUE${C_OFF}"
fi

if ! queue_check="$(node scripts/migration-state.mjs queue migrations 2>&1)"; then
  log "ERROR: invalid route queue"
  printf '%s\n' "$queue_check" >&2
  exit 2
fi

# Discovery owns the inventory; per-page agents do not. Keep the exact queue immutable for this run so
# an iteration cannot accidentally drop later routes and turn a partial Plan into a false success.
QUEUE_HASH="$(hash_queue)"
if ! scope_check="$(node -e '
  const fs=require("fs"),path=require("path");const [file,hash]=process.argv.slice(1);let scope;
  try{scope=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,"utf8")):{version:1,mode:"legacy",source:"",createdAt:new Date().toISOString()}}
  catch(e){console.error(`invalid scope file: ${e.message}`);process.exit(1)}
  if(scope.queueHash&&scope.queueHash!==hash){console.error("queue bytes no longer match the sealed route inventory");process.exit(1)}
  if(!scope.queueHash){scope.queueHash=hash;scope.sealedAt=new Date().toISOString();fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(scope,null,2)+"\n")}
' "$SCOPE_FILE" "$QUEUE_HASH" 2>&1)"; then
  log "ERROR: $scope_check. Restore $QUEUE or archive both $QUEUE and $SCOPE_FILE before starting a new migration."
  exit 2
fi
if [ "$MODE" = "resume" ]; then
  BACKUP_URL="$(node -e 'const fs=require("fs");const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(s.mode==="reference"){const marker="|backup=";const i=String(s.source||"").indexOf(marker);if(i>=0)process.stdout.write(String(s.source).slice(i+marker.length))}' "$SCOPE_FILE")"
fi
SCOPE_HASH="$(hash_file "$SCOPE_FILE")"
inventory_unchanged() {
  [ -f "$QUEUE" ] && [ -f "$SCOPE_FILE" ] || return 1
  [ "$(hash_queue)" = "$QUEUE_HASH" ] && [ "$(hash_file "$SCOPE_FILE")" = "$SCOPE_HASH" ]
}

pack_done() {
  node scripts/migration-state.mjs pack "migrations/$1" "$2" >/dev/null 2>&1
}

next_route() {
  while IFS=$'\t' read -r page url _rest; do
    page="${page%%[[:space:]]}"; [ -z "${page:-}" ] && continue
    case "$page" in \#*) continue ;; esac
    pack_done "$page" "$url" || { printf '%s\t%s' "$page" "$url"; return 0; }
  done < "$QUEUE"
  return 1
}

count_done() {
  local n=0 page url rest
  while IFS=$'\t' read -r page url rest; do
    case "${page:-}" in ''|\#*) continue ;; esac
    pack_done "$page" "$url" && n=$((n + 1))
  done < "$QUEUE"
  printf '%s' "$n"
}

total="$(grep -cvE '^[[:space:]]*(#|$)' "$QUEUE" 2>/dev/null || echo 0)"
log "start | provider=${AGENT_PROVIDER:-claude} queue=$QUEUE routes=$total model=${MODEL:-default} effort=$EFFORT"

iter=0; no_progress=0; no_progress_page=""
while :; do
  iter=$((iter + 1))
  inventory_unchanged || { log "ERROR: $QUEUE or $SCOPE_FILE changed after discovery. The route inventory is immutable during per-page planning; restore it before resuming."; exit 2; }
  if [ -f .ralph/BLOCKED ]; then log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; fi
  entry="$(next_route || true)"
  if [ -z "$entry" ]; then
    if final_check="$(node scripts/migration-state.mjs planned migrations 2>&1)"; then
      log "${C_OK}DONE — $final_check.${C_OFF}"; exit 0
    fi
    log "ERROR: queue has no selectable route but final planning validation failed"
    printf '%s\n' "$final_check" >&2
    exit 2
  fi
  if [ "$iter" -gt "$MAX_ITERATIONS" ]; then log "STOP — max iterations ($MAX_ITERATIONS) reached."; exit 4; fi
  if awk "BEGIN{exit !($spent >= $MAX_BUDGET_USD)}"; then log "STOP — budget \$$MAX_BUDGET_USD reached (spent \$$spent)."; exit 5; fi
  if [ "$MAX_TOKENS" -gt 0 ] 2>/dev/null && [ "$spent_tokens" -ge "$MAX_TOKENS" ]; then log "STOP — token cap $MAX_TOKENS reached (used $spent_tokens)."; exit 5; fi

  page="${entry%%$'\t'*}"; url="${entry#*$'\t'}"
  if [ "$page" != "$no_progress_page" ]; then no_progress=0; no_progress_page="$page"; fi
  log "iteration $iter — planning ${C_INFO}$page${C_OFF} ($url) [$(count_done)/$total validated]"

  before="$(node scripts/migration-state.mjs fingerprint "migrations/$page")"
  case "$url" in
    __REF__*)
      SCOPE="--from-reference for the local reference entry $url — set this page's contract.source to exactly that __REF__ path (it is auto-served)"
      [ -z "$BACKUP_URL" ] || SCOPE="$SCOPE; use --url $BACKUP_URL only to fill gaps, never to override the local reference"
      ;;
    *) SCOPE="--page $url" ;;
  esac
  printf 'Read and follow prompts/PLAN.md exactly. Plan %s (page key: %s). Reuse shared globals + the migrations/_sections.md catalog; plan only, write no theme code. migrations/_queue.tsv and migrations/_scope.json are immutable: never edit them. NON-INTERACTIVE loop run: do NOT interview the user — read migrations/_brief.md if present (authoritative), default sensibly for anything it omits, and record the assumption in the page contract _notes + summary. Never block on a question.\n' "$SCOPE" "$page" \
    | run_agent "$RUN_DIR/iter-${iter}.jsonl"

  inventory_unchanged || { log "ERROR: the sealed route inventory was modified while planning $page. Refusing to continue."; exit 2; }
  if [ -f .ralph/BLOCKED ]; then log "BLOCKED: $(head -n1 .ralph/BLOCKED 2>/dev/null)"; exit 3; fi
  load_agent_summary "$RUN_DIR/iter-${iter}.jsonl"
  record_usage
  if [ "$compacted" = "1" ]; then log "${C_WARN}STOP — session auto-compacted planning $page. Narrow the page or split it.${C_OFF}"; exit 7; fi

  if pack_done "$page" "$url"; then
    no_progress=0; api_errors=0
    log "${C_OK}✓ $page planned + validated${C_OFF}"
    continue
  fi

  if [ "$retryable" = "1" ]; then
    api_errors=$((api_errors + 1))
    log "${C_WARN}transient provider/API failure while planning $page ($api_errors/$API_MAX)${C_OFF}"
    if [ "$api_errors" -ge "$API_MAX" ]; then log "STOP — $api_errors consecutive provider/API failures."; exit 8; fi
    [ "$API_BACKOFF" -gt 0 ] 2>/dev/null && sleep "$API_BACKOFF"
    continue
  fi
  if [ "$provider_failed" = "1" ]; then log "STOP — provider failed while planning $page; inspect $RUN_DIR/plan.err."; exit 8; fi
  api_errors=0

  after="$(node scripts/migration-state.mjs fingerprint "migrations/$page")"
  if [ "$after" = "$before" ]; then
    no_progress=$((no_progress + 1))
    log "${C_WARN}$page still invalid and unchanged (no-progress $no_progress/$NO_PROGRESS_MAX)${C_OFF}"
    if [ "$no_progress" -ge "$NO_PROGRESS_MAX" ]; then
      log "${C_WARN}STOP — no durable progress on $page. Inspect $RUN_DIR/plan.err and its iteration logs.${C_OFF}"; exit 6
    fi
  else
    no_progress=0
    log "${C_WARN}$page advanced but is not valid yet — retrying with its updated evidence pack${C_OFF}"
  fi
done
