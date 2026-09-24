#!/usr/bin/env bash
# =============================================================================
# agent-runner.sh — Provider-Neutral Agent Runner Plug
# Features:
# - Stall & Idle Activity Watchdog (detects AI freeze and aborts early)
# - Dynamic Budgeting (auto-extends timeout budget if AI is actively progressing)
# Supports: agy (default), claude, codex, custom
# =============================================================================
set -euo pipefail

PROVIDER="${AGENT_PROVIDER:-agy}"
OUTPUT_FILE=""
ERROR_FILE=""
MODEL=""
EFFORT=""
ROOT_DIR="$(pwd)"
RAW_TIMEOUT="${PRINT_TIMEOUT:-15m0s}"
STALL_TIMEOUT="${RALPH_STALL_TIMEOUT:-300}"    # 5 minutes of zero output = stall (allows deep reading & thinking)
EXTENSION_STEP="${RALPH_EXTENSION:-300}"        # +5 minutes extension per dynamic budgeting step
MAX_TIMEOUT="${RALPH_MAX_TIMEOUT:-1800}"        # 30 minutes hard maximum ceiling

parse_seconds() {
  local str="$1"
  local total=0
  if [[ "$str" =~ ([0-9]+)h ]]; then total=$(( total + BASH_REMATCH[1] * 3600 )); fi
  if [[ "$str" =~ ([0-9]+)m ]]; then total=$(( total + BASH_REMATCH[1] * 60 )); fi
  if [[ "$str" =~ ([0-9]+)s ]]; then total=$(( total + BASH_REMATCH[1] )); fi
  if [[ $total -eq 0 && "$str" =~ ^[0-9]+$ ]]; then total="$str"; fi
  [[ $total -eq 0 ]] && total=900
  echo "$total"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      if [[ "$PROVIDER" == "agy" ]]; then
        if command -v agy >/dev/null 2>&1; then
          echo "agy ($(agy --version 2>/dev/null || echo 'installed'))"
          exit 0
        else
          echo "agy CLI not found in PATH" >&2
          exit 1
        fi
      elif [[ "$PROVIDER" == "claude" ]]; then
        if command -v claude >/dev/null 2>&1; then
          echo "claude ($(claude --version 2>/dev/null || echo 'installed'))"
          exit 0
        else
          echo "claude CLI not found in PATH" >&2
          exit 1
        fi
      elif [[ "$PROVIDER" == "codex" ]]; then
        echo "codex (configured)"
        exit 0
      else
        echo "custom provider: $PROVIDER"
        exit 0
      fi
      ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --error) ERROR_FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --root) ROOT_DIR="$2"; shift 2 ;;
    --timeout) RAW_TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

PROMPT_INPUT="$(cat)"
INITIAL_BUDGET=$(parse_seconds "$RAW_TIMEOUT")

# Ensure target directory exists for output
TEMP_OUTPUT=""
if [[ -n "$OUTPUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
else
  TEMP_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/ralph-agent-out-XXXXXX.log")"
  OUTPUT_FILE="$TEMP_OUTPUT"
fi
if [[ -n "$ERROR_FILE" ]]; then
  mkdir -p "$(dirname "$ERROR_FILE")"
fi

# Ensure .venv is activated and prepended to PATH if present
if [[ -d "${ROOT_DIR}/.venv/bin" ]]; then
  export VIRTUAL_ENV="${ROOT_DIR}/.venv"
  export PATH="${ROOT_DIR}/.venv/bin:${PATH}"
fi

# Ensure standard PYTHONPATH is dynamically propagated to agent sessions
_EXTRA_PY_PATHS=".:${ROOT_DIR}"
[[ -d "${ROOT_DIR}/src" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:./src:${ROOT_DIR}/src"
[[ -d "${ROOT_DIR}/app" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:./app:${ROOT_DIR}/app"
export PYTHONPATH="${_EXTRA_PY_PATHS}:${PYTHONPATH:-}"

# Prepare provider command
build_command() {
  case "$PROVIDER" in
    agy)
      local model_args=()
      if [[ -n "$MODEL" ]]; then
        model_args+=("--model" "$MODEL")
      fi
      if [[ -n "$EFFORT" && ! "$MODEL" =~ ^claude ]]; then
        model_args+=("--effort" "$EFFORT")
      fi
      model_args+=("--disable-slash-commands")
      # Let the runner supervisor manage timeouts up to MAX_TIMEOUT
      agy "${model_args[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions --print-timeout "${MAX_TIMEOUT}s"
      ;;
    claude)
      local model_args=()
      if [[ -n "$MODEL" ]]; then
        model_args+=("--model" "$MODEL")
      fi
      claude "${model_args[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions
      ;;
    codex)
      echo "$PROMPT_INPUT" | codex exec
      ;;
    custom)
      if [[ -n "${AGENT_BIN:-}" ]]; then
        eval "$AGENT_BIN"
      else
        echo "ERROR: AGENT_BIN not set for custom provider" >&2
        exit 2
      fi
      ;;
    *)
      echo "Unknown provider: $PROVIDER" >&2
      exit 2
      ;;
  esac
}

# Clean output file then launch agent in background subshell with append mode
> "$OUTPUT_FILE"
build_command >> "$OUTPUT_FILE" 2>&1 &
AGENT_PID=$!

cleanup_subprocesses() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    # Terminate direct children first
    pkill -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      pkill -9 -P "$pid" 2>/dev/null || true
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
}

CURRENT_BUDGET=$INITIAL_BUDGET
START_TIME=$(date +%s)
LAST_ACTIVITY_TIME=$START_TIME
LAST_SEEN_SIZE=0

get_file_size() {
  if [[ -f "$OUTPUT_FILE" ]]; then
    wc -c < "$OUTPUT_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

EXIT_CODE=0

# Watchdog & Dynamic Budgeting Supervisor Loop
while true; do
  if ! kill -0 "$AGENT_PID" 2>/dev/null; then
    wait "$AGENT_PID" || EXIT_CODE=$?
    break
  fi

  NOW=$(date +%s)
  ELAPSED=$(( NOW - START_TIME ))

  CURRENT_SIZE=$(get_file_size)
  if (( CURRENT_SIZE > LAST_SEEN_SIZE )); then
    LAST_ACTIVITY_TIME=$NOW
    LAST_SEEN_SIZE=$CURRENT_SIZE
  fi

  IDLE_SECONDS=$(( NOW - LAST_ACTIVITY_TIME ))

  # 1. Stall Activity Watchdog: Abort if completely idle for STALL_TIMEOUT
  if (( IDLE_SECONDS >= STALL_TIMEOUT )); then
    cleanup_subprocesses "$AGENT_PID"
    MSG="[STALL WATCHDOG] Tiến trình AI không sinh thêm dữ liệu trong ${IDLE_SECONDS}s (ngưỡng: ${STALL_TIMEOUT}s). Tự động ngắt sớm để bảo vệ tài nguyên."
    echo "" >> "$OUTPUT_FILE"
    echo "⚠️ $MSG" | tee -a "$OUTPUT_FILE" >&2
    EXIT_CODE=124
    break
  fi

  # 2. Time Budget & Dynamic Budgeting Check
  if (( ELAPSED >= CURRENT_BUDGET )); then
    # If AI has been actively generating output within the last 60s, extend budget
    if (( IDLE_SECONDS <= 60 && (CURRENT_BUDGET + EXTENSION_STEP) <= MAX_TIMEOUT )); then
      CURRENT_BUDGET=$(( CURRENT_BUDGET + EXTENSION_STEP ))
      MSG="[DYNAMIC BUDGETING] AI đang tích cực thực thi (hoạt động cách đây ${IDLE_SECONDS}s). Tự động gia hạn thêm +${EXTENSION_STEP}s (Thời hạn mới: ${CURRENT_BUDGET}s / Trần tối đa: ${MAX_TIMEOUT}s)."
      echo "" >> "$OUTPUT_FILE"
      echo "⏳ $MSG" | tee -a "$OUTPUT_FILE" >&2
    else
      # Reached hard ceiling or stalled near deadline
      cleanup_subprocesses "$AGENT_PID"
      MSG="[TIMEOUT] Lượt chạy đã vượt quá giới hạn thời gian cho phép (${CURRENT_BUDGET}s). Kết thúc phiên làm việc."
      echo "" >> "$OUTPUT_FILE"
      echo "⏰ $MSG" | tee -a "$OUTPUT_FILE" >&2
      EXIT_CODE=124
      break
    fi
  fi

  sleep 2
done

# If temporary output was used, dump to stdout and remove temp file
if [[ -n "$TEMP_OUTPUT" && -f "$TEMP_OUTPUT" ]]; then
  cat "$TEMP_OUTPUT"
  rm -f "$TEMP_OUTPUT"
fi

exit "$EXIT_CODE"
