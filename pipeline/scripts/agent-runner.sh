#!/usr/bin/env bash
# =============================================================================
# agent-runner.sh — Provider-Neutral Agent Runner Plug
# Features:
# - Multi-Dimensional Deep Activity Watchdog (CPU ticks, child subprocesses,
#   worktree filesystem mtime, output byte delta)
# - Real-time Progress Heartbeat (exposes live status for parallel workers)
# - Dynamic Budgeting (auto-extends timeout budget if AI is actively progressing)
# Supports: agy (default), claude, codex, custom
# =============================================================================
set -euo pipefail

# Ensure ~/.local/bin is on PATH for CLI tools like agy
export PATH="${HOME}/.local/bin:${PATH}"

PROVIDER="${AGENT_PROVIDER:-agy}"
OUTPUT_FILE=""
ERROR_FILE=""
MODEL=""
EFFORT=""
ROOT_DIR="$(pwd)"
RAW_TIMEOUT="${PRINT_TIMEOUT:-15m0s}"
STALL_TIMEOUT="${RALPH_STALL_TIMEOUT:-600}"    # 10 minutes default (deep reasoning, tool calls, tests)
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

HEARTBEAT_FILE="${OUTPUT_FILE}.heartbeat"

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
    pkill -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      pkill -9 -P "$pid" 2>/dev/null || true
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
}

get_file_size() {
  if [[ -f "$OUTPUT_FILE" ]]; then
    wc -c < "$OUTPUT_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

get_total_cpu_ticks() {
  local pid="$1"
  local total=0
  if [[ -d "/proc/$pid" ]]; then
    local p_stat
    p_stat=$(cat "/proc/$pid/stat" 2>/dev/null || echo "")
    if [[ -n "$p_stat" ]]; then
      local u s
      u=$(echo "$p_stat" | awk '{print $14}')
      s=$(echo "$p_stat" | awk '{print $15}')
      total=$(( total + u + s ))
    fi
    local child_pids
    child_pids=$(pgrep -P "$pid" 2>/dev/null || true)
    for cpid in $child_pids; do
      if [[ -d "/proc/$cpid" ]]; then
        local c_stat
        c_stat=$(cat "/proc/$cpid/stat" 2>/dev/null || echo "")
        if [[ -n "$c_stat" ]]; then
          local cu cs
          cu=$(echo "$c_stat" | awk '{print $14}')
          cs=$(echo "$c_stat" | awk '{print $15}')
          total=$(( total + cu + cs ))
        fi
      fi
    done
  fi
  echo "$total"
}

get_workspace_latest_mtime() {
  local dir="$1"
  local latest=0
  if [[ -d "$dir" ]]; then
    latest=$(
      set +o pipefail
      find "$dir" -maxdepth 5 -type f \
        -not -path "*/.git/*" \
        -not -path "*/.ralph/*" \
        -not -path "*/.venv/*" \
        -not -path "*/__pycache__/*" \
        -not -name "*.log" \
        -not -name "*.err" \
        -not -name "*.heartbeat" \
        -printf '%T@\n' 2>/dev/null | sort -nr | head -n 1 | cut -d. -f1
    )
  fi
  latest=$(echo "$latest" | grep -oE '^[0-9]+' | head -n 1 || true)
  [[ -z "$latest" ]] && latest=0
  echo "$latest"
}

CURRENT_BUDGET=$INITIAL_BUDGET
START_TIME=$(date +%s)
LAST_ACTIVITY_TIME=$START_TIME
LAST_SEEN_SIZE=0
LAST_SEEN_CPU=$(get_total_cpu_ticks "$AGENT_PID")
LAST_SEEN_MTIME=$(get_workspace_latest_mtime "$ROOT_DIR")
LAST_STATUS_T=0

EXIT_CODE=0

# Deep Activity Watchdog & Dynamic Budgeting Supervisor Loop
while true; do
  if ! kill -0 "$AGENT_PID" 2>/dev/null; then
    wait "$AGENT_PID" || EXIT_CODE=$?
    break
  fi

  NOW=$(date +%s)
  ELAPSED=$(( NOW - START_TIME ))

  CURRENT_SIZE=$(get_file_size)
  CURRENT_CPU=$(get_total_cpu_ticks "$AGENT_PID")
  CURRENT_MTIME=$(get_workspace_latest_mtime "$ROOT_DIR")
  CHILD_COUNT=$(pgrep -P "$AGENT_PID" 2>/dev/null | wc -l || echo 0)

  ACTIVITY_DETECTED=false
  ACTIVITY_REASON=""

  # Dimension 1: Output log file size increased
  if (( CURRENT_SIZE > LAST_SEEN_SIZE )); then
    ACTIVITY_DETECTED=true
    ACTIVITY_REASON="Output log bytes increased (+ $(( CURRENT_SIZE - LAST_SEEN_SIZE )) B)"
    LAST_SEEN_SIZE=$CURRENT_SIZE
  # Dimension 2: CPU activity across process tree (calculation, compilation, test execution)
  elif (( CURRENT_CPU > (LAST_SEEN_CPU + 10) )); then
    ACTIVITY_DETECTED=true
    ACTIVITY_REASON="CPU activity (+ $(( CURRENT_CPU - LAST_SEEN_CPU )) ticks across process tree)"
    LAST_SEEN_CPU=$CURRENT_CPU
  # Dimension 3: Workspace files created or modified by AI tools
  elif (( CURRENT_MTIME > LAST_SEEN_MTIME )); then
    ACTIVITY_DETECTED=true
    ACTIVITY_REASON="Filesystem modified in workspace"
    LAST_SEEN_MTIME=$CURRENT_MTIME
  # Dimension 4: Subprocesses running and consuming CPU
  elif (( CHILD_COUNT > 0 && CURRENT_CPU > LAST_SEEN_CPU )); then
    ACTIVITY_DETECTED=true
    ACTIVITY_REASON="${CHILD_COUNT} active subprocess(es) running"
    LAST_SEEN_CPU=$CURRENT_CPU
  fi

  if [[ "$ACTIVITY_DETECTED" == "true" ]]; then
    LAST_ACTIVITY_TIME=$NOW
  fi

  IDLE_SECONDS=$(( NOW - LAST_ACTIVITY_TIME ))

  # Periodically update heartbeat status file for parallel supervisor inspection
  if (( NOW - LAST_STATUS_T >= 10 )); then
    LAST_STATUS_T=$NOW
    echo "STATUS: Active | Elapsed: ${ELAPSED}s | Idle: ${IDLE_SECONDS}s / ${STALL_TIMEOUT}s | CPU: ${CURRENT_CPU} ticks | Children: ${CHILD_COUNT} | OutSize: ${CURRENT_SIZE}B | Latest: ${ACTIVITY_REASON:-none}" > "$HEARTBEAT_FILE" 2>/dev/null || true
  fi

  # 1. Stall Activity Watchdog: Abort ONLY if truly zero activity across all dimensions for STALL_TIMEOUT
  if (( IDLE_SECONDS >= STALL_TIMEOUT )); then
    cleanup_subprocesses "$AGENT_PID"
    MSG="[STALL WATCHDOG] Tiến trình AI và toàn bộ subprocess không có hoạt động (0 CPU ticks, 0 file changes, 0 output) trong ${IDLE_SECONDS}s (ngưỡng: ${STALL_TIMEOUT}s). Tự động ngắt sớm để bảo vệ tài nguyên."
    echo "" >> "$OUTPUT_FILE"
    echo "⚠️ $MSG" | tee -a "$OUTPUT_FILE" >&2
    EXIT_CODE=124
    break
  fi

  # 2. Time Budget & Dynamic Budgeting Check
  if (( ELAPSED >= CURRENT_BUDGET )); then
    # If AI has been actively progressing within the last 90s, extend budget
    if (( IDLE_SECONDS <= 90 && (CURRENT_BUDGET + EXTENSION_STEP) <= MAX_TIMEOUT )); then
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

# Clean heartbeat file on exit
rm -f "$HEARTBEAT_FILE" 2>/dev/null || true

# If temporary output was used, dump to stdout and remove temp file
if [[ -n "$TEMP_OUTPUT" && -f "$TEMP_OUTPUT" ]]; then
  cat "$TEMP_OUTPUT"
  rm -f "$TEMP_OUTPUT"
fi

exit "$EXIT_CODE"
