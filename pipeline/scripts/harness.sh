#!/usr/bin/env bash
# =============================================================================
# harness.sh — Ralph Loop Execution Script
# Chạy AI agent trong một vòng lặp tự trị với đầy đủ guardrails
#
# Cách dùng:
#   ./pipeline/scripts/harness.sh                               # Chạy với defaults (single-model)
#   ./pipeline/scripts/harness.sh --max-iter 20                 # Giới hạn 20 iterations
#   ./pipeline/scripts/harness.sh --task "TASK-001"             # Chỉ định task ID
#   ./pipeline/scripts/harness.sh --dry-run                     # Simulate, không thực thi thực sự
#   ./pipeline/scripts/harness.sh --review-model gemini-3.7-flash-low  # Bật Dual-Model mode
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -d "${SCRIPT_DIR}/../docs/core" ]]; then

  DOCS_DIR="$(cd "${SCRIPT_DIR}/../docs" && pwd)"
elif [[ -d "./pipeline/docs/core" ]]; then
  DOCS_DIR="./pipeline/docs"
else
  DOCS_DIR="./pipeline/docs"
fi
RUNTIME_DIR="${DOCS_DIR}/runtime"
CONTEXT_DIR="${DOCS_DIR}/context"
CORE_DIR="${DOCS_DIR}/core"
ITERATIONS_DIR="${RUNTIME_DIR}/ITERATIONS"
BLOCKERS_DIR="${RUNTIME_DIR}/BLOCKERS"

MAX_ITERATIONS=30
CONTEXT_REFRESH_EVERY=5
TASK_ID=""
TASK_FILTER=""
PRINT_TIMEOUT="15m0s"
DRY_RUN=false
VERBOSE=false
STOP_ON_BLOCK=false


# Dual-Model Review Mode
# Set REVIEW_MODEL to enable: executor writes code, reviewer (different model) checks logic
# Default empty = single-model mode (backward compatible)
REVIEW_MODEL=""
REVIEW_TIMEOUT="3m0s"   # Reviewer is faster — only reads git diff + checklist
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
# Task Filter & Pruning Helpers
# ────────────────────────────────────────────────────────────────────────────
is_task_in_filter() {
  local tid="$1"       # e.g. "TASK-003" or "TASK-3"
  local filter="$2"    # e.g. "1..5,6,9" or "TASK-001..TASK-005"

  if [[ -z "$filter" ]]; then
    return 0  # No filter active -> all tasks allowed
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
    task_id=$(echo "$line" | grep -oE '`TASK-[0-9]+`|TASK-[0-9]+' | tr -d '`' | head -1 || true)
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

  mkdir -p "${RUNTIME_DIR}"
  cat > "$current_task_file" <<EOF
# CURRENT TASK
# Task hiện tại đang thực thi — Context cho AI agent

> **Trạng thái:** RUNTIME (Auto-Generated / Synced by harness.sh) | **Cập nhật:** $(date '+%Y-%m-%d %H:%M')
>
> 🤖 **AUTO-GENERATED BY HARNESS.** File này được \`harness.sh\` tự động trích xuất từ \`pipeline/docs/context/Tasks_list.md\` để lưu giữ trạng thái task đang active ra filesystem.

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

_build_executor_payload() {
  local active_task="$1"
  local task_spec="$2"
  local role_tag="${3:-SINGLE-MODEL}"
  local tech_summary
  tech_summary=$(get_tech_context_summary)
  local bound_summary
  bound_summary=$(get_boundaries_summary)

  # Đồng bộ ra filesystem để đảm bảo nguyên tắc Filesystem is Memory
  sync_current_task_doc "$active_task" "$task_spec"

  cat <<EOF
[${role_tag} — TASK-BOUND SESSION — TARGET: ${active_task}]

=== 📜 10 ĐIỀU LUẬT CỐT LÕI (INLINE CONSTITUTION) ===
1. State on disk (STATUS.md/PLAN.md). 2. Atomic steps. 3. Verify pass before done (python3 pipeline/scripts/verify.py). 4. Proof over promise. 5. Inspect file before edit. 6. Scope boundary. 7. 1 Task = 1 Commit ([x] DONE). 8. Overnight Non-blocking BLOCKED.

=== 🎯 THÔNG TIN TASK SPEC (TRÍCH XUẤT TỪ Tasks_list.md) ===
${task_spec}

=== 🛡️ GIỚI HẠN & TECH STACK (JIT CONTEXT) ===
- Tech Context: ${tech_summary}
- Scope Boundaries: ${bound_summary}

=== 🚀 NHIỆM VỤ THỰC THI CHO ${active_task} ===
Thực thi trọn vẹn Task ${active_task} trong phiên làm việc này:
1. Đọc/Tạo pipeline/docs/runtime/PLAN.md cho ${active_task} (chia thành 2-4 atomic steps). Nếu tiếp tục task dở dang, đọc PLAN.md và VERIFICATION_REPORT.md để resume.
2. Thực thi tuần tự từng bước: Sửa code trong scope ──► Chạy 'python3 pipeline/scripts/verify.py'.
3. Sửa ngay nếu VERIFICATION_REPORT báo lỗi cho đến khi PASS 100%.
4. Cập nhật tiến độ liên tục vào STATUS.md, PROGRESS_LOG.md và PLAN.md ra filesystem.
5. Khi ${active_task} đã xong 100% và verify PASS: Đánh dấu [x] DONE dòng ${active_task} trong Tasks_list.md và DỪNG PHIÊN (Harness sẽ tự động commit git).

⚠️ KHÔNG COMMIT TRUNG GIAN.
NẾU BỊ KẸT (sửa 2 lần không qua verify.py): Dừng lại, viết report vào BLOCKERS/${active_task}.md và đổi task thành [!] BLOCKED.
EOF
}

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
      --tasks|--task|-t)
        TASK_FILTER="$2"
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
  ./pipeline/docs/harness.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  --max-iter, -n N        Maximum number of iterations (default: 30)
  --task, -t ID           Task ID to run (default: reads from Tasks_list.md)
  --timeout TIME          Timeout for AI executor process e.g. 10m0s, 15m0s (default: 15m0s)
  --review-model, -r M    Enable Dual-Model mode: use model M for Tier 2 Cognitive Review.
                          M must be a valid agy model name (run: agy models).
                          Example: --review-model gemini-3.6-flash-low
                          IMPORTANT: You MUST specify a model name explicitly.
                          No default model is assumed — omitting -r uses single-model mode.
  --review-timeout TIME   Timeout for reviewer agy call (default: 5m0s)
  --stop-on-block         Stop harness immediately if any task is blocked (default: false / Overnight Mode)
  --dry-run, -d           Simulate without executing
  --verbose, -v           Verbose output
  --help, -h              Show this help

${BOLD}DUAL-MODEL MODE:${NC}
  When --review-model is set, each iteration runs two agy calls:
    1. EXECUTOR (default model)  — ORIENT → PLAN → EXECUTE → VERIFY (runs verify.py)
                                   Stops before Phase 5 (Review). Phase 6-7 (Commit/Report)
                                   run AFTER reviewer approves.
    2. REVIEWER (--review-model) — Phase 5 Cognitive Review using git diff + verify.py summary.
                                   Reads prompt from pipeline/docs/core/REVIEWER_PROMPT_TEMPLATE.md.
                                   Output: 'Review Result: APPROVED' or 'Review Result: REJECTED: <reason>'
  If REVIEWER rejects:
    - EXECUTOR reads DEBATE_LOG.md, fixes issues, re-runs verify.py, then REVIEWER checks again.
    - Max ${REVIEW_MAX_RETRIES:-2} retry cycles per iteration.
  If REVIEWER rejects after max retries:
    - Task is marked [!] BLOCKED (same as Overnight Non-Blocking blocker behavior).
    - Harness continues to next TODO task automatically.
  The reviewer call is a FRESH agy conversation (separate context, same CLI quota).

${BOLD}EXAMPLES:${NC}
  ./pipeline/docs/harness.sh                                  # Single-model mode (classic)
  ./pipeline/docs/harness.sh --review-model gemini-3.6-flash-low  # Dual-model: cheap flash reviewer
  ./pipeline/docs/harness.sh --review-model claude-sonnet-4-6 --review-timeout 8m0s  # Premium reviewer
  ./pipeline/docs/harness.sh --timeout 20m0s                  # Increase executor timeout
  ./pipeline/docs/harness.sh --max-iter 50                    # Limit to 50 iterations
  ./pipeline/docs/harness.sh --stop-on-block                  # Strict mode: stop on first blocker

${BOLD}REVIEWER PROMPT CUSTOMIZATION:${NC}
  Edit pipeline/docs/core/REVIEWER_PROMPT_TEMPLATE.md to customize:
  - Review checklist focus areas
  - Project-specific rules (SQL injection checks, API conventions, etc.)
  - Output format requirements

${BOLD}DOCS:${NC}
  See pipeline/docs/core/HARNESS_PROTOCOL.md for full documentation.
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
  if [[ -f "${PIPELINE_DIR}/scripts/verify.py" ]]; then
    log_ok "Verification script exists: ${PIPELINE_DIR}/scripts/verify.py"
  else
    log_warn "Missing ${PIPELINE_DIR}/scripts/verify.py — verification script recommended"
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

  # Check if all tasks in target filter scope are finished
  if [[ -f "${CONTEXT_DIR}/Tasks_list.md" ]]; then
    local next_task
    next_task=$(get_next_todo_task "$TASK_FILTER")
    if [[ -z "$next_task" ]]; then
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

  # Đọc task ID đang active từ STATUS.md (nếu có)
  local active_task="unknown"
  if [[ -f "${RUNTIME_DIR}/STATUS.md" ]]; then
    active_task=$(grep -m1 "^Current Task ID:" "${RUNTIME_DIR}/STATUS.md" 2>/dev/null \
      | sed 's/Current Task ID://;s/^[[:space:]]*//' || echo "unknown")
    [[ -z "$active_task" ]] && active_task="unknown"
  fi

  cat > "$iter_file" << EOF
# Iteration $(printf '%03d' $iter)
- Date: $(date '+%Y-%m-%d %H:%M')
- Task: ${active_task}
- Result: ${result}
- Git: $(git log --oneline -1 2>/dev/null || echo "no commits yet")
EOF

  if [[ "$VERBOSE" == true ]]; then
    log_info "Snapshot saved: $iter_file"
  fi
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# NOTE: checkpoint_commit() đã bị XÓA theo AGENT_CONSTITUTION.md Điều 8:
# "1 commit = 1 Task hoàn chỉnh đã pass verify [x] DONE"
#
# Git commit là trách nhiệm của AI agent (Phase 6), chỉ khi task [x] DONE.
# harness.sh KHÔNG tự động commit — tránh tạo commit vụn vặt theo iteration.
# Để xem uncommitted changes: git status
# ────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────
# Execute one iteration — dispatcher routes to single-model or dual-model
# ────────────────────────────────────────────────────────────────────────────
CURRENT_ACTIVE_TASK=""

execute_iteration() {
  local iter="$1"

  log_section "ITERATION ${iter} / ${MAX_ITERATIONS}"

  # Task-Bound Session & Memory Management
  local active_task
  active_task=$(get_next_todo_task "$TASK_FILTER")

  if [[ -n "$active_task" ]]; then
    if [[ "$active_task" != "$CURRENT_ACTIVE_TASK" ]]; then
      if [[ -n "$CURRENT_ACTIVE_TASK" ]]; then
        log_info "🔄 [SESSION FLUSH] Task switched from [${CURRENT_ACTIVE_TASK}] to [${active_task}]. Memory reset for new task."
      else
        log_info "⚡ [TASK SESSION] Initiating Task-Bound Session for [${active_task}]..."
      fi
      CURRENT_ACTIVE_TASK="$active_task"
    else
      log_info "⚡ [TASK SESSION] Continuing active Task-Bound Session for [${active_task}]..."
    fi
  fi

  # Context refresh trigger
  if (( iter % CONTEXT_REFRESH_EVERY == 0 && iter > 0 )); then
    log_warn "Context refresh point (iter ${iter}). AI re-validates filesystem state."
  fi

  if $DRY_RUN; then
    log_info "[DRY RUN] Simulating iteration ${iter} (mode: $([ -n "$REVIEW_MODEL" ] && echo 'dual-model' || echo 'single-model'))..."
    sleep 1
    return 0
  fi

  if [[ -n "$REVIEW_MODEL" ]]; then
    execute_iteration_dual_model "$iter"
  else
    execute_iteration_single_model "$iter"
  fi
}


# ────────────────────────────────────────────────────────────────────────────
# Fallback Auto-Commit helper:
# Automatically commits changes if a task has been completed and marked [x] DONE
# in Tasks_list.md to ensure clean working tree and prevent progress loss.
# ────────────────────────────────────────────────────────────────────────────
check_and_auto_commit_done_task() {
  local mode_label="${1:-HARNESS}"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    local done_task_id
    done_task_id=$(grep -E "^\|[[:space:]]*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep "\[x\] DONE" | tail -1 | grep -oE "TASK-[0-9]+" || true)
    if [[ -n "$done_task_id" ]]; then
      local latest_commit_msg
      latest_commit_msg=$(git log -1 --pretty=%B 2>/dev/null || echo "")
      if [[ "$latest_commit_msg" != *"[${done_task_id}]"* ]]; then
        log_info "[${mode_label}] Detected uncommitted changes for completed task [${done_task_id}]. Auto-committing to maintain clean working tree..."
        git add -A
        git commit -m "[${done_task_id}] feat: completed task (verified pass by ${mode_label})" 2>&1 | tee -a "${RUNTIME_DIR}/session_live.log" || true
        log_ok "[${mode_label}] Working tree cleanly committed for ${done_task_id}."
      fi
    fi
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Single-model iteration (classic mode — backward compatible)
# ────────────────────────────────────────────────────────────────────────────
execute_iteration_single_model() {
  local iter="$1"
  local active_task
  active_task=$(get_next_todo_task "$TASK_FILTER")

  if [[ -z "$active_task" ]]; then
    log_ok "No more matching tasks in queue for current filter."
    return 0
  fi

  local task_spec
  task_spec=$(get_task_spec "$active_task")

  local iter_prompt
  iter_prompt=$(_build_executor_payload "$active_task" "$task_spec" "SINGLE-MODEL")

  log_info "[SINGLE-MODEL] Launching continuous Task Session for ${active_task} (Iteration ${iter})..."
  if _run_agy_with_retry "$iter_prompt" "$PRINT_TIMEOUT" "$iter" "" "EXECUTOR"; then
    check_and_auto_commit_done_task "SINGLE-MODEL"
    return 0
  else
    return 1
  fi
}





# ────────────────────────────────────────────────────────────────────────────
# Shared helper: run agy with retry logic (used by both single and dual mode)
# ────────────────────────────────────────────────────────────────────────────
_run_agy_with_retry() {
  local prompt="$1"
  local timeout="$2"
  local iter="$3"
  local model_flag="${4:-}"  # Optional: "--model MODEL_NAME" for reviewer calls
  local role_name="${5:-EXECUTOR}"

  local max_retries=2
  local attempt=1
  local success=false
  local live_log="${RUNTIME_DIR}/session_live.log"

  while (( attempt <= max_retries )); do
    log_info "⚡ [${role_name}] AI is running..."

    # Simple status indicator (no elapsed time numbers)
    (
      while kill -0 $$ 2>/dev/null; do
        sleep 20
        echo -e "${CYAN}[RUNNING]${NC} [${role_name}] AI is active..."
      done
    ) &
    local heartbeat_pid=$!

    local agy_cmd="agy"
    local exit_code=0

    # Execute agy and stream live output to session_live.log
    if [[ -n "$model_flag" ]]; then
      # shellcheck disable=SC2086
      $agy_cmd $model_flag -p "$prompt" --dangerously-skip-permissions --print-timeout "$timeout" 2>&1 | tee -a "$live_log" || exit_code=${PIPESTATUS[0]}
    else
      $agy_cmd -p "$prompt" --dangerously-skip-permissions --print-timeout "$timeout" 2>&1 | tee -a "$live_log" || exit_code=${PIPESTATUS[0]}
    fi

    # Terminate background heartbeat
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true

    if [[ $exit_code -eq 0 ]]; then
      log_ok "[${role_name}] Done."
      success=true
      break
    else
      log_warn "[${role_name}] Attempt ${attempt}/${max_retries} failed or timed out."

      if (( attempt < max_retries )); then
        log_info "Retrying in 3 seconds..."
        sleep 3
      fi
      ((attempt++))
    fi
  done

  if [[ "$success" == true ]]; then
    return 0
  else
    log_error "[${role_name}] Execution failed after ${max_retries} attempts."
    return 1
  fi
}


# ────────────────────────────────────────────────────────────────────────────
# Build reviewer prompt by reading REVIEWER_PROMPT_TEMPLATE.md
# and substituting {{PLACEHOLDER}} tokens
# ────────────────────────────────────────────────────────────────────────────
_build_reviewer_prompt() {
  local iter="$1"
  local tier1_summary="$2"
  local git_diff="$3"
  local template_file="${CORE_DIR}/REVIEWER_PROMPT_TEMPLATE.md"
  local debate_log_path="${RUNTIME_DIR}/DEBATE_LOG.md"

  if [[ ! -f "$template_file" ]]; then
    log_error "REVIEWER_PROMPT_TEMPLATE.md not found at ${template_file}"
    log_error "Create it or copy from boilerplate. See pipeline/docs/core/HARNESS_PROTOCOL.md Section 6."
    return 1
  fi

  # Extract only the content between ---PROMPT_START--- and ---PROMPT_END---
  local raw_prompt
  raw_prompt=$(sed -n '/^---PROMPT_START---$/,/^---PROMPT_END---$/{ /^---PROMPT_START---$/d; /^---PROMPT_END---$/d; p }' "$template_file")

  # Extract Project-Specific Review Rules section (everything after the section header)
  local project_rules
  project_rules=$(awk '/^## Project-Specific Review Rules/{found=1; next} found && /^<!--/{next} found && /^-->/{next} found{print}' "$template_file" | grep -v '^$' | grep -v '^<!--' | grep -v '^-->' || true)

  # Substitute placeholders
  local prompt="$raw_prompt"
  prompt="${prompt//\{\{ITERATION\}\}/${iter}}"
  prompt="${prompt//\{\{TIER1_SUMMARY\}\}/${tier1_summary}}"
  prompt="${prompt//\{\{GIT_DIFF\}\}/${git_diff}}"
  prompt="${prompt//\{\{DEBATE_LOG_PATH\}\}/${debate_log_path}}"

  # Append project-specific rules if any exist
  if [[ -n "$project_rules" ]]; then
    prompt="${prompt}

## Project-Specific Review Rules (from REVIEWER_PROMPT_TEMPLATE.md)
${project_rules}"
  fi

  echo "$prompt"
}

# ────────────────────────────────────────────────────────────────────────────
# Dual-model iteration:
#   1. Executor (default model): ORIENT → PLAN → EXECUTE → VERIFY (Phase 0-4)
#   2. Reviewer (REVIEW_MODEL): Phase 5 Cognitive Review on working tree git diff HEAD
#   3. Fast Native Commit (no 3rd LLM call): Native git commit upon APPROVAL
# ────────────────────────────────────────────────────────────────────────────
execute_iteration_dual_model() {
  local iter="$1"
  local active_task
  active_task=$(get_next_todo_task "$TASK_FILTER")

  if [[ -z "$active_task" ]]; then
    log_ok "No more matching tasks in queue for current filter."
    return 0
  fi

  local task_spec
  task_spec=$(get_task_spec "$active_task")

  # ── STEP 1: Executor — Phase 0 (ORIENT) → Phase 4 (VERIFY) + Phase 7 (REPORT) ─────
  local executor_prompt
  executor_prompt=$(_build_executor_payload "$active_task" "$task_spec" "DUAL-MODEL")

  log_info "[DUAL-MODEL] Step 1/2 — Launching continuous EXECUTOR session for ${active_task}..."



  if ! _run_agy_with_retry "$executor_prompt" "$PRINT_TIMEOUT" "$iter" "" "EXECUTOR"; then
    log_error "[DUAL-MODEL] Executor failed on Iteration ${iter}. Skipping reviewer."
    return 1
  fi
  log_ok "[DUAL-MODEL] Executor execution complete."

  # ── STEP 2: Collect context for reviewer (token-efficient) ────────────────
  local tier1_summary
  tier1_summary=$(python3 pipeline/scripts/verify.py --summary 2>/dev/null \
    || echo "TIER1: UNKNOWN (verify.py failed to run)")

  # FIX: Collect working tree changes via git diff HEAD (not old committed diff HEAD~1 HEAD)
  local git_diff
  git_diff=$(git diff HEAD 2>/dev/null | head -n 400 || true)
  if [[ -z "$git_diff" ]]; then
    git_diff=$(git status --short 2>/dev/null || echo "(no diff available)")
  fi

  # OPTIMIZATION: If no working tree changes exist, auto-approve immediately (save Reviewer LLM call & tokens)
  if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
    log_ok "[DUAL-MODEL] No working tree changes detected. Auto-approving review step (saved LLM call & tokens)."
    return 0
  fi

  # ── STEP 3: Reviewer loop (max REVIEW_MAX_RETRIES) ───────────────────────
  local review_attempt=0
  local review_approved=false

  while (( review_attempt < REVIEW_MAX_RETRIES )); do
    (( review_attempt++ ))
    local diff_lines
    diff_lines=$(echo "$git_diff" | wc -l || echo 0)
    log_info "[DUAL-MODEL] Step 2/2 — Launching REVIEWER model '${REVIEW_MODEL}' (attempt ${review_attempt}/${REVIEW_MAX_RETRIES}, reviewing ${diff_lines} diff lines)..."

    # Build reviewer prompt from template
    local reviewer_prompt
    if ! reviewer_prompt=$(_build_reviewer_prompt "$iter" "$tier1_summary" "$git_diff"); then
      log_error "Failed to build reviewer prompt. Falling back to auto-approval."
      review_approved=true
      break
    fi

    # Run reviewer as fresh agy conversation with specified model
    if ! _run_agy_with_retry "$reviewer_prompt" "$REVIEW_TIMEOUT" "$iter" "--model ${REVIEW_MODEL}" "REVIEWER"; then
      log_warn "[DUAL-MODEL] Reviewer model call failed/timed out on attempt ${review_attempt}."
      continue
    fi

    # Parse review result from DEBATE_LOG.md
    local debate_log="${RUNTIME_DIR}/DEBATE_LOG.md"
    if [[ -f "$debate_log" ]] && grep -q "Review Result: APPROVED" "$debate_log" 2>/dev/null; then
      local last_result
      last_result=$(grep "Review Result:" "$debate_log" | tail -1)
      if [[ "$last_result" == *"APPROVED"* ]]; then
        log_ok "[DUAL-MODEL] Reviewer APPROVED!"
        review_approved=true
        break
      fi
    fi

    # REJECTED — extract reason and send back to executor for fix
    local rejection_reason
    rejection_reason=$(grep "Review Result: REJECTED" "${RUNTIME_DIR}/DEBATE_LOG.md" 2>/dev/null | tail -1 \
      || echo "Reviewer rejected without specifying reason. See DEBATE_LOG.md.")
    log_warn "[DUAL-MODEL] Reviewer REJECTED (attempt ${review_attempt}): ${rejection_reason}"

    if (( review_attempt < REVIEW_MAX_RETRIES )); then
      log_info "[DUAL-MODEL] Sending rejection feedback to executor for fix + re-verify..."
      local fix_prompt="[DUAL-MODEL MODE — EXECUTOR FIX ROLE]

Từ chối review lần ${review_attempt}/${REVIEW_MAX_RETRIES}. Lý do từ Reviewer:
${rejection_reason}

Đọc đầy đủ pipeline/docs/runtime/DEBATE_LOG.md để hiểu tất cả issues được nêu ra.
Sửa các vấn đề được chỉ ra (ưu tiên CRITICAL và HIGH trước).
Sau khi sửa, BẮT BUỘC chạy lại 'python3 pipeline/scripts/verify.py' và cập nhật STATUS.md, PROGRESS_LOG.md."
      if ! _run_agy_with_retry "$fix_prompt" "$PRINT_TIMEOUT" "$iter" "" "EXECUTOR-FIX"; then
        log_warn "[DUAL-MODEL] Executor fix attempt failed."
      fi
      # Refresh git diff after fix
      git_diff=$(git diff HEAD 2>/dev/null | head -n 400 || true)
      if [[ -z "$git_diff" ]]; then
        git_diff=$(git status --short 2>/dev/null || echo "(no diff available)")
      fi
      tier1_summary=$(python3 pipeline/scripts/verify.py --summary 2>/dev/null || echo "TIER1: UNKNOWN")
    fi
  done

  # ── STEP 4: Handle final outcome ──────────────────────────────────────────
  if [[ "$review_approved" == true ]]; then
    # OPTIMIZATION: Native fast commit — Eliminates heavy 3rd LLM call!
    local done_task_id
    done_task_id=$(grep -E "^\|[[:space:]]*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep "\[x\] DONE" | tail -1 | grep -oE "TASK-[0-9]+" || true)

    if [[ -n "$done_task_id" ]] && [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      log_info "[DUAL-MODEL] Auto-committing completed task [${done_task_id}] (Native Fast-Commit)..."
      git add -A
      git commit -m "[${done_task_id}] feat: completed task verified by ${REVIEW_MODEL}" || true
      log_ok "[DUAL-MODEL] Task ${done_task_id} committed successfully."
    else
      log_ok "[DUAL-MODEL] Work verified. Progress saved to filesystem."
    fi
    return 0
  else
    # MAX RETRIES EXCEEDED: Mark task BLOCKED, continue to next
    log_warn "[DUAL-MODEL] Reviewer rejected ${REVIEW_MAX_RETRIES} times. Marking task as BLOCKED."
    local blocked_prompt="[DUAL-MODEL MODE — BLOCKER HANDLING]

Reviewer đã từ chối code ${REVIEW_MAX_RETRIES} lần liên tiếp trong Iteration ${iter}.
Xem chi tiết lý do trong pipeline/docs/runtime/DEBATE_LOG.md.

Thực hiện Overnight Non-Blocking BLOCKED protocol:
1. Đọc task hiện tại trong pipeline/docs/context/Tasks_list.md.
2. Tạo report tại pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md.
3. Cập nhật task đó trong Tasks_list.md thành [!] BLOCKED.
4. Cập nhật STATUS.md để chuyển sang task TODO tiếp theo."
    _run_agy_with_retry "$blocked_prompt" "3m0s" "$iter" "" "BLOCKER-HANDLING" || \
      log_warn "[DUAL-MODEL] Blocker handling call failed. Check DEBATE_LOG.md manually."
    return 0
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

  if [[ -n "$TASK_FILTER" ]]; then filter_label="$TASK_FILTER"; else filter_label="ALL (Auto-queue from Tasks_list.md)"; fi

  log_info "Task Filter: ${filter_label}"

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
  local consecutive_task_fails=0
  local start_time
  start_time=$(date +%s)

  # ─── THE RALPH LOOP ───────────────────────────────────────────────────────
  while true; do
    # Execute one iteration
    if ! execute_iteration "$iter"; then
      log_warn "Iteration ${iter} execution failed or was interrupted"
      (( consecutive_task_fails++ ))
      local current_active_task
      current_active_task=$(grep -E "^\|[[:space:]]*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -E "(\[ \]|\[/\])" | head -1 | grep -oE "TASK-[0-9]+" || true)

      if [[ -n "$current_active_task" ]] && (( consecutive_task_fails >= 2 )); then
        log_warn "Task ${current_active_task} failed ${consecutive_task_fails} times consecutively. Marking as [!] BLOCKED (Overnight Non-Blocking Mode)..."
        mkdir -p "${BLOCKERS_DIR}"
        cat <<EOF > "${BLOCKERS_DIR}/${current_active_task}.md"
# BLOCKER REPORT: ${current_active_task}
- **Timestamp:** $(date '+%Y-%m-%d %H:%M:%S')
- **Iteration:** ${iter}
- **Reason:** Execution failed/timed out ${consecutive_task_fails} times consecutively during autonomous Ralph loop.
- **Action:** Auto-bypassed by harness to continue overnight queue. Human investigation required.
EOF
        # Update Tasks_list.md to [!] BLOCKED
        sed -i -E "s/(\|[[:space:]]*\`${current_active_task}\`[[:space:]]*\|[^|]*\|[[:space:]]*)(\[[ /]\])/\1[\!] BLOCKED/" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null || true
        # Reset fail counter for next task
        consecutive_task_fails=0
        log_info "Continuing loop with next available task in queue..."
      elif [[ -z "$current_active_task" ]]; then
        log_info "No more active tasks in queue. Proceeding to exit check."
      else
        log_info "Retrying task ${current_active_task} in next iteration (attempt ${consecutive_task_fails}/2)..."
      fi

      if [[ "$STOP_ON_BLOCK" == true ]] && (( consecutive_task_fails >= 2 )); then
        log_error "Strict stop-on-block enabled. Exiting."
        break
      fi

      iter=$((iter + 1))
      if (( iter > MAX_ITERATIONS )); then
        log_warn "Reached maximum iterations (${MAX_ITERATIONS}). Stopping loop."
        break
      fi
      continue
    fi
    consecutive_task_fails=0

    # Fallback auto-commit if any task completed
    check_and_auto_commit_done_task "RALPH-LOOP"

    # Check exit condition
    local exit_code
    exit_code=$(check_exit_condition "$iter")

    case "$exit_code" in
      EXIT_ALL_TASKS_PROCESSED|EXIT_DONE)
        log_section "✅ ALL QUEUED TASKS PROCESSED"
        create_iteration_snapshot "$iter" "DONE"

        local duration=$(( $(date +%s) - start_time ))
        local done_count
        done_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[x\]" || true)
        local blocked_count
        blocked_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[!\]" || true)

        log_ok "Completed loop in ${iter} iterations ($(( duration / 60 ))m $(( duration % 60 ))s)"
        log_ok "Tasks Completed ([x] DONE): ${done_count}"
        log_warn "Tasks Blocked   ([!] BLOCKED): ${blocked_count} (See ${BLOCKERS_DIR}/ for reports)"
        log_ok "See pipeline/docs/runtime/PROOF_OF_SOLUTION.md for verification"

        # Final check for uncommitted changes
        check_and_auto_commit_done_task "FINAL-CHECK"

        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
          log_warn "⚠️  Uncommitted changes detected. Review: git status"
          log_warn "    AI should have committed each task via Phase 6. Check PROGRESS_LOG.md."
        else
          log_ok "Git working tree clean. All task commits are in order."
          # Tag milestone khi toàn bộ queue done
          local tag_name="harness/done-$(date '+%Y%m%d-%H%M')"
          git tag "$tag_name" 2>/dev/null && log_ok "Git tag created: ${tag_name}" || true
        fi
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
        log_warn "Reached maximum iterations (${MAX_ITERATIONS})"
        log_warn "Review pipeline/docs/runtime/PROGRESS_LOG.md for current state"
        log_warn "Increase --max-iter or review Tasks_list.md to continue"
        check_and_auto_commit_done_task "MAX-ITER-FALLBACK"
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
          log_warn "Uncommitted changes exist (task likely still IN_PROGRESS). Check git status."
        fi
        exit 2
        ;;

      EXIT_CONTINUE)
        create_iteration_snapshot "$iter" "CONTINUE"
        log_info "Iteration ${iter} complete (progression saved to filesystem). Continuing..."
        iter=$((iter + 1))
        ;;
    esac
  done
  # ─────────────────────────────────────────────────────────────────────────
}

main "$@"

