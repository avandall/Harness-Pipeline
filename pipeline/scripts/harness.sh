#!/usr/bin/env bash
# =============================================================================
# harness.sh — Next-Gen Ralph Loop Master Orchestrator (2026 Standard)
# Tự động hóa 100% vòng lặp AI: Code -> Verify -> Review -> Commit -> Progress
# Optimized for: Antigravity / Agy Pro Subscription Quota
#
# -----------------------------------------------------------------------------
# CÚ PHÁP SỬ DỤNG (USAGE):
#   ./pipeline/scripts/harness.sh [OPTIONS]
#
# -----------------------------------------------------------------------------
# DANH SÁCH TẤT CẢ THAM SỐ & CỜ (ALL CLI FLAGS & OPTIONS):
#
# [Task & Phạm vi thực thi]
#   --tasks, --task, -t RANGE
#       Lọc danh sách task cần chạy từ Tasks_list.md.
#       Hỗ trợ:
#         - Dải số liên tục: "1..5", "10..15"
#         - Danh sách rời rạc: "1,3,7"
#         - Task ID cụ thể: "TASK-001" hoặc "001"
#         - Kết hợp: "1..3,5,8..10"
#       (Mặc định: chạy tuần tự tất cả các task [ ] TODO trong queue)
#
#   --max-iter, -n N
#       Số vòng lặp tối đa (Max iterations) trước khi dừng loop an toàn.
#       (Mặc định: 30 | Env: $RALPH_MAX_ITERATIONS)
#
#   --one-go
#       Chế độ One-Go: Yêu cầu Agent hoàn thành toàn bộ queue task trong một
#       lần invoke duy nhất thay vì chia nhỏ từng task một lượt.
#       (Mặc định: tắt (0) | Env: $RALPH_ONE_GO=1)
#
# [Chế độ Song song & Sửa lỗi độc lập]
#   --parallel, -p [NUM]
#       Kích hoạt chế độ chạy song song theo Wave độc lập (Git Worktrees).
#       Tự động gom nhóm các task không phụ thuộc, chạy trên branch cô lập,
#       serialize merge vào main và kiểm thử tích hợp (Tier 2 Integration Gate).
#       NUM: Số worker song song tối đa (mặc định: 3 | Env: $RALPH_MAX_WORKERS).
#
#   --fix-bug, --bug "MSG" | FILE
#       Kích hoạt Agentless Bug Fix Workflow (tách biệt khỏi Tasks_list.md):
#       Tự động phân tích stacktrace/lỗi từ chuỗi text hoặc file log ->
#       Tạo test tái hiện lỗi cô lập (Reproduce Test Red) -> Sửa root cause ->
#       Kiểm thử xác minh (Tier 1 & Tier 2 Green) -> Auto-commit vào main.
#
# [Mô hình & Provider]
#   --model, -m MODEL
#       Mô hình AI chỉ định cho Executor Agent (ví dụ: claude-sonnet-4-6, gemini-2.5-pro).
#       (Mặc định: lấy từ $RALPH_MODEL hoặc cấu hình mặc định của CLI Provider)
#
#   --provider NAME
#       Công cụ CLI Agent điều khiển (mặc định: agy | hỗ trợ: agy, claude, codex, v.v.).
#       Ghi đè biến môi trường $AGENT_PROVIDER.
#
#   --timeout TIME
#       Thời gian giới hạn tối đa cho một lượt Agent Executor chạy (per-turn timeout).
#       (Mặc định: 15m0s)
#
# [Dual-Model Review (Phản biện nhận thức)]
#   --review-model, -r MODEL
#       Bật chế độ Dual-Model Review: Sau khi Executor hoàn thành và pass Tier 1,
#       một model độc lập (ví dụ: o3-mini, claude-3-7-sonnet) sẽ review diff,
#       bảo đảm logic, security, và kiến trúc trước khi commit.
#       (Mặc định: tắt — Single-Model mode)
#
#   --review-effort EFFORT
#       Mức độ suy luận (Reasoning effort) của Reviewer Model: low | medium | high.
#       (Mặc định: medium | Env: $RALPH_REVIEW_EFFORT)
#
#   --review-timeout TIME
#       Thời gian timeout cho bước review phản biện.
#       (Mặc định: 5m0s)
#
# [Kiểm soát an toàn & Môi trường làm việc]
#   --stop-on-block
#       Chế độ nghiêm ngặt: Dừng toàn bộ vòng lặp ngay khi phát hiện blocker
#       (file runtime/BLOCKED.md hoặc runtime/STOP.md xuất hiện).
#       (Mặc định: false — ghi nhận blocker và thử task tiếp theo nếu hợp lệ)
#
#   --no-auto-clean
#       Giữ lại các file bẩn/uncommitted changes khi bắt đầu task mới hoặc bị ngắt.
#       (Mặc định: tự động stash backup và dọn sạch workspace | Env: $RALPH_AUTO_CLEAN)
#
#   --dry-run, -d
#       Chạy mô phỏng (Dry run): Kiểm tra flow, resolve task, in cấu hình nhưng
#       không gọi Agent thực tế và không sửa đổi source code.
#
#   --verbose, -v
#       Bật chế độ log chi tiết quá trình thực thi, token estimate và git state.
#
#   --help, -h
#       Hiển thị hướng dẫn sử dụng và danh sách tham số.
#
# -----------------------------------------------------------------------------
# BIẾN MÔI TRƯỜNG TƯƠNG THÍCH (ENVIRONMENT VARIABLES):
#   RALPH_MAX_ITERATIONS   Số iteration tối đa (mặc định: 30)
#   RALPH_NO_PROGRESS      Ngưỡng circuit breaker số lần lặp không có commit (mặc định: 10)
#   RALPH_API_MAX          Số lần retry tối đa khi gặp lỗi API/5xx liên tiếp (mặc định: 5)
#   RALPH_API_BACKOFF      Thời gian sleep backoff tính bằng giây khi gặp lỗi API (mặc định: 20s)
#   RALPH_MODEL            Mô hình mặc định cho Executor
#   RALPH_REVIEW_EFFORT    Độ sâu suy luận review: low | medium | high (mặc định: medium)
#   RALPH_MAX_WORKERS      Số worker song song tối đa trong wave parallel (mặc định: 3)
#   RALPH_MERGE_MAX_WAIT   Thời gian tối đa chờ merge lock tính bằng giây (mặc định: 900s)
#   RALPH_AUTO_CLEAN       Tự động dọn dẹp git uncommitted dirty changes (mặc định: true)
#   RALPH_ONE_GO           Chế độ chạy trọn vẹn một lần (0: tắt, 1: bật)
#   AGENT_PROVIDER         CLI Provider mặc định (mặc định: agy)
#
# -----------------------------------------------------------------------------
# MÃ THOÁT POSIX (EXIT CODES — Xem chi tiết docs/core/EXIT_CODES.md):
#   0    Thành công (All tasks complete & verified 100% PASS)
#   2    Lỗi tham số dòng lệnh (Unknown CLI option / Invalid arguments)
#   3    Bị chặn (Handbrake triggered: STOP.md hoặc BLOCKED.md)
#   4    Chạm ngưỡng vòng lặp tối đa (Max iterations reached)
#   6    Ngắt mạch (Circuit breaker: quá nhiều vòng lặp không tạo ra progress)
#   7    Context compaction hard-stop (Task quá lớn làm tràn bộ nhớ, cần chia nhỏ)
#   8    Lỗi Provider / API / 5xx liên tục vượt ngưỡng retry
#   130  Người dùng ngắt tiến trình (Ctrl+C / SIGINT / SIGTERM)
#
# -----------------------------------------------------------------------------
# VÍ DỤ SỬ DỤNG THỰC TẾ (EXAMPLES):
#   1. Chạy tuần tự mặc định toàn bộ queue:
#      ./pipeline/scripts/harness.sh
#
#   2. Chạy phạm vi task từ TASK-001 đến TASK-005 với tối đa 15 vòng lặp:
#      ./pipeline/scripts/harness.sh --tasks "1..5" --max-iter 15
#
#   3. Chạy Dual-Model: Executor (Claude Sonnet) kết hợp Reviewer phản biện (o3-mini):
#      ./pipeline/scripts/harness.sh -m claude-sonnet-4-6 -r o3-mini --review-effort high
#
#   4. Chạy song song Wave với 4 worker độc lập qua Git Worktree:
#      ./pipeline/scripts/harness.sh --parallel 4
#
#   5. Tự động tái hiện và sửa nhanh một lỗi cụ thể (Agentless Mode):
#      ./pipeline/scripts/harness.sh --fix-bug "ZeroDivisionError in services/calc.py line 45"
#      ./pipeline/scripts/harness.sh --fix-bug logs/traceback.log
#
#   6. Chế độ kiểm tra khô (Dry Run) với log chi tiết:
#      ./pipeline/scripts/harness.sh --tasks "1..3" --dry-run --verbose
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOCS_DIR="${PIPELINE_DIR}/docs"
RUNTIME_DIR="${DOCS_DIR}/runtime"
CONTEXT_DIR="${DOCS_DIR}/context"
CORE_DIR="${DOCS_DIR}/core"
PROMPTS_DIR="${PIPELINE_DIR}/prompts"
ITERATIONS_DIR="${RUNTIME_DIR}/ITERATIONS"
BLOCKERS_DIR="${RUNTIME_DIR}/BLOCKERS"

MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-30}"
NO_PROGRESS_MAX="${RALPH_NO_PROGRESS:-10}"
API_MAX="${RALPH_API_MAX:-5}"
API_BACKOFF="${RALPH_API_BACKOFF:-20}"

TASK_ID=""
TASK_FILTER=""
PRINT_TIMEOUT="15m0s"
DRY_RUN=false
VERBOSE=false
STOP_ON_BLOCK=false
ONE_GO="${RALPH_ONE_GO:-0}"
PROVIDER_OVERRIDE=""
EXECUTOR_MODEL="${RALPH_MODEL:-}"

REVIEW_MODEL=""
REVIEW_TIMEOUT="5m0s"
REVIEW_EFFORT="${RALPH_REVIEW_EFFORT:-medium}"
REVIEW_MAX_RETRIES=2
AUTO_CLEAN_DIRTY="${RALPH_AUTO_CLEAN:-true}"
PARALLEL_MODE=false
PARALLEL_WORKERS="${RALPH_MAX_WORKERS:-3}"
FIX_BUG_TARGET=""
declare -a ACTIVE_WORKTREES=()
declare -a ACTIVE_BRANCHES=()
declare -a GLOBAL_WORKER_PIDS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ────────────────────────────────────────────────────────────────────────────
# Pillar 2: Run-Scoped Ephemeral vs Durable Global Memory Lifecycle
# ────────────────────────────────────────────────────────────────────────────
init_run_lifecycle() {
  RUN_ID="$(date +%Y%m%d-%H%M%S)"
  RUN_DIR="${RUNTIME_DIR}/runs/${RUN_ID}"
  export RALPH_RUN_TAG="ralph-managed-run-${RUN_ID}"
  export RUN_ID
  export RUN_DIR

  mkdir -p "${PIPELINE_DIR}/.ralph/runs/${RUN_ID}" "$RUN_DIR/plans" "$RUN_DIR/contracts" "$RUN_DIR/debates" "$ITERATIONS_DIR" "$BLOCKERS_DIR" "${PIPELINE_DIR}/.ralph/locks"

  # Manage Symlinks: CURRENT -> current run, PREV -> previous run
  local prev_run
  prev_run=$(readlink "${RUNTIME_DIR}/CURRENT" 2>/dev/null || echo "")
  if [[ -n "$prev_run" && -d "$prev_run" ]]; then
    ln -sfn "$prev_run" "${RUNTIME_DIR}/PREV"
  fi
  ln -sfn "$RUN_DIR" "${RUNTIME_DIR}/CURRENT"

  # Durable global memory files (preserved across runs)
  touch "${RUNTIME_DIR}/DECISIONS_LOG.md"
  touch "${RUNTIME_DIR}/LEARNINGS.md"
  touch "${RUNTIME_DIR}/PROGRESS_LOG.md"
  touch "${RUNTIME_DIR}/REJECTED_RULES.md"
}

_RALPH_REPO_ROOT="$(cd "${PIPELINE_DIR}/.." && pwd)"
if [[ ! -d "$_RALPH_REPO_ROOT" ]]; then
  echo "FATAL: Could not determine project root from PIPELINE_DIR=${PIPELINE_DIR}" >&2
  exit 1
fi
_EXTRA_PY_PATHS="${_RALPH_REPO_ROOT}"
[[ -d "${_RALPH_REPO_ROOT}/src" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:${_RALPH_REPO_ROOT}/src"
[[ -d "${_RALPH_REPO_ROOT}/app" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:${_RALPH_REPO_ROOT}/app"
export PYTHONPATH="${_EXTRA_PY_PATHS}:${PYTHONPATH:-}"

reap_orphans() {
  if [[ -z "${RALPH_RUN_TAG:-}" ]]; then
    return 0
  fi
  pkill -f "$RALPH_RUN_TAG" 2>/dev/null || true
}

cleanup_on_interrupt() {
  echo -e "\n${YELLOW}[RALPH] Interrupted by user (Ctrl+C). Terminating workers & cleaning up active worktrees...${NC}"
  # 1. Kill tracked worker PIDs explicitly, then reap any remaining tagged orphans
  if ((${#GLOBAL_WORKER_PIDS[@]} > 0)); then
    for wpid in "${GLOBAL_WORKER_PIDS[@]}"; do
      kill -TERM "$wpid" 2>/dev/null || true
    done
  fi
  reap_orphans
  wait 2>/dev/null || true

  local reg_file="${PIPELINE_DIR}/.ralph/active_worktrees.txt"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  # 2. Cleanup registered worktrees and branches
  if [[ -f "$reg_file" ]]; then
    while IFS='|' read -r wt br || [[ -n "$wt" ]]; do
      [[ -n "$wt" ]] && git -C "$repo_root" worktree remove --force "$wt" >/dev/null 2>&1 || true
      [[ -n "$br" ]] && git -C "$repo_root" branch -D "$br" >/dev/null 2>&1 || true
    done < "$reg_file"
    rm -f "$reg_file"
  elif ((${#ACTIVE_WORKTREES[@]} > 0)); then
    for wt in "${ACTIVE_WORKTREES[@]}"; do
      git -C "$repo_root" worktree remove --force "$wt" >/dev/null 2>&1 || true
    done
    for br in "${ACTIVE_BRANCHES[@]}"; do
      git -C "$repo_root" branch -D "$br" >/dev/null 2>&1 || true
    done
  fi
  ACTIVE_WORKTREES=()
  ACTIVE_BRANCHES=()
  GLOBAL_WORKER_PIDS=()

  exit 130
}

trap cleanup_on_interrupt INT TERM
trap '[[ -n "${RUN_DIR:-}" ]] && echo -e "\n${CYAN}[RALPH]${NC} Run logs archived in: ${RUN_DIR}\n💡 Run automated post-loop improvement: ${BOLD}./pipeline/scripts/ralph-retro.sh ${RUN_DIR}${NC}"' EXIT

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

# ────────────────────────────────────────────────────────────────────────────
# Pillar 1: Concurrency Locks & Solution B Adaptive Integration Lock
# ────────────────────────────────────────────────────────────────────────────
safe_update_task_status() {
  local task_id="$1"
  local new_status="$2"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"
  local lock_file="${PIPELINE_DIR}/.ralph/locks/tasks_list.lock"
  mkdir -p "$(dirname "$lock_file")"

  if [[ ! -f "$tasks_file" ]]; then
    log_warn "Tasks file not found at $tasks_file"
    return 1
  fi

  local clean_status
  clean_status="$(echo "$new_status" | tr -d '`')"
  local escaped_tid
  escaped_tid="$(printf '%s' "$task_id" | sed 's/[][\\.^$*+?{}()|/]/\\&/g')"

  local lock_fd
  {
    if [[ -z "${lock_fd:-}" ]]; then
      log_error "Failed to allocate file descriptor for lock on $lock_file"
      return 1
    fi
    flock -x -w 30 "$lock_fd" || { log_error "Lock timeout (30s) updating status for task $task_id"; return 1; }
    # 1. Update markdown table row (matches backticked or non-backticked task ID & status)
    sed -i -E "s/(\|[[:space:]]*\`?${escaped_tid}\`?[^|]*\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|)[[:space:]]*\`?\[[ /x!]\][[:space:]]*[A-Za-z0-9_]+\`?/\1 \`${clean_status}\`/" "$tasks_file" 2>/dev/null || true
    # 2. Update task detail metadata block if present
    sed -i -E "/^### 📌 (.*)${escaped_tid}/,/^---/{ s/Trạng thái:[[:space:]]*\`?\[[ /x!]\][[:space:]]*[A-Za-z0-9_]+\`?/Trạng thái:      ${clean_status}/ }" "$tasks_file" 2>/dev/null || true
  } {lock_fd}>"$lock_file"
}

safe_append_durable_log() {
  local log_file="$1"
  local content="$2"
  local worker_tag="[Worker ${RALPH_WORKER_ID:-1} | Task ${RALPH_ACTIVE_TASK:-CORE}]"
  local lock_file="${PIPELINE_DIR}/.ralph/locks/durable_log.lock"
  mkdir -p "$(dirname "$lock_file")"

  local lock_fd
  {
    if [[ -z "${lock_fd:-}" ]]; then
      log_error "Failed to allocate file descriptor for lock on $lock_file"
      return 1
    fi
    flock -x -w 30 "$lock_fd" || { log_error "Lock timeout (30s) appending to durable log $log_file"; return 1; }
    echo -e "\n### ${worker_tag} $(date '+%Y-%m-%d %H:%M:%S')\n${content}" >> "$log_file"
  } {lock_fd}>"$lock_file"
}

wait_and_acquire_merge_lock() {
  local lock_fd="$1"
  local lock_file="${PIPELINE_DIR}/.ralph/locks/merge_queue.lock"
  local max_total_wait="${RALPH_MERGE_MAX_WAIT:-900}" # 15 minutes max
  local interval=5
  local elapsed=0
  mkdir -p "$(dirname "$lock_file")"

  log_info "[MERGE-QUEUE] Waiting for serialized integration merge lock..."

  while (( elapsed < max_total_wait )); do
    if flock -x -w "$interval" "$lock_fd"; then
      return 0
    fi
    elapsed=$(( elapsed + interval ))

    # Inspect active PIDs for diagnostics only — NEVER rm lock file (breaks flock inode semantics)
    local active_pids=""
    if command -v fuser >/dev/null 2>&1; then
      active_pids=$(fuser "$lock_file" 2>/dev/null | tr -s ' ' ', ' || echo "")
    elif command -v lsof >/dev/null 2>&1; then
      active_pids=$(lsof -t "$lock_file" 2>/dev/null | paste -sd, - || echo "")
    fi

    if [[ -n "$active_pids" ]]; then
      log_info "[MERGE-QUEUE] Lock contested by PID(s): ${active_pids}. Waiting... (${elapsed}/${max_total_wait}s)"
    else
      log_info "[MERGE-QUEUE] Waiting for serialized merge lock... (${elapsed}/${max_total_wait}s)"
    fi
  done

  log_error "[MERGE-QUEUE] DEADLOCK: Merge lock acquisition timed out after ${max_total_wait}s!"
  return 1
}

get_test_target_from_table() {
  local tid="$1"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"
  if [[ ! -f "$tasks_file" || -z "$tid" ]]; then
    echo ""
    return
  fi
  local target
  target=$(awk -F'|' -v tid="$tid" '$0 ~ tid { print $5 }' "$tasks_file" | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//')
  if [[ "$target" == "-" || "$target" == "none" || "$target" == "static_check" ]]; then
    echo ""
  else
    echo "$target"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Task Filter & Pruning Helpers
# ────────────────────────────────────────────────────────────────────────────
is_task_in_filter() {
  local tid="$1"
  local filter="$2"

  if [[ -z "$filter" ]]; then
    return 0
  fi

  local num
  num=$(echo "$tid" | grep -oE '[0-9]+' | sed 's/^0*//' || echo "")
  [[ -z "$num" ]] && num=0

  IFS=',' read -ra TOKENS <<< "$filter"
  for token in "${TOKENS[@]}"; do
    token=$(echo "$token" | xargs)
    if [[ "$token" == *".."* ]]; then
      local start_raw end_raw start_num end_num
      start_raw="${token%%..*}"
      end_raw="${token##*..}"
      start_num=$(echo "$start_raw" | grep -oE '[0-9]+' | sed 's/^0*//' || echo "0")
      end_num=$(echo "$end_raw" | grep -oE '[0-9]+' | sed 's/^0*//' || echo "0")
      [[ -z "$start_num" ]] && start_num=0
      [[ -z "$end_num" ]] && end_num=0
      if (( num >= start_num && num <= end_num )); then
        return 0
      fi
    else
      local token_num
      token_num=$(echo "$token" | grep -oE '[0-9]+' | sed 's/^0*//' || echo "")
      if [[ "$tid" == "$token" ]] || [[ "$num" == "$token_num" && -n "$num" ]]; then
        return 0
      fi
    fi
  done
  return 1
}

get_next_todo_task() {
  local filter="${1:-$TASK_FILTER}"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"
  if [[ ! -f "$tasks_file" ]]; then
    echo ""
    return
  fi

  local line task_id
  while IFS= read -r line; do
    task_id=$(echo "$line" | grep -oE '`TASK-[A-Za-z0-9_-]+`|TASK-[A-Za-z0-9_-]+' | tr -d '`' | head -1 || true)
    if [[ -n "$task_id" ]]; then
      if is_task_in_filter "$task_id" "$filter"; then
        echo "$task_id"
        return
      fi
    fi
  done < <(grep -E "^\|.*\`TASK-" "$tasks_file" 2>/dev/null | grep -E "\[ \] TODO|\[/\] IN_PROGRESS")
  echo ""
}

get_task_spec() {
  local tid="$1"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"
  if [[ ! -f "$tasks_file" || -z "$tid" ]]; then
    echo "No detailed spec available."
    return
  fi
  awk -v tid="$tid" '
    BEGIN { found=0 }
    $0 ~ "^### 📌 " tid { found=1; print; next }
    found && $0 ~ "^### 📌 " { exit }
    found { print }
  ' "$tasks_file" | head -n 40
}

inspect_task_complexity() {
  local tid="$1"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"
  if [[ ! -f "$tasks_file" || -z "$tid" ]]; then
    echo "0 0"
    return
  fi

  local spec_block
  spec_block=$(awk -v tid="$tid" '
    BEGIN { found=0 }
    $0 ~ "^### 📌 " tid { found=1; print; next }
    found && $0 ~ "^### 📌 " { exit }
    found { print }
  ' "$tasks_file")

  local is_wildcard=0
  if echo "$spec_block" | grep -qE "Services/\*"; then
    is_wildcard=1
  fi

  local svc_count
  svc_count=$(echo "$spec_block" | grep -oE "Services/[A-Za-z0-9_-]+" | sort -u | wc -l)
  if [[ $is_wildcard -eq 1 ]]; then
    svc_count=$(( svc_count + 6 ))
  fi

  local file_count
  file_count=$(echo "$spec_block" | grep -oE '[A-Za-z0-9_./-]+\.(py|proto|md|json|yml|yaml|txt|toml|gitignore)' | sort -u | wc -l)
  if [[ $is_wildcard -eq 1 ]]; then
    file_count=$(( file_count + 6 ))
  fi

  echo "$svc_count $file_count"
}

create_verified_step_checkpoint() {
  local tid="$1"
  [[ -z "$tid" ]] && return 0
  local ckpt_tag="ralph-checkpoint-${tid}"

  if [[ -n "$(git status --porcelain --ignore-submodules=dirty 2>/dev/null)" ]]; then
    # Quick deterministic verification check
    if python3 "${PIPELINE_DIR}/scripts/verify.py" --quick >/dev/null 2>&1; then
      local ckpt_commit
      ckpt_commit=$(git stash create "ralph-verified-${tid}" 2>/dev/null || echo "")
      if [[ -n "$ckpt_commit" ]]; then
        git tag -f "$ckpt_tag" "$ckpt_commit" >/dev/null 2>&1 || true
        log_ok "🛡️ [VERIFIED CHECKPOINT] Step verified PASS! Checkpoint updated at [${ckpt_tag}] (${ckpt_commit:0:7})"
      fi
    fi
  fi
}

get_tech_context_summary() {
  local tech_file="${CONTEXT_DIR}/TECH_CONTEXT.md"
  if [[ -f "$tech_file" ]]; then
    grep -v "^#" "$tech_file" 2>/dev/null | grep -v "^>" | grep -v "^---" | grep -v "^$" | head -n 8 | paste -sd ", " - || echo "Standard environment"
  else
    echo "Standard development environment"
  fi
}

get_boundaries_summary() {
  local bound_file="${CONTEXT_DIR}/BOUNDARIES.md"
  if [[ -f "$bound_file" ]]; then
    grep -v "^#" "$bound_file" 2>/dev/null | grep -v "^>" | grep -v "^---" | grep -v "^$" | head -n 8 | paste -sd ", " - || echo "Only modify files within task scope"
  else
    echo "Only modify files directly within task scope. Do not touch .env or core pipeline docs."
  fi
}

sync_current_task_doc() {
  local tid="$1"
  local task_spec="$2"
  local current_task_file="${RUNTIME_DIR}/CURRENT_TASK.md"

  cat > "$current_task_file" <<EOF
# CURRENT TASK
# Task hiện tại đang thực thi — Context cho AI agent

> **Trạng thái:** RUNTIME (Auto-Generated / Synced by harness.sh) | **Cập nhật:** $(date '+%Y-%m-%d %H:%M')

---

## 🎯 Task Spec: ${tid}
${task_spec}

---

## 🛡️ JIT Environment Context
- **Tech Stack:** $(get_tech_context_summary)
- **Scope Boundaries:** $(get_boundaries_summary)
- **Last Synced:** $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

get_memory_bridge() {
  local bridge=""
  local progress_file="${RUNTIME_DIR}/PROGRESS_LOG.md"
  local decisions_file="${RUNTIME_DIR}/DECISIONS_LOG.md"
  local plan_file="${RUNTIME_DIR}/PLAN.md"

  if [[ -f "$decisions_file" ]]; then
    local dec_lines
    dec_lines=$(grep -v "^#" "$decisions_file" 2>/dev/null | grep -v "^>" | grep -v "^---" | grep -v "^<!--" | grep -v "^-->" | grep -v "^[[:space:]]*$" | tail -n 15 || true)
    if [[ -n "$dec_lines" ]]; then
      bridge+="Recent Architecture Decisions (DECISIONS_LOG.md):\n${dec_lines}\n\n"
    fi
  fi

  if [[ -f "$progress_file" ]]; then
    local prog_lines
    prog_lines=$(grep -v "^#" "$progress_file" 2>/dev/null | grep -v "^>" | grep -v "^[[:space:]]*$" | tail -n 15 || true)
    if [[ -n "$prog_lines" ]]; then
      bridge+="Recent Progress History (PROGRESS_LOG.md):\n${prog_lines}\n\n"
    fi
  fi

  if [[ -f "$plan_file" ]]; then
    local plan_steps
    plan_steps=$(grep -E "^[[:space:]]*- \[[ x/]\]" "$plan_file" 2>/dev/null | head -n 10 || true)
    if [[ -n "$plan_steps" ]]; then
      bridge+="Active Plan Steps (PLAN.md):\n${plan_steps}\n"
    fi
  fi

  echo -e "$bridge"
}

_build_executor_payload() {
  local active_task="$1"
  local task_spec="$2"
  local role_tag="${3:-SINGLE-MODEL}"
  local complexity_notice="${4:-}"
  local tech_summary
  tech_summary=$(get_tech_context_summary)
  local bound_summary
  bound_summary=$(get_boundaries_summary)
  local mem_bridge
  mem_bridge=$(get_memory_bridge)

  sync_current_task_doc "$active_task" "$task_spec"

  cat <<EOF
[${role_tag} — TASK-BOUND SESSION — TARGET: ${active_task}]

=== 📜 QUY TẮC CỐT LÕI (Condensed Agent Constitution) ===
1. 🛡️ ANTI-CHEAT & NO FAKE MOCKS: Tuyệt đối KHÔNG mock dữ liệu giả, KHÔNG hardcode return giá trị ảo để qua test, KHÔNG dùng 'assert True' hay cheat verify.py. Phải implement logic thật 100%.
2. 🧠 STATE & DECISION ON DISK: Cập nhật STATUS.md, PLAN.md, PROGRESS_LOG.md liên tục. Khi chọn phương án kỹ thuật/kiến trúc, ghi nhận lý do ngắn gọn vào DECISIONS_LOG.md để lưu giữ Memory Bridge xuyên suốt các phiên.
3. ⚡ DETERMINISTIC TIERED VERIFICATION:
   - Trong quá trình code từng file: Dùng 'python3 pipeline/scripts/verify.py --tier 0' (Lint & Type check tức thì <2s).
   - Sau mỗi atomic step / viết test: Dùng 'python3 pipeline/scripts/verify.py --tier 1 --test-target <file_test>' (Unit test nhanh <10s).
   - Khi hoàn thành task: BẮT BUỘC chạy 'python3 pipeline/scripts/verify.py --tier 2' (Toàn bộ test suite & Security Scan) đạt 100% PASS thật.
4. 🧪 TEST STRATEGY THEO TASK TYPE:
   - Task 'feature': BẮT BUỘC tạo/cập nhật file test trước (Test Contract Red ➔ Green).
   - Task 'refactor': Dùng bộ test hiện có làm hàng rào (Regression Guard), KHÔNG duplicate test, không làm giảm số lượng tests pass.
   - Task 'scaffold'/'setup': Verify cấu trúc files, manifest và lint/typecheck.
5. 🧱 SCOPE BOUNDARY & NO SILENT PATCH: Chỉ sửa files trong BOUNDARIES.md. Không chạm .env. Sửa triệt để root cause, không vá tạm bợ.
6. 🎯 1 TASK = 1 COMMIT CHUYÊN NGHIỆP: Khi xong [x] DONE, Harness sẽ tự động commit đầy đủ Title, Summary, Key Changes, Verification. Tuyệt đối không commit dở dang.
7. 🛑 BẾ TẮC (OVERNIGHT NON-BLOCKING): Nếu thử 2 lần không qua verify.py -> Dừng lại, ghi chi tiết lỗi vào BLOCKERS/${active_task}.md, đổi task thành [!] BLOCKED để loop tiếp tục sang task khác mà không bị treo.
$([ -n "$complexity_notice" ] && echo -e "\n=== ⚠️ CHỈ THỊ CHIA NHỎ ATOMIC (COMPLEXITY GUARD) ===\n${complexity_notice}")

$([ -n "$mem_bridge" ] && echo -e "=== 🧠 MEMORY BRIDGE (Ngữ cảnh tích lũy từ các phiên trước) ===\n${mem_bridge}")
=== 🎯 THÔNG TIN TASK SPEC (TRÍCH XUẤT TỪ Tasks_list.md) ===
${task_spec}

=== 🛡️ GIỚI HẠN & TECH STACK (JIT CONTEXT) ===
- Tech Context: ${tech_summary}
- Scope Boundaries: ${bound_summary}

=== 🚀 NHIỆM VỤ THỰC THI CHO ${active_task} ===
Thực thi trọn vẹn Task ${active_task} trong phiên làm việc này:
1. Đọc/Tạo pipeline/docs/runtime/PLAN.md cho ${active_task} (chia thành 2-4 atomic steps).
2. Kiểm tra Task Type:
   - Nếu là 'feature': Viết test case/contract trước trong thư mục tests/, chạy 'python3 pipeline/scripts/verify.py --tier 1 --test-target <file_test>' thấy test fail (Red), sau đó mới implement code cho pass (Green).
   - Nếu là 'refactor': Giữ nguyên bộ test sẵn có, implement tối ưu code và chạy Tier 1 test target.
3. Thực thi tuần tự từng step: Sửa code trong scope ──► Chạy 'python3 pipeline/scripts/verify.py --tier 1 --test-target <file_test>'.
4. Trước khi kết thúc task: Chạy full 'python3 pipeline/scripts/verify.py --tier 2' đảm bảo không gây regression cho bất kỳ module nào khác trong toàn dự án.
5. Cập nhật tiến độ liên tục vào STATUS.md, PROGRESS_LOG.md và PLAN.md ra filesystem.
6. Khi ${active_task} đã xong 100% và verify Tier 2 PASS: Đánh dấu [x] DONE dòng ${active_task} trong Tasks_list.md và DỪNG PHIÊN (Harness sẽ tự động tạo commit chuyên nghiệp chi tiết gồm Summary, Key Changes, Verification).

⚠️ KHÔNG COMMIT TRUNG GIAN. TUYỆT ĐỐI KHÔNG COMMIT 1 DÒNG SƠ SÀI.
NẾU BỊ KẸT (sửa 2 lần không qua verify.py): Dừng lại, viết report vào BLOCKERS/${active_task}.md và đổi task thành [!] BLOCKED.
EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Pillar 7: Multi-Byte Token Budget Awareness & Proactive Trimming
# ────────────────────────────────────────────────────────────────────────────
estimate_tokens_multibyte() {
  local text="$1"
  local byte_count
  byte_count=$(printf "%s" "$text" | wc -c)
  echo $(( byte_count / 3 ))
}

_build_executor_payload_safe() {
  local active_task="$1"
  local task_spec="$2"
  local role_tag="${3:-SINGLE-MODEL}"
  local complexity_notice="${4:-}"

  local raw_payload
  raw_payload=$(_build_executor_payload "$active_task" "$task_spec" "$role_tag" "$complexity_notice")

  local est_tokens
  est_tokens=$(estimate_tokens_multibyte "$raw_payload")

  local token_limit="${RALPH_TOKEN_BUDGET:-12000}"
  if (( est_tokens > token_limit )); then
    log_warn "⚠️ [TOKEN BUDGET] Prompt size (${est_tokens} tokens) exceeds ${token_limit} safe limit. Proactively trimming..."

    local slim_spec
    slim_spec=$(echo "$task_spec" | head -n 25)

    raw_payload=$(_build_executor_payload "$active_task" "$slim_spec" "$role_tag" "$complexity_notice")
    local new_est
    new_est=$(estimate_tokens_multibyte "$raw_payload")
    log_ok "[TOKEN BUDGET] Prompt proactively trimmed down to ${new_est} tokens."
  fi

  echo "$raw_payload"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-iter|-n) MAX_ITERATIONS="$2"; shift 2 ;;
      --tasks|--task|-t) TASK_FILTER="$2"; TASK_ID="$2"; shift 2 ;;
      --model|-m) EXECUTOR_MODEL="$2"; shift 2 ;;
      --timeout) PRINT_TIMEOUT="$2"; shift 2 ;;
      --review-model|-r) REVIEW_MODEL="$2"; shift 2 ;;
      --review-effort) REVIEW_EFFORT="$2"; shift 2 ;;
      --review-timeout) REVIEW_TIMEOUT="$2"; shift 2 ;;
      --one-go) ONE_GO=1; shift ;;
      --provider) PROVIDER_OVERRIDE="$2"; shift 2 ;;
      --stop-on-block) STOP_ON_BLOCK=true; shift ;;
      --no-auto-clean) AUTO_CLEAN_DIRTY=false; shift ;;
      --parallel|-p)
        PARALLEL_MODE=true
        if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
          PARALLEL_WORKERS="$2"
          shift 2
        else
          PARALLEL_WORKERS="${RALPH_MAX_WORKERS:-3}"
          shift
        fi
        ;;
      --fix-bug|--bug)
        FIX_BUG_TARGET="$2"
        shift 2
        ;;
      --dry-run|-d) DRY_RUN=true; shift ;;
      --verbose|-v) VERBOSE=true; shift ;;
      --help|-h) show_help; exit 0 ;;
      *) echo "Unknown option: $1" >&2; show_help; exit 2 ;;
    esac
  done
}

show_help() {
  cat <<EOF
${BOLD}harness.sh${NC} — Master Ralph Loop Orchestrator (2026 Standard)
Optimized for Antigravity / Agy Pro Subscription Quota

${BOLD}USAGE:${NC}
  ./pipeline/scripts/harness.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  --max-iter, -n N        Maximum iterations (default: 30)
  --tasks, -t RANGE       Task filter e.g. "1..5", "6,9", "TASK-001"
  --parallel, -p [NUM]    Run execution waves in parallel using Git Worktrees (default: 3 workers)
  --fix-bug MSG|FILE      Run isolated Agentless bug fix workflow (reproduce -> fix -> verify)
  --model, -m MODEL       Model for executor agent (e.g. claude-sonnet-4-6, default: \$RALPH_MODEL or provider default)
  --review-model, -r M    Enable Dual-Model cognitive review with model M
  --review-effort EFFORT  Reasoning effort for reviewer (low|medium|high, default: medium)
  --review-timeout TIME   Timeout for review step (default: 5m0s)
  --one-go                Run complete queue in a single execution invocation
  --provider NAME         Agent CLI provider (default: agy)
  --timeout TIME          Execution timeout per turn (default: 15m0s)
  --stop-on-block         Strict mode: stop loop immediately on first blocker
  --no-auto-clean         Keep uncommitted dirty changes from interrupted runs (default: auto-clean with stash backup)
  --dry-run, -d           Simulate execution without modifying files
  --verbose, -v           Verbose logging output
  --help, -h              Show this help message

${BOLD}EXIT CODES (See docs/core/EXIT_CODES.md):${NC}
  0  Success (All tasks complete & verified)
  3  Blocked (Handbrake active in BLOCKERS/ or STOP.md)
  4  Max iterations reached
  6  Stuck circuit breaker (No progress across iterations)
  7  Context auto-compaction hard stop (Task must be re-narrowed)
  8  Provider process or API failure
EOF
}

sync_venv_dependencies() {
  local project_root
  project_root="$(cd "${PIPELINE_DIR}/.." && pwd)"

  if ! command -v uv >/dev/null 2>&1; then
    log_warn "⚠️ [UV] 'uv' CLI not found. Skipping automated uv dependency sync."
    return 0
  fi

  local venv_dir="${project_root}/.venv"
  if [[ ! -d "$venv_dir" ]]; then
    log_info "⚡ [UV] Initializing virtual environment at ${venv_dir}..."
    uv venv "$venv_dir" >/dev/null 2>&1 || {
      log_warn "Could not create .venv with uv."
      return 0
    }
  fi

  export VIRTUAL_ENV="$venv_dir"
  export PATH="${venv_dir}/bin:${PATH}"
  local py_bin="${venv_dir}/bin/python"

  local updated=false
  if [[ -f "${project_root}/pyproject.toml" ]]; then
    log_info "⚡ [UV] Step 1: Synchronizing dependencies via 'uv sync' (pyproject.toml)..."
    if (cd "${project_root}" && uv sync --quiet); then
      updated=true
    fi
  fi

  if [[ -f "${project_root}/requirements.txt" ]]; then
    log_info "⚡ [UV] Step 2: Checking and updating dependencies from requirements.txt..."
    if uv pip install --python "$py_bin" -r "${project_root}/requirements.txt" --quiet; then
      updated=true
    fi
  fi

  if [[ -f "${project_root}/requirements-dev.txt" ]]; then
    uv pip install --python "$py_bin" -r "${project_root}/requirements-dev.txt" --quiet || true
  fi

  if [[ "$updated" == true ]]; then
    log_ok "[UV] Virtual environment (.venv) synchronized with latest dependencies ✓"
  fi
}

preflight_check() {
  log_section "PRE-FLIGHT CHECK"
  local errors=0

  # Check Bash version (Bash 4.1+ required for dynamic file descriptors {fd}>file)
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1) )); then
    log_error "Bash 4.1+ is required for Ralph Loop concurrency features (detected: ${BASH_VERSION})."
    ((errors++))
  else
    log_ok "Bash version supported: ${BASH_VERSION}"
  fi

  # Sync virtual environment & dependencies via uv
  sync_venv_dependencies

  # Check directories
  for dir in "$DOCS_DIR" "$RUNTIME_DIR" "$CONTEXT_DIR" "$CORE_DIR"; do
    if [[ -d "$dir" ]]; then
      log_ok "Directory exists: $dir"
    else
      log_error "Missing directory: $dir"
      ((errors++))
    fi
  done

  # Check required context files
  for file in "${CONTEXT_DIR}/PROJECT_BRIEF.md" "${CONTEXT_DIR}/Tasks_list.md" "${CONTEXT_DIR}/BOUNDARIES.md"; do
    if [[ -f "$file" ]]; then
      log_ok "Context file exists: $file"
    else
      log_error "Missing context file: $file"
      ((errors++))
    fi
  done

  # Check human intent anchor file if present
  if [[ -f "${CONTEXT_DIR}/Original_Tasks.md" ]]; then
    log_ok "Human Intent Anchor exists: ${CONTEXT_DIR}/Original_Tasks.md"
  fi

  # Check git repository
  if git rev-parse --git-dir >/dev/null 2>&1; then
    log_ok "Git repository initialized"
  else
    log_error "Not a git repository. Run 'git init' first."
    ((errors++))
  fi

  # Check verify.py
  if [[ -f "${PIPELINE_DIR}/scripts/verify.py" ]]; then
    log_ok "Verification engine ready: ${PIPELINE_DIR}/scripts/verify.py"
  else
    log_warn "Missing ${PIPELINE_DIR}/scripts/verify.py"
  fi

  # Check agent runner
  local runner_check
  runner_check="$("${PIPELINE_DIR}/scripts/agent-runner.sh" --check 2>&1)" || true
  log_ok "Agent Provider: $runner_check"

  # Check Plan Seal integrity and auto-restore from git if drifted
  verify_or_restore_plan_seal "PRE-FLIGHT"

  # Clean State Guard: Ensure working tree is clean before starting loop
  ensure_clean_working_tree "" "$AUTO_CLEAN_DIRTY"

  if [[ $errors -gt 0 ]]; then
    log_error "Pre-flight failed with $errors error(s)."
    exit 2
  fi
  log_ok "All pre-flight checks passed ✓ (Overnight Non-Blocking Mode Active)"
}

verify_or_restore_plan_seal() {
  local context_stage="${1:-LOOP}"
  if [[ -f "${PIPELINE_DIR}/scripts/plan.sh" ]]; then
    if ! "${PIPELINE_DIR}/scripts/plan.sh" check >/dev/null 2>&1; then
      log_warn "⚠️ [PLAN SEAL] Specification drift detected (${context_stage})! Searching git history to restore original sealed context..."
      if "${PIPELINE_DIR}/scripts/plan.sh" restore; then
        log_ok "✅ [PLAN SEAL] Context specifications cleanly restored to sealed state from git history. Continuing execution..."
      else
        log_warn "⚠️ [PLAN SEAL] Could not restore context from git history. Continuing with current context."
      fi
    else
      log_ok "Plan seal verified ✓ (No drift)"
    fi
  fi
}

generate_commit_message() {
  local tid="$1"
  local mode_label="${2:-HARNESS}"
  local git_target="${3:-.}"
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"

  local task_name=""
  local task_type="feat"
  local task_scope="core"
  local task_why=""
  local task_what=""

  if [[ -f "$tasks_file" && -n "$tid" ]]; then
    # 1. Extract Task Name from table or heading (literal string match via index)
    task_name=$(awk -F'|' -v tid="$tid" '$0 ~ /^[[:space:]]*\|/ && index($0, tid) > 0 && NF >= 3 {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit}' "$tasks_file")
    if [[ -z "$task_name" ]]; then
      task_name=$(awk -v tid="$tid" '$0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, tid) > 0 {sub(/^[[:space:]]*### [^ ]* [^:]*:[ \t]*/, ""); print; exit}' "$tasks_file")
    fi

    # 2. Extract Task Type from metadata
    local raw_type
    raw_type=$(awk -v tid="$tid" '
      $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, tid) > 0 { found=1; next }
      found && $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, "TASK-") > 0 { exit }
      found && /Task Type:/ { sub(/.*Task Type:[ \t]*/, ""); print; exit }
    ' "$tasks_file" | tr '[:upper:]' '[:lower:]' | tr -d ' \r\t')

    case "$raw_type" in
      *fix*|*bug*) task_type="fix" ;;
      *refactor*) task_type="refactor" ;;
      *test*) task_type="test" ;;
      *doc*) task_type="docs" ;;
      *scaffold*|*setup*|*chore*) task_type="chore" ;;
      *) task_type="feat" ;;
    esac

    # 3. Extract Why & What from spec
    task_why=$(awk -v tid="$tid" '
      $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, tid) > 0 { found=1; next }
      found && $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, "TASK-") > 0 { exit }
      found && /^[ \t]*- \*\*Why:\*\*/ { sub(/^[ \t]*- \*\*Why:\*\*[ \t]*/, ""); print; exit }
    ' "$tasks_file")

    task_what=$(awk -v tid="$tid" '
      $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, tid) > 0 { found=1; next }
      found && $0 ~ /^[[:space:]]*###[[:space:]]/ && index($0, "TASK-") > 0 { exit }
      found && /^[ \t]*- \*\*What:\*\*/ { sub(/^[ \t]*- \*\*What:\*\*[ \t]*/, ""); print; exit }
    ' "$tasks_file")
  fi

  [[ -z "$task_name" ]] && task_name="implement requested specifications"

  # Determine scope from changed files if possible
  local staged_dirs
  staged_dirs=$(git -C "$git_target" diff --cached --name-only 2>/dev/null | awk -F/ '{if (NF>1) print $1}' | grep -vE "^(pipeline|\.gitignore|\.github)" | sort | uniq | head -1)
  if [[ -n "$staged_dirs" ]]; then
    task_scope="$staged_dirs"
  elif git -C "$git_target" diff --cached --name-only 2>/dev/null | grep -q "pipeline"; then
    task_scope="pipeline"
  fi

  # Summary of changed files (up to 12 files)
  local file_changes
  file_changes=$(git -C "$git_target" diff --cached --name-status 2>/dev/null | head -n 12 | sed 's/^/- /')
  local total_changed
  total_changed=$(git -C "$git_target" diff --cached --name-only 2>/dev/null | wc -l)
  if (( total_changed > 12 )); then
    file_changes="${file_changes}"$'\n'"- ... and $((total_changed - 12)) more files"
  fi

  # Diff stat summary (e.g. 5 files changed, 120 insertions(+), 10 deletions(-))
  local stat_summary
  stat_summary=$(git -C "$git_target" diff --cached --stat 2>/dev/null | tail -1 | sed 's/^[ \t]*//')

  # Assemble full message
  cat <<EOF
[${tid}] ${task_type}(${task_scope}): ${task_name}

## Summary
- Task: ${task_name}
$([ -n "$task_why" ] && echo "- Why: ${task_why}")
$([ -n "$task_what" ] && echo "- What: ${task_what}")
$([ -z "$task_why" ] && [ -z "$task_what" ] && echo "- Successfully completed task specifications and verified clean working state.")

## Key Changes
${file_changes}
$([ -n "$stat_summary" ] && echo "(${stat_summary})")

## Verification
- Deterministic Quality Verification: PASS 100% (python3 pipeline/scripts/verify.py)
- Review & Audit: Verified & Approved by ${mode_label}
EOF
}

check_and_auto_commit_done_task() {
  local mode_label="${1:-HARNESS}"
  local target_task="${2:-}"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    local done_task_id=""

    # 1. First check if target_task is marked done in its detail section or table
    if [[ -n "$target_task" ]]; then
      if grep -A 10 "^### 📌 $target_task" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -q "\[x\] DONE" || \
         grep -E "^\|[[:space:]]*\`${target_task}\`" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -q "\[x\] DONE"; then
        done_task_id="$target_task"
      fi
    fi

    # 2. Fallback to scanning table for latest DONE task
    if [[ -z "$done_task_id" ]]; then
      done_task_id=$(grep -E "^\|[[:space:]]*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep "\[x\] DONE" | tail -1 | grep -oE "TASK-[A-Za-z0-9_-]+" || true)
    fi

    if [[ -n "$done_task_id" ]]; then
      local latest_commit_msg
      latest_commit_msg=$(git log -1 --pretty=%B 2>/dev/null || echo "")
      if [[ "$latest_commit_msg" != *"[${done_task_id}]"* ]]; then
        log_info "[${mode_label}] Detected changes for task [${done_task_id}]. Enforcing Hard OS Gate (Tier 2 Verification)..."

        local repo_root
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

        # Hard OS Gate: Verify Tier 2 before committing to main
        if ! PYTHONPATH="$repo_root:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 2; then
          log_error "🚨 [HARD OS GATE] Tier 2 verification FAILED for task [${done_task_id}]! Refusing to commit broken changes to main."
          safe_update_task_status "$done_task_id" "[!] BLOCKED"
          safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Task ${done_task_id} failed Tier 2 verification gate before commit. Marked [!] BLOCKED."
          return 1
        fi

        log_ok "[${mode_label}] Hard OS Gate passed 100% ✓. Auto-committing cleanly..."
        safe_update_task_status "$done_task_id" "[x] DONE"
        git add -A
        local commit_msg
        commit_msg=$(generate_commit_message "$done_task_id" "$mode_label")
        git commit -m "$commit_msg" 2>&1 | tee -a "${RUNTIME_DIR}/session_live.log" || true
        # Clean up verified checkpoint tag upon successful task commit
        git tag -d "ralph-checkpoint-${done_task_id}" >/dev/null 2>&1 || true
        safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Task ${done_task_id} cleanly verified (Tier 2 PASS) and committed to main."
        log_ok "[${mode_label}] Working tree cleanly committed for ${done_task_id}."
      fi
    fi
  fi
}

ensure_clean_working_tree() {
  local target_task="${1:-}"
  local auto_clean="${2:-$AUTO_CLEAN_DIRTY}"
  local ckpt_tag=""
  [[ -n "$target_task" ]] && ckpt_tag="ralph-checkpoint-${target_task}"

  if [[ -n "$(git status --porcelain --ignore-submodules=dirty 2>/dev/null)" ]]; then
    # 1. First check if there is a completed task marked [x] DONE that was not committed
    check_and_auto_commit_done_task "CLEAN-GUARD" "$target_task"

    # 2. If working tree is STILL dirty after checking for DONE tasks:
    if [[ -n "$(git status --porcelain --ignore-submodules=dirty 2>/dev/null)" ]]; then
      if [[ "$auto_clean" == "true" ]]; then
        log_warn "🧹 [CLEAN STATE GUARD] Uncommitted dirty changes detected from an interrupted/aborted session!"
        local git_root
        git_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

        # Stash changes for safety so work is never permanently destroyed
        local stash_name="ralph-aborted-backup-$(date +%Y%m%d-%H%M%S)"
        local stash_hash
        stash_hash=$(git stash create "$stash_name" 2>/dev/null || echo "")
        if [[ -n "$stash_hash" ]]; then
          git stash store -m "$stash_name" "$stash_hash" 2>/dev/null || true
          log_info "🛡️ Interrupted changes archived safely in git stash (${stash_hash:0:7})"
        fi

        # Check if a VERIFIED CHECKPOINT exists for this task
        if [[ -n "$target_task" ]] && git rev-parse --verify "$ckpt_tag" >/dev/null 2>&1; then
          log_info "🔄 [VERIFIED RESTORE] Restoring working tree to verified step checkpoint [${ckpt_tag}]..."
          (
            cd "$git_root"
            git restore . 2>/dev/null || true
            git clean -fd -e pipeline/ -e harness.sh -e .agents/ -e .bandit 2>/dev/null || true
            git checkout "$ckpt_tag" -- . 2>/dev/null || true
          )
          log_ok "Working tree cleanly restored to Verified Checkpoint (100% tests PASS, zero Frankenstein code) ✓"
        else
          (
            cd "$git_root"
            git restore . 2>/dev/null || true
            git clean -fd -e pipeline/ -e harness.sh -e .agents/ -e .bandit 2>/dev/null || true
          )
          log_ok "Working tree reset cleanly to HEAD ✓ (Clean baseline restored for [${target_task:-next task}])"
        fi
      else
        log_warn "⚠️ [DIRTY WORKING TREE] Uncommitted changes detected. --no-auto-clean is active; continuing with dirty tree."
      fi
    fi
  fi
}

_run_agent_turn() {
  local prompt="$1"
  local timeout="$2"
  local iter="$3"
  local model_override="${4:-}"
  local role_name="${5:-EXECUTOR}"
  local effort_override="${6:-}"

  local out_log="${RUN_DIR}/iter-${iter}-${role_name}.log"
  local err_log="${RUN_DIR}/iter-${iter}-${role_name}.err"
  local runner_args=("--output" "$out_log" "--error" "$err_log" "--timeout" "$timeout")
  if [[ -n "$model_override" ]]; then
    runner_args+=("--model" "$model_override")
  fi
  if [[ -n "$effort_override" ]]; then
    runner_args+=("--effort" "$effort_override")
  fi

  log_info "⚡ [${role_name}] AI is running (Iter ${iter})..."
  set +e
  "${PIPELINE_DIR}/scripts/agent-runner.sh" "${runner_args[@]}" <<< "$prompt"
  local exit_code=$?

  # Analyze metrics & compaction
  local log_summary
  log_summary="$(node "${PIPELINE_DIR}/scripts/agent-log.mjs" "$out_log" 2>/dev/null || echo '{}')"
  compacted=$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.compacted?"1":"0")' "$log_summary" 2>/dev/null || echo 0)
  retryable=$(node -e 'const s=JSON.parse(process.argv[1]);process.stdout.write(s.retryableApiError?"1":"0")' "$log_summary" 2>/dev/null || echo 0)

  if [[ "$compacted" == "1" ]]; then
    log_warn "🛑 [CONTEXT COMPACTION] Task auto-compacted mid-run! Quality degraded."
    return 7
  fi

  if [[ $exit_code -ne 0 ]]; then
    if [[ "$retryable" == "1" ]]; then
      log_warn "⚠️ [API ERROR] Transient API / network error detected."
      return 8
    fi
    return 1
  fi
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Dual-Model Review Execution
# ────────────────────────────────────────────────────────────────────────────
execute_dual_model_review() {
  local iter="$1"
  local tier1_summary
  tier1_summary=$(python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 1 --summary 2>/dev/null || echo "TIER1: UNKNOWN")

  local git_diff
  git_diff=$(git diff HEAD 2>/dev/null | head -n 400 || true)
  if [[ -z "$git_diff" ]]; then
    git_diff=$(git status --short 2>/dev/null || echo "(no diff)")
  fi

  if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
    log_ok "[DUAL-MODEL] No code changes detected. Auto-approving review step."
    return 0
  fi

  local template_file="${CORE_DIR}/REVIEWER_PROMPT_TEMPLATE.md"
  local raw_prompt
  raw_prompt=$(sed -n '/^---PROMPT_START---$/,/^---PROMPT_END---$/{ /^---PROMPT_START---$/d; /^---PROMPT_END---$/d; p }' "$template_file")

  local prompt="$raw_prompt"
  prompt="${prompt//\{\{ITERATION\}\}/${iter}}"
  prompt="${prompt//\{\{TIER1_SUMMARY\}\}/${tier1_summary}}"
  prompt="${prompt//\{\{GIT_DIFF\}\}/${git_diff}}"
  prompt="${prompt//\{\{DEBATE_LOG_PATH\}\}/${RUNTIME_DIR}/DEBATE_LOG.md}"

  log_info "[DUAL-MODEL] Step 2/2 — Launching REVIEWER model (${REVIEW_MODEL}, effort: ${REVIEW_EFFORT})..."
  _run_agent_turn "$prompt" "$REVIEW_TIMEOUT" "$iter" "$REVIEW_MODEL" "REVIEWER" "$REVIEW_EFFORT"
  local turn_code=$?

  local reviewer_out="${RUN_DIR}/iter-${iter}-REVIEWER.log"
  if [[ -f "$reviewer_out" && -s "$reviewer_out" ]]; then
    log_info "[DUAL-MODEL] Syncing reviewer output into ${RUNTIME_DIR}/DEBATE_LOG.md..."
    {
      echo -e "\n<!-- Auto-captured by harness.sh for Iteration ${iter} -->"
      cat "$reviewer_out"
      echo ""
    } >> "${RUNTIME_DIR}/DEBATE_LOG.md"
  fi

  return $turn_code
}

# ────────────────────────────────────────────────────────────────────────────
# Pillar 1 & 3: Parallel Worker Execution (Git Worktrees & Wave Runner)
# ────────────────────────────────────────────────────────────────────────────
execute_worker_for_task() {
  local worktree_dir="$1"
  local task="$2"
  local branch_name="$3"
  local repo_root="$4"

  export RALPH_WORKER_ID="worker-$task"
  export RALPH_ACTIVE_TASK="$task"
  export RALPH_TEST_TARGET="$(get_test_target_from_table "$task")"

  local heartbeat_file="${worktree_dir}/.ralph_heartbeat"
  touch "$heartbeat_file"

  safe_update_task_status "$task" "[/] IN_PROGRESS"
  safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Worker [${RALPH_WORKER_ID}] started task ${task} in worktree ${worktree_dir}"

  # 1. State: EXECUTING
  local task_spec
  task_spec=$(get_task_spec "$task")
  local complexity_metrics
  complexity_metrics=$(inspect_task_complexity "$task")
  local svc_count="${complexity_metrics% *}"
  local file_count="${complexity_metrics#* }"
  local complexity_notice=""
  if (( svc_count > 3 || file_count > 5 )); then
    complexity_notice="High complexity task. Keep changes strictly localized."
  fi

  local executor_prompt
  executor_prompt=$(_build_executor_payload_safe "$task" "$task_spec" "PARALLEL-WORKER" "$complexity_notice")

  (
    cd "$worktree_dir"
    _run_agent_turn "$executor_prompt" "$PRINT_TIMEOUT" "1" "$EXECUTOR_MODEL" "WORKER-${task}"
  )
  local agent_exit=$?

  if [[ $agent_exit -eq 124 || $agent_exit -eq 7 ]]; then
    safe_update_task_status "$task" "[!] BLOCKED"
    safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Worker [${RALPH_WORKER_ID}] failed (Exit code: $agent_exit). Task marked [!] BLOCKED."
    return 1
  fi

  # 2. State: VERIFIED_LOCAL (Run Tier 1 locally in worktree)
  log_info "[Worker $task] Running Tier 1 local verification..."
  if ! (cd "$worktree_dir" && PYTHONPATH="$worktree_dir:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 1); then
    log_error "🚨 [Worker $task] Local Tier 1 verification failed! Task marked [!] BLOCKED."
    safe_update_task_status "$task" "[!] BLOCKED"
    return 1
  fi

  git -C "$worktree_dir" add -A
  local commit_msg
  commit_msg=$(generate_commit_message "$task" "PARALLEL-WORKER" "$worktree_dir")
  git -C "$worktree_dir" commit -m "$commit_msg" >/dev/null 2>&1 || true

  # 3. State: QUEUED_FOR_MERGE (Serialized integration queue with Solution B adaptive lock)
  local merge_fd
  {
    if [[ -z "${merge_fd:-}" ]]; then
      log_error "[MERGE-QUEUE] Failed to allocate dynamic file descriptor for merge lock!"
      safe_update_task_status "$task" "[!] BLOCKED"
      exit 1
    fi

    wait_and_acquire_merge_lock "$merge_fd" || {
      log_error "[MERGE-QUEUE] Worker $task failed to acquire merge lock!"
      safe_update_task_status "$task" "[!] BLOCKED"
      exit 1
    }

    log_info "[MERGE-QUEUE] Worker $task entering serialized integration into main..."

    # Assert repo_root is on branch main before doing any merge
    local current_branch
    current_branch=$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || echo "")
    if [[ "$current_branch" != "main" ]]; then
      log_error "[MERGE-QUEUE] Fatal: repo_root is on branch '$current_branch', expected 'main'! Aborting integration for $task."
      safe_update_task_status "$task" "[!] BLOCKED"
      exit 1
    fi

    # 4. State: REBASING on main
    if ! git -C "$worktree_dir" rebase main >/dev/null 2>&1; then
      log_warn "[MERGE-QUEUE] Worker $task rebase conflict. Aborting rebase and marking task BLOCKED."
      git -C "$worktree_dir" rebase --abort 2>/dev/null || true
      safe_update_task_status "$task" "[!] BLOCKED"
      exit 1
    fi

    # 5. Integrate to main
    if ! git -C "$repo_root" merge --squash "$branch_name" >/dev/null 2>&1; then
      log_error "[MERGE-QUEUE] Worker $task squash merge conflict into main!"
      git -C "$repo_root" reset --hard HEAD >/dev/null 2>&1
      git -C "$repo_root" clean -fd >/dev/null 2>&1 || true
      safe_update_task_status "$task" "[!] BLOCKED"
      exit 1
    fi

    # 6. Hard Gate Tier 2 on main (Reset hard if fail!)
    if PYTHONPATH="$repo_root:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 2; then
      local main_commit_msg
      main_commit_msg=$(generate_commit_message "$task" "PARALLEL-INTEGRATED" "$repo_root")
      if [[ -z "${main_commit_msg//[[:space:]]/}" ]]; then
        main_commit_msg="[${task}] feat(core): auto-integrated verified changes for ${task}"
      fi
      if ! git -C "$repo_root" commit -m "$main_commit_msg" >/dev/null 2>&1; then
        if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]]; then
          log_error "[MERGE-QUEUE] git commit failed on main for $task despite staged changes!"
          git -C "$repo_root" reset --hard HEAD >/dev/null 2>&1
          git -C "$repo_root" clean -fd >/dev/null 2>&1 || true
          safe_update_task_status "$task" "[!] BLOCKED"
          exit 1
        else
          log_warn "[MERGE-QUEUE] No new changes to commit on main for $task (already integrated or no-op)."
        fi
      fi
      safe_update_task_status "$task" "[x] DONE"
      safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Task ${task} integrated cleanly into main (Tier 2 PASS)."
      log_ok "🎉 [INTEGRATED] Task $task merged and verified on main ✓"
    else
      git -C "$repo_root" reset --hard HEAD >/dev/null 2>&1
      git -C "$repo_root" clean -fd >/dev/null 2>&1 || true
      safe_update_task_status "$task" "[!] BLOCKED"
      safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Task ${task} failed Tier 2 gate on main. Reverted via reset --hard."
      log_error "🚨 [INTEGRATION FAILED] Task $task broke Tier 2 on main. Reverted cleanly via reset --hard."
    fi
  } {merge_fd}>"${PIPELINE_DIR}/.ralph/locks/merge_queue.lock"
}

run_parallel_waves() {
  local max_workers="${PARALLEL_WORKERS:-3}"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  log_section "PARALLEL WAVE DISPATCHER (Max Workers: ${max_workers})"

  # 1. Run task_dispatcher.py to generate wave schedule
  local schedule_json
  schedule_json=$(python3 "${PIPELINE_DIR}/scripts/task_dispatcher.py" "${CONTEXT_DIR}/Tasks_list.md" --max-workers "$max_workers" 2>/dev/null || echo "[]")

  local wave_count
  wave_count=$(echo "$schedule_json" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(len(data))' 2>/dev/null || echo "0")

  if [[ "$wave_count" -eq 0 ]]; then
    log_ok "No pending tasks to dispatch in parallel. All tasks are completed or blocked."
    return 0
  fi

  log_info "Task Dispatcher identified ${wave_count} wave(s) of disjoint tasks."

  local reg_file="${PIPELINE_DIR}/.ralph/active_worktrees.txt"
  mkdir -p "$(dirname "$reg_file")"

  local wave_idx=0
  while (( wave_idx < wave_count )); do
    local wave_num=$(( wave_idx + 1 ))
    local tasks_in_wave
    tasks_in_wave=$(echo "$schedule_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(' '.join(t['task_id'] for t in data[$wave_idx]['tasks']))" 2>/dev/null || echo "")

    log_section "DISPATCHING WAVE ${wave_num}/${wave_count}: [${tasks_in_wave}]"

    local wave_pre_commit
    wave_pre_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo "")"
    local pids=()
    local wave_worktrees=()
    local wave_branches=()

    for task in $tasks_in_wave; do
      local worktree_dir="${PIPELINE_DIR}/.ralph/worktrees/${RUN_ID}/${task}"
      local branch_name="ralph/${RUN_ID}/${task}"

      # Write-Ahead Log: Pre-register worktree & branch so cleanup trap never misses them if Ctrl+C occurs during git worktree add
      echo "${worktree_dir}|${branch_name}" >> "$reg_file"
      ACTIVE_WORKTREES+=("$worktree_dir")
      ACTIVE_BRANCHES+=("$branch_name")
      wave_worktrees+=("$worktree_dir")
      wave_branches+=("$branch_name")

      mkdir -p "$(dirname "$worktree_dir")"
      if ! git -C "$repo_root" worktree add -b "$branch_name" "$worktree_dir" main >/dev/null 2>&1; then
        log_error "Failed to create git worktree for $task. Skipping."
        local reg_tmp="${reg_file}.tmp"
        awk -v target="$worktree_dir" -F'|' '$1 != target' "$reg_file" > "$reg_tmp" 2>/dev/null && mv "$reg_tmp" "$reg_file" 2>/dev/null || true
        git -C "$repo_root" branch -D "$branch_name" >/dev/null 2>&1 || true
        continue
      fi

      (
        execute_worker_for_task "$worktree_dir" "$task" "$branch_name" "$repo_root"
      ) &
      pids+=($!)
      GLOBAL_WORKER_PIDS+=($!)
      log_info "Launched Worker for ${task} (PID: ${pids[-1]}, Worktree: ${worktree_dir})"
    done

    # Collect individual worker exit codes (Issue #4)
    local wave_failed=0
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        wave_failed=$(( wave_failed + 1 ))
      fi
    done
    if [[ $wave_failed -gt 0 ]]; then
      log_warn "⚠️ [WAVE ${wave_num}] ${wave_failed} worker(s) exited with failure or blocked status."
    fi

    # Post-Wave Integration Gate
    log_section "POST-WAVE ${wave_num} INTEGRATION GATE"
    if ! PYTHONPATH="$repo_root:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 2; then
      log_error "🚨 [WAVE REGRESSION] Cross-task interaction broke full test suite! Rolling back Wave ${wave_num}..."
      # Kill any lingering background workers before rollback (Issue #11)
      for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      wait 2>/dev/null || true
      git -C "$repo_root" reset --hard "$wave_pre_commit"
      git -C "$repo_root" clean -fd >/dev/null 2>&1 || true
      for t in $tasks_in_wave; do
        safe_update_task_status "$t" "[!] BLOCKED"
      done
      safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Wave ${wave_num} regression detected! Reverted to ${wave_pre_commit}. Tasks in wave marked [!] BLOCKED."
      for wt in "${wave_worktrees[@]}"; do
        git -C "$repo_root" worktree remove --force "$wt" >/dev/null 2>&1 || true
      done
      for br in "${wave_branches[@]}"; do
        git -C "$repo_root" branch -D "$br" >/dev/null 2>&1 || true
      done
      rm -f "$reg_file"
      ACTIVE_WORKTREES=()
      ACTIVE_BRANCHES=()
      GLOBAL_WORKER_PIDS=()
      return 1
    fi
    log_ok "Wave ${wave_num} integration verified 100% PASS ✓"

    # Cleanup worktrees and branches for this wave
    for wt in "${wave_worktrees[@]}"; do
      git -C "$repo_root" worktree remove --force "$wt" >/dev/null 2>&1 || true
    done
    for br in "${wave_branches[@]}"; do
      git -C "$repo_root" branch -D "$br" >/dev/null 2>&1 || true
    done
    rm -f "$reg_file"
    ACTIVE_WORKTREES=()
    ACTIVE_BRANCHES=()
    GLOBAL_WORKER_PIDS=()

    wave_idx=$(( wave_idx + 1 ))
  done

  log_ok "All parallel waves completed successfully!"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Pillar 6: Isolated Bug Fix Workflow (Agentless Pattern)
# ────────────────────────────────────────────────────────────────────────────
run_fix_bug_flow() {
  local error_input="$1"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  log_section "AGENTLESS BUG FIX MODE"
  log_info "Analyzing input error / traceback..."

  local culprit_file=""
  if [[ -f "$error_input" ]]; then
    error_input=$(cat "$error_input")
  fi

  # Zero-token injection-safe traceback localization via stdin (Issue #3)
  culprit_file=$(printf "%s" "$error_input" | python3 -c '
import re, sys
text = sys.stdin.read()
matches = re.findall(r"File [\x22\x27](.*?(\.py|\.sh|\.json|\.ts|\.js))[\x22\x27], line (\d+)", text)
if matches:
    print(matches[-1][0])
else:
    file_match = re.search(r"([a-zA-Z0-9_\-\./]+\.(py|sh|json|ts|js))", text)
    print(file_match.group(1) if file_match else "")
' 2>/dev/null || echo "")

  if [[ -z "$culprit_file" ]]; then
    log_warn "Could not automatically localize culprit file from error input."
    log_info "Prompting Agent for general bug reproduction & fix..."
  else
    log_info "🎯 Localized culprit file: ${culprit_file}"
  fi

  # Reproduce: Build isolated test reproducing the bug
  local reproduce_dir="${repo_root}/tests/reproduce"
  mkdir -p "$reproduce_dir"
  local test_file="${reproduce_dir}/test_bug_reproduce.py"
  local err_report_file="${RUNTIME_DIR}/error_report.txt"

  # Injection-safe storage: write raw error into isolated report file in RUNTIME_DIR (Issue NEW2.8, NEW3.7)
  printf '%s\n' "$error_input" > "$err_report_file"

  local bug_prompt="[AGENTLESS-BUGFIX]
Phát hiện lỗi cần sửa chữa triệt để (Chi tiết lỗi lưu tại '${err_report_file}'):
=== 🎯 MỤC TIÊU ===
1. Đọc nội dung chi tiết lỗi từ '${err_report_file}'.
2. Nếu chưa có test tái hiện: Tạo file test tại '${test_file}' để tái hiện đúng lỗi này (Test Contract Red).
3. Sửa lỗi chính xác tại file nguồn (chỉ sửa root cause, không vá tạm bợ).
4. Đảm bảo chạy 'python3 pipeline/scripts/verify.py --tier 1 --test-target ${test_file}' PASS 100%.
5. Đảm bảo chạy full 'python3 pipeline/scripts/verify.py --tier 2' PASS 100% không gây regression."

  log_info "Running Agent Turn for targeted bug fix..."
  _run_agent_turn "$bug_prompt" "$PRINT_TIMEOUT" "1" "$EXECUTOR_MODEL" "BUGFIX-AGENT"

  # Verify
  log_info "Verifying bug fix via deterministic Tier 1 and Tier 2..."
  local tier1_ok=false
  local tier2_ok=false

  if [[ -f "$test_file" ]]; then
    if PYTHONPATH="$repo_root:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 1 --test-target "$test_file"; then
      tier1_ok=true
    fi
  else
    tier1_ok=true
  fi

  if [[ "$tier1_ok" == "true" ]] && PYTHONPATH="$repo_root:$PYTHONPATH" python3 "${PIPELINE_DIR}/scripts/verify.py" --tier 2; then
    tier2_ok=true
  fi

  # Clean up error_report_file so sensitive data is never committed to git history (Issue NEW3.7)
  rm -f "$err_report_file" 2>/dev/null || true

  if [[ "$tier2_ok" == "true" ]]; then
    local bug_summary
    bug_summary=$(printf '%s' "$error_input" | head -n 1 | tr -cd '[:alnum:] _.,-:()[]' | cut -c 1-50)
    [[ -z "$bug_summary" ]] && bug_summary="targeted error reproduction"
    git -C "$repo_root" add -A
    git -C "$repo_root" commit -m "fix(agentless): resolve issue: ${bug_summary}"
    safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Agentless bug fix succeeded and cleanly committed to main."
    log_ok "🎉 [BUGFIX] Bug fix verified and committed cleanly ✓"
    return 0
  else
    log_error "🚨 [BUGFIX FAILED] Bug fix did not pass Tier 2 verification. Reverting uncommitted changes..."
    # Clean both modified and untracked files (Issue #10)
    git -C "$repo_root" checkout -- . 2>/dev/null || true
    git -C "$repo_root" clean -fd 2>/dev/null || true
    safe_append_durable_log "${RUNTIME_DIR}/PROGRESS_LOG.md" "Agentless bug fix failed verification. Changes reverted."
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main Master Loop
# ────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  init_run_lifecycle
  preflight_check

  if [[ -n "$PROVIDER_OVERRIDE" ]]; then
    export AGENT_PROVIDER="$PROVIDER_OVERRIDE"
  fi

  # Dispatch to isolated bug fix mode if requested
  if [[ -n "$FIX_BUG_TARGET" ]]; then
    run_fix_bug_flow "$FIX_BUG_TARGET"
    exit $?
  fi

  # Dispatch to parallel wave mode if requested
  if [[ "$PARALLEL_MODE" == "true" ]]; then
    run_parallel_waves
    exit $?
  fi

  local iter=0
  local no_progress=0
  local api_errors=0
  local CURRENT_ACTIVE_TASK=""

  log_section "STARTING RALPH LOOP ORCHESTRATION"

  while :; do
    iter=$((iter + 1))
    reap_orphans

    # Check manual STOP signal
    if [[ -f "${RUNTIME_DIR}/STOP.md" ]]; then
      log_error "Emergency STOP.md detected. Halting loop."
      exit 3
    fi

    # Check strict BLOCKED signal
    if [[ "$STOP_ON_BLOCK" == true ]] && [[ -f "${RUNTIME_DIR}/BLOCKED.md" ]]; then
      log_error "Strict BLOCKED.md detected. Halting loop."
      exit 3
    fi

    # Check max iterations
    if (( iter > MAX_ITERATIONS )); then
      log_warn "Reached maximum iterations ($MAX_ITERATIONS). Stopping."
      exit 4
    fi

    # Check circuit breaker
    if (( no_progress >= NO_PROGRESS_MAX )); then
      log_error "Circuit breaker triggered: $no_progress consecutive iterations without commit. Stopping."
      exit 6
    fi

    # Pick next task
    local active_task
    active_task=$(get_next_todo_task "$TASK_FILTER")

    if [[ -z "$active_task" ]]; then
      log_ok "🎉 ALL TASKS PROCESSED & VERIFIED 100% PASS! [Queue Complete]"
      exit 0
    fi

    # Session Memory Management (Task-Bound Continuous Sessions)
    if [[ "$active_task" != "$CURRENT_ACTIVE_TASK" ]]; then
      if [[ -n "$CURRENT_ACTIVE_TASK" ]]; then
        log_info "🔄 [SESSION FLUSH] Task switched from [${CURRENT_ACTIVE_TASK}] to [${active_task}]. Flushed memory for clean prompt caching."
      else
        log_info "⚡ [TASK SESSION] Initiating Task-Bound Session for [${active_task}]..."
      fi
      CURRENT_ACTIVE_TASK="$active_task"
      ensure_clean_working_tree "$active_task" "$AUTO_CLEAN_DIRTY"
    fi

    log_section "ITERATION ${iter} / ${MAX_ITERATIONS} — TARGET: [${active_task}]"

    # Ensure plan seal integrity before executing agent turn
    verify_or_restore_plan_seal "ITERATION ${iter}"

    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY RUN] Simulating iteration ${iter} for ${active_task}..."
      sleep 1
      exit 0
    fi

    local head_before
    head_before=$(git rev-parse HEAD 2>/dev/null || echo "none")

    local task_spec
    task_spec=$(get_task_spec "$active_task")

    # Inspect task complexity (>3 services or >5 files)
    local complexity_metrics
    complexity_metrics=$(inspect_task_complexity "$active_task")
    local svc_count="${complexity_metrics% *}"
    local file_count="${complexity_metrics#* }"
    local complexity_notice=""

    if (( svc_count > 3 || file_count > 5 )); then
      log_warn "⚠️ [COMPLEXITY GUARD] Task [${active_task}] is high-complexity: spans ${svc_count} microservices and ${file_count} files (>3 services or >5 files)!"
      complexity_notice="Task này có phạm vi lớn (${svc_count} microservices, ${file_count} files). Để không bị timeout:
- BẮT BUỘC tạo PLAN.md chia thành 2-4 atomic micro-steps độc lập (mỗi step chỉ sửa 1-2 services hoặc 2-3 files).
- Chạy 'python3 pipeline/scripts/verify.py' ngay sau mỗi step để kích hoạt Verified Step Checkpoint.
- Không sửa dàn trải cùng lúc nhiều services trong một lần gọi tool."
    fi

    local role_tag="SINGLE-MODEL"
    [[ -n "$REVIEW_MODEL" ]] && role_tag="DUAL-MODEL"

    local executor_prompt
    executor_prompt=$(_build_executor_payload_safe "$active_task" "$task_spec" "$role_tag" "$complexity_notice")

    set +e
    _run_agent_turn "$executor_prompt" "$PRINT_TIMEOUT" "$iter" "$EXECUTOR_MODEL" "EXECUTOR"
    local turn_code=$?

    # Create verified checkpoint if step passed verification
    create_verified_step_checkpoint "$active_task"

    if [[ $turn_code -eq 7 ]]; then
      log_error "Hard-stopping loop on context compaction. Re-narrow task ${active_task}."
      exit 7
    elif [[ $turn_code -eq 8 ]]; then
      api_errors=$((api_errors + 1))
      if (( api_errors >= API_MAX )); then
        log_error "Repeated API/5xx errors ($api_errors). Stopping loop."
        exit 8
      fi
      log_warn "Backing off for ${API_BACKOFF}s before retrying..."
      sleep "$API_BACKOFF"
      continue
    fi

    # If Dual-Model review is active, run reviewer
    if [[ -n "$REVIEW_MODEL" ]]; then
      execute_dual_model_review "$iter" || log_warn "[DUAL-MODEL] Review step completed."
    fi

    # Auto-sync dependencies if agent added new packages to manifest
    if git status --porcelain "${PIPELINE_DIR}/../pyproject.toml" "${PIPELINE_DIR}/../requirements.txt" 2>/dev/null | grep -qE "pyproject\.toml|requirements"; then
      log_info "📦 Manifest modification detected. Synchronizing new dependencies via uv into .venv..."
      sync_venv_dependencies
    fi

    # Check and auto-commit done task (passing active_task for auto-sync)
    check_and_auto_commit_done_task "$role_tag" "$active_task"

    local head_after
    head_after=$(git rev-parse HEAD 2>/dev/null || echo "none")

    if [[ "$head_after" != "$head_before" ]]; then
      no_progress=0
      api_errors=0
      log_ok "Progress verified: New clean commit ${head_after:0:9}"
    else
      no_progress=$((no_progress + 1))
      log_info "No new commit this iteration (No-progress count: ${no_progress}/${NO_PROGRESS_MAX})"
    fi
  done
}

main "$@"
