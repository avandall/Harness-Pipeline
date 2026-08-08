#!/usr/bin/env bash
# =============================================================================
# harness.sh — Ralph Loop Execution Script
# Chạy AI agent trong một vòng lặp tự trị với đầy đủ guardrails
#
# Cách dùng:
#   ./harness.sh                               # Chạy với defaults (single-model)
#   ./harness.sh --max-iter 20                 # Giới hạn 20 iterations
#   ./harness.sh --task "TASK-001"             # Chỉ định task ID
#   ./harness.sh --dry-run                     # Simulate, không thực thi thực sự
#   ./harness.sh --review-model gemini-3.6-flash-low  # Bật Dual-Model mode
# =============================================================================

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────
DOCS_DIR="./H_docs"
RUNTIME_DIR="${DOCS_DIR}/runtime"
CONTEXT_DIR="${DOCS_DIR}/context"
CORE_DIR="${DOCS_DIR}/core"
ITERATIONS_DIR="${RUNTIME_DIR}/ITERATIONS"
BLOCKERS_DIR="${RUNTIME_DIR}/BLOCKERS"

MAX_ITERATIONS=30
CONTEXT_REFRESH_EVERY=5
TASK_ID=""
PRINT_TIMEOUT="15m0s"
DRY_RUN=false
VERBOSE=false
STOP_ON_BLOCK=false

# Dual-Model Review Mode
# Set REVIEW_MODEL to enable: executor writes code, reviewer (different model) checks logic
# Default empty = single-model mode (backward compatible)
REVIEW_MODEL=""
REVIEW_TIMEOUT="5m0s"   # Reviewer is faster — only reads git diff + checklist
REVIEW_MAX_RETRIES=2    # Max re-execute cycles per iteration when reviewer rejects

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ────────────────────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --max-iter|-n)
        MAX_ITERATIONS="$2"
        shift 2
        ;;
      --task|-t)
        TASK_ID="$2"
        shift 2
        ;;
      --timeout)
        PRINT_TIMEOUT="$2"
        shift 2
        ;;
      --review-model|-r)
        REVIEW_MODEL="$2"
        shift 2
        ;;
      --review-timeout)
        REVIEW_TIMEOUT="$2"
        shift 2
        ;;
      --stop-on-block)
        STOP_ON_BLOCK=true
        shift
        ;;
      --dry-run|-d)
        DRY_RUN=true
        shift
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

show_help() {
  cat <<EOF
${BOLD}harness.sh${NC} — Ralph Loop Execution Script (Overnight Non-Blocking Mode)

${BOLD}USAGE:${NC}
  ./harness.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  --max-iter, -n N        Maximum number of iterations (default: 30)
  --task, -t ID           Task ID to run (default: reads from Tasks_list.md)
  --timeout TIME          Timeout for AI executor process e.g. 10m0s, 15m0s (default: 15m0s)
  --review-model, -r M    Enable Dual-Model mode: use model M for Tier 2 Cognitive Review.
                          M must be a valid agy model name (run: agy models).
                          Example: --review-model gemini-3.6-flash-low
                          When not set: single-model mode (backward compatible).
  --review-timeout TIME   Timeout for reviewer agy call (default: 5m0s)
  --stop-on-block         Stop harness immediately if any task is blocked (default: false / Overnight Mode)
  --dry-run, -d           Simulate without executing
  --verbose, -v           Verbose output
  --help, -h              Show this help

${BOLD}DUAL-MODEL MODE:${NC}
  When --review-model is set, each iteration runs two agy calls:
    1. EXECUTOR (default model)  — ORIENT → EXECUTE → VERIFY (runs verify.py)
    2. REVIEWER (--review-model) — PHASE 5 Cognitive Review on git diff
  If REVIEWER rejects, EXECUTOR gets feedback from DEBATE_LOG.md and retries
  (max ${REVIEW_MAX_RETRIES:-2} times per iteration).

${BOLD}EXAMPLES:${NC}
  ./harness.sh                                  # Single-model mode (classic)
  ./harness.sh --review-model gemini-3.6-flash-low  # Dual-model review
  ./harness.sh --timeout 20m0s                  # Increase timeout to 20 minutes
  ./harness.sh --max-iter 50                    # Limit to 50 iterations
  ./harness.sh --stop-on-block                  # Strict mode: stop on first blocker

${BOLD}DOCS:${NC}
  See H_docs/core/HARNESS_PROTOCOL.md for full documentation.
EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Logging helpers
# ────────────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

# ────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ────────────────────────────────────────────────────────────────────────────
preflight_check() {
  log_section "PRE-FLIGHT CHECK"
  
  local errors=0

  # Check docs structure
  for dir in "$DOCS_DIR" "$RUNTIME_DIR" "$CONTEXT_DIR" "$CORE_DIR"; do
    if [[ -d "$dir" ]]; then
      log_ok "Directory exists: $dir"
    else
      log_error "Missing directory: $dir"
      ((errors++))
    fi
  done

  # Check required context files
  for file in \
    "${CONTEXT_DIR}/PROJECT_BRIEF.md" \
    "${CONTEXT_DIR}/Tasks_list.md" \
    "${CONTEXT_DIR}/BOUNDARIES.md"; do
    if [[ -f "$file" ]]; then
      log_ok "Context file exists: $file"
    else
      log_error "Missing context file: $file (fill this in before running)"
      ((errors++))
    fi
  done

  # Check git is initialized
  if git rev-parse --git-dir > /dev/null 2>&1; then
    log_ok "Git repository initialized"
  else
    log_error "Not a git repository. Run 'git init' first."
    ((errors++))
  fi

  # Check for uncommitted changes
  if [[ -n "$(git status --porcelain)" ]]; then
    log_warn "Uncommitted changes detected. Consider committing before starting."
  fi

  # Check verify.py script exists
  if [[ -f "${DOCS_DIR}/scripts/verify.py" ]]; then
    log_ok "Verification script exists: ${DOCS_DIR}/scripts/verify.py"
  else
    log_warn "Missing ${DOCS_DIR}/scripts/verify.py — verification script recommended"
  fi

  # Check python3 is available
  if command -v python3 >/dev/null 2>&1; then
    log_ok "Python3 environment available for verification"
  else
    log_warn "Python3 not found in PATH — verify.py requires python3"
  fi

  # Check STOP.md emergency signal
  if [[ -f "${RUNTIME_DIR}/STOP.md" ]]; then
    log_error "STOP.md exists! Execution halted by user emergency signal."
    log_error "Remove ${RUNTIME_DIR}/STOP.md to resume."
    ((errors++))
  fi

  if [[ $errors -gt 0 ]]; then
    log_error "Pre-flight failed with $errors error(s). Fix before running."
    exit 1
  fi

  log_ok "All pre-flight checks passed ✓ (Overnight Non-Blocking Mode Active)"
}

# ────────────────────────────────────────────────────────────────────────────
# Initialize runtime docs if not exist
# ────────────────────────────────────────────────────────────────────────────
init_runtime() {
  log_section "INITIALIZING RUNTIME"

  mkdir -p "$ITERATIONS_DIR" "$BLOCKERS_DIR"

  # Initialize STATUS.md if not exists
  if [[ ! -f "${RUNTIME_DIR}/STATUS.md" ]]; then
    log_info "Creating STATUS.md..."
    cat > "${RUNTIME_DIR}/STATUS.md" << EOF
# STATUS
Task: ${TASK_ID:-Auto-select from Tasks_list.md}
Phase: INIT
Iteration: 0 / ${MAX_ITERATIONS}
Last Updated: $(date '+%Y-%m-%d %H:%M')

Next Action: AI reads context docs and picks first [ ] TODO task in Tasks_list.md
EOF
    log_ok "STATUS.md initialized"
  fi

  # Initialize PROGRESS_LOG.md if not exists
  if [[ ! -f "${RUNTIME_DIR}/PROGRESS_LOG.md" ]]; then
    log_info "Creating PROGRESS_LOG.md..."
    echo "# PROGRESS LOG" > "${RUNTIME_DIR}/PROGRESS_LOG.md"
    echo "Started: $(date '+%Y-%m-%d %H:%M')" >> "${RUNTIME_DIR}/PROGRESS_LOG.md"
    log_ok "PROGRESS_LOG.md initialized"
  fi

  log_ok "Runtime initialized (BLOCKERS directory ready at ${BLOCKERS_DIR})"
}

# ────────────────────────────────────────────────────────────────────────────
# Check exit conditions
# ────────────────────────────────────────────────────────────────────────────
check_exit_condition() {
  local iter="$1"

  # Check manual STOP signal
  if [[ -f "${RUNTIME_DIR}/STOP.md" ]]; then
    echo "EXIT_MANUAL_STOP"
    return
  fi

  # Check if strict mode stop-on-block is active and a root BLOCKED.md exists
  if [[ "$STOP_ON_BLOCK" == true ]] && [[ -f "${RUNTIME_DIR}/BLOCKED.md" ]]; then
    echo "EXIT_BLOCKED"
    return
  fi

  # Check if all tasks in Tasks_list.md are finished (no [ ] TODO or [/] IN_PROGRESS left)
  if [[ -f "${CONTEXT_DIR}/Tasks_list.md" ]]; then
    local remaining_todo
    remaining_todo=$(grep -c "\[ \] TODO" "${CONTEXT_DIR}/Tasks_list.md" || true)
    local remaining_in_progress
    remaining_in_progress=$(grep -c "\[/\] IN_PROGRESS" "${CONTEXT_DIR}/Tasks_list.md" || true)

    if [[ "$remaining_todo" -eq 0 ]] && [[ "$remaining_in_progress" -eq 0 ]]; then
      echo "EXIT_ALL_TASKS_PROCESSED"
      return
    fi
  fi

  # Check DONE signal in STATUS.md (Chỉ kích hoạt EXIT_DONE khi Phase: ALL_DONE)
  if [[ -f "${RUNTIME_DIR}/STATUS.md" ]]; then
    if grep -qE "^Phase:\s*ALL_DONE\s*$" "${RUNTIME_DIR}/STATUS.md" 2>/dev/null; then
      echo "EXIT_DONE"
      return
    fi
  fi

  # Check max iterations
  if [[ $iter -ge $MAX_ITERATIONS ]]; then
    echo "EXIT_MAX_ITER"
    return
  fi

  echo "EXIT_CONTINUE"
}

# ────────────────────────────────────────────────────────────────────────────
# Create iteration snapshot
# ────────────────────────────────────────────────────────────────────────────
create_iteration_snapshot() {
  local iter="$1"
  local result="$2"
  local iter_file="${ITERATIONS_DIR}/iter_$(printf '%03d' $iter).md"

  cat > "$iter_file" << EOF
# Iteration $(printf '%03d' $iter)
- Date: $(date '+%Y-%m-%d %H:%M')
- Result: ${result}
- Git: $(git log --oneline -1 2>/dev/null || echo "no commits yet")
EOF

  if [[ "$VERBOSE" == true ]]; then
    log_info "Snapshot saved: $iter_file"
  fi
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Git commit checkpoint
# ────────────────────────────────────────────────────────────────────────────
checkpoint_commit() {
  local iter="$1"
  local message="$2"

  if $DRY_RUN; then
    log_info "[DRY RUN] Would commit: [iter-${iter}] ${message}"
    return
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "[iter-${iter}] ${message}" || true
    log_ok "Committed: [iter-${iter}] ${message}"
  else
    log_info "No changes to commit at iter-${iter}"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Execute one iteration (hook point for actual AI execution)
# ────────────────────────────────────────────────────────────────────────────
execute_iteration() {
  local iter="$1"

  log_section "ITERATION ${iter} / ${MAX_ITERATIONS}"

  # Context refresh trigger
  if (( iter % CONTEXT_REFRESH_EVERY == 0 && iter > 0 )); then
    log_warn "Context refresh point (iter ${iter}). AI should re-read context docs."
  fi

  if $DRY_RUN; then
    log_info "[DRY RUN] Simulating iteration ${iter}..."
    sleep 1
    return 0
  fi

  # ─── AUTOMATED AGY CLI EXECUTION ─────────────────────────────────────────
  local iter_prompt="Đọc H_docs/core/AGENT_CONSTITUTION.md, H_docs/context/Tasks_list.md và H_docs/runtime/STATUS.md. Tìm task đầu tiên có trạng thái [ ] TODO hoặc [/] IN_PROGRESS trong Tasks_list.md. Đọc H_docs/runtime/PLAN.md (nếu chưa có plan cho task này thì tạo PLAN.md). Thực hiện 1 bước atomic tiếp theo trong task đó theo quy trình Harness Protocol. Ở Phase 4 (VERIFY), BẮT BUỘC chạy 'python3 H_docs/scripts/verify.py' để kiểm định Tier 1 (Linter/Type/Security/Test) và kiểm tra H_docs/runtime/VERIFICATION_REPORT.md. NẾU VERIFICATION_REPORT có lỗi, hãy đọc log ngắn gọn trong đó để sửa ngay. Ở Phase 5 (REVIEW), thực hiện Tier 2 Cognitive Review dựa trên git diff và H_docs/core/REVIEW_PROTOCOL.md. Cập nhật H_docs/runtime/STATUS.md, H_docs/runtime/PROGRESS_LOG.md và tự thực hiện atomic git commits nhỏ. NẾU GẶP BLOCKER mà không thể tự giải quyết: 1) Viết báo cáo chi tiết vào file H_docs/runtime/BLOCKERS/<TASK_ID>.md. 2) Cập nhật dòng của task đó trong H_docs/context/Tasks_list.md thành [!] BLOCKED. 3) Cập nhật STATUS.md để chuyển sang task TODO tiếp theo. KHÔNG TẠO file BLOCKED.md ở root ngoại trừ khi khẩn cấp. LƯU Ý QUAN TRỌNG: Chỉ được phép ghi 'Phase: ALL_DONE' vào H_docs/runtime/STATUS.md KHI VÀ CHỈ KHI TẤT CẢ các tasks trong Tasks_list.md đã được thực hiện, phản biện, xác minh pass 100% và đánh dấu [x] DONE (hoặc [!] BLOCKED). Khi đó mới cập nhật STATUS.md thành Phase: ALL_DONE và viết H_docs/runtime/PROOF_OF_SOLUTION.md. Nếu dự án còn task chưa hoàn thành, giữ Phase: IN_PROGRESS."

  log_info "Launching agy CLI process for Iteration ${iter}..."

  local max_retries=3
  local attempt=1
  local success=false

  while (( attempt <= max_retries )); do
    if agy -p "$iter_prompt" --dangerously-skip-permissions --print-timeout "$PRINT_TIMEOUT"; then
      log_ok "agy CLI process finished Iteration ${iter} successfully."
      success=true
      break
    else
      log_warn "agy CLI process attempt ${attempt}/${max_retries} failed or timed out."
      if (( attempt < max_retries )); then
        log_info "Waiting 5 seconds before retrying..."
        sleep 5
      fi
      ((attempt++))
    fi
  done

  if [[ "$success" == true ]]; then
    return 0
  else
    log_error "agy CLI process failed after ${max_retries} attempts on Iteration ${iter}."
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main Loop — The Ralph Loop
# ────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ██╗  ██╗ █████╗ ██████╗ ███╗   ██╗███████╗███████╗███████╗"
  echo "  ██║  ██║██╔══██╗██╔══██╗████╗  ██║██╔════╝██╔════╝██╔════╝"
  echo "  ███████║███████║██████╔╝██╔██╗ ██║█████╗  ███████╗███████╗"
  echo "  ██╔══██║██╔══██║██╔══██╗██║╚██╗██║██╔══╝  ╚════██║╚════██║"
  echo "  ██║  ██║██║  ██║██║  ██║██║ ╚████║███████╗███████║███████║"
  echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝"
  echo "                     Harness Engineering — Ralph Loop"
  echo "                     (Overnight Non-Blocking Mode)"
  echo -e "${NC}"

  log_info "Task Strategy: Auto-queue from Tasks_list.md"
  log_info "Max iterations: ${MAX_ITERATIONS}"
  log_info "Context refresh: every ${CONTEXT_REFRESH_EVERY} iterations"
  log_info "Overnight Mode: ACTIVE (Blocked tasks will be bypassed)"
  if [[ -n "$REVIEW_MODEL" ]]; then
    log_info "Review Mode: DUAL-MODEL — Reviewer=${REVIEW_MODEL} (max ${REVIEW_MAX_RETRIES} retries/iter)"
  else
    log_info "Review Mode: SINGLE-MODEL (self-review by executor)"
  fi
  if $DRY_RUN; then
    log_warn "DRY RUN MODE — no real changes will be made"
  fi
  echo ""

  preflight_check
  init_runtime

  local iter=1
  local start_time
  start_time=$(date +%s)

  # ─── THE RALPH LOOP ───────────────────────────────────────────────────────
  while true; do
    # Execute one iteration
    if ! execute_iteration "$iter"; then
      log_warn "Iteration ${iter} execution failed or was interrupted"
      break
    fi

    # Check exit condition
    local exit_code
    exit_code=$(check_exit_condition "$iter")

    case "$exit_code" in
      EXIT_ALL_TASKS_PROCESSED|EXIT_DONE)
        log_section "✅ ALL QUEUED TASKS PROCESSED"
        create_iteration_snapshot "$iter" "DONE"
        checkpoint_commit "$iter" "chore: overnight queue complete — update runtime docs"
        
        local duration=$(( $(date +%s) - start_time ))
        local done_count
        done_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[x\]" || true)
        local blocked_count
        blocked_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[!\]" || true)

        log_ok "Completed loop in ${iter} iterations ($(( duration / 60 ))m $(( duration % 60 ))s)"
        log_ok "Tasks Completed ([x] DONE): ${done_count}"
        log_warn "Tasks Blocked   ([!] BLOCKED): ${blocked_count} (See ${BLOCKERS_DIR}/ for reports)"
        log_ok "See H_docs/runtime/PROOF_OF_SOLUTION.md for verification"
        break
        ;;

      EXIT_BLOCKED)
        log_section "🛑 BLOCKED (Strict Mode)"
        create_iteration_snapshot "$iter" "BLOCKED"
        log_error "AI has created BLOCKED.md and requires human input (Strict Mode active)"
        exit 1
        ;;

      EXIT_MANUAL_STOP)
        log_section "🛑 MANUAL STOP SIGNAL DETECTED"
        log_warn "STOP.md detected in ${RUNTIME_DIR}/. Stopping loop safely."
        break
        ;;

      EXIT_MAX_ITER)
        log_section "⚠️ MAX ITERATIONS REACHED"
        create_iteration_snapshot "$iter" "MAX_ITER"
        checkpoint_commit "$iter" "chore: max iterations reached — partial progress"
        log_warn "Reached maximum iterations (${MAX_ITERATIONS})"
        log_warn "Review H_docs/runtime/PROGRESS_LOG.md for current state"
        log_warn "Increase --max-iter or review Tasks_list.md to continue"
        exit 2
        ;;

      EXIT_CONTINUE)
        create_iteration_snapshot "$iter" "CONTINUE"
        checkpoint_commit "$iter" "chore: iter-${iter} complete — continue"
        log_info "Iteration ${iter} complete. Continuing..."
        iter=$((iter + 1))
        ;;
    esac
  done
  # ─────────────────────────────────────────────────────────────────────────
}

main "$@"

