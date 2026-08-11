#!/usr/bin/env bash
# =============================================================================
# harness.sh — Ralph Loop Execution Script
# Chạy AI agent trong một vòng lặp tự trị với đầy đủ guardrails
#
# Cách dùng:
#   ./H_docs/harness.sh                               # Chạy với defaults (single-model)
#   ./H_docs/harness.sh --max-iter 20                 # Giới hạn 20 iterations
#   ./H_docs/harness.sh --task "TASK-001"             # Chỉ định task ID
#   ./H_docs/harness.sh --dry-run                     # Simulate, không thực thi thực sự
#   ./H_docs/harness.sh --review-model gemini-3.6-flash-low  # Bật Dual-Model mode
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
  ./H_docs/harness.sh [OPTIONS]

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
                                   Reads prompt from H_docs/core/REVIEWER_PROMPT_TEMPLATE.md.
                                   Output: 'Review Result: APPROVED' or 'Review Result: REJECTED: <reason>'
  If REVIEWER rejects:
    - EXECUTOR reads DEBATE_LOG.md, fixes issues, re-runs verify.py, then REVIEWER checks again.
    - Max ${REVIEW_MAX_RETRIES:-2} retry cycles per iteration.
  If REVIEWER rejects after max retries:
    - Task is marked [!] BLOCKED (same as Overnight Non-Blocking blocker behavior).
    - Harness continues to next TODO task automatically.
  The reviewer call is a FRESH agy conversation (separate context, same CLI quota).

${BOLD}EXAMPLES:${NC}
  ./H_docs/harness.sh                                  # Single-model mode (classic)
  ./H_docs/harness.sh --review-model gemini-3.6-flash-low  # Dual-model: cheap flash reviewer
  ./H_docs/harness.sh --review-model claude-sonnet-4-6 --review-timeout 8m0s  # Premium reviewer
  ./H_docs/harness.sh --timeout 20m0s                  # Increase executor timeout
  ./H_docs/harness.sh --max-iter 50                    # Limit to 50 iterations
  ./H_docs/harness.sh --stop-on-block                  # Strict mode: stop on first blocker

${BOLD}REVIEWER PROMPT CUSTOMIZATION:${NC}
  Edit H_docs/core/REVIEWER_PROMPT_TEMPLATE.md to customize:
  - Review checklist focus areas
  - Project-specific rules (SQL injection checks, API conventions, etc.)
  - Output format requirements

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
execute_iteration() {
  local iter="$1"

  log_section "ITERATION ${iter} / ${MAX_ITERATIONS}"

  # Context refresh trigger
  if (( iter % CONTEXT_REFRESH_EVERY == 0 && iter > 0 )); then
    log_warn "Context refresh point (iter ${iter}). AI should re-read context docs."
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
# Single-model iteration (classic mode — backward compatible, unchanged)
# ────────────────────────────────────────────────────────────────────────────
execute_iteration_single_model() {
  local iter="$1"

  # ─── AUTOMATED AGY CLI EXECUTION ─────────────────────────────────────────
  local iter_prompt="Đọc H_docs/core/AGENT_CONSTITUTION.md, H_docs/context/Tasks_list.md và H_docs/runtime/STATUS.md. Tìm task đầu tiên có trạng thái [ ] TODO hoặc [/] IN_PROGRESS trong Tasks_list.md. Đọc H_docs/runtime/PLAN.md (nếu chưa có plan cho task này thì tạo PLAN.md). Thực hiện 1 bước atomic tiếp theo trong task đó theo quy trình Harness Protocol. Ở Phase 4 (VERIFY), BẮT BUỘC chạy 'python3 H_docs/scripts/verify.py' để kiểm định Tier 1 (Linter/Type/Security/Test) và kiểm tra H_docs/runtime/VERIFICATION_REPORT.md. NẾU VERIFICATION_REPORT có lỗi, hãy đọc log ngắn gọn trong đó để sửa ngay. Ở Phase 5 (REVIEW), thực hiện Tier 2 Cognitive Review dựa trên git diff và H_docs/core/REVIEW_PROTOCOL.md. BẮT BUỘC CẬP NHẬT H_docs/runtime/STATUS.md, H_docs/runtime/PROGRESS_LOG.md và PLAN.md RA FILESYSTEM để lưu progression context cho Ralph loop. QUY TẮC COMMIT: KHÔNG THỰC HIỆN GIT COMMIT TRONG CÁC ITERATION TRUNG GIAN. CHỈ CHẠY GIT COMMIT KHI THỰC SỰ HOÀN THÀNH 1 TASK VÀ ĐÁNH DẤU [x] DONE TRONG Tasks_list.md với commit message format: [TASK-ID] <type>(<scope>): <mô tả ngắn gọn task đã hoàn thành>. NẾU GẶP BLOCKER mà không thể tự giải quyết: 1) Viết báo cáo chi tiết vào file H_docs/runtime/BLOCKERS/<TASK_ID>.md. 2) Cập nhật dòng của task đó trong H_docs/context/Tasks_list.md thành [!] BLOCKED. 3) Cập nhật STATUS.md để chuyển sang task TODO tiếp theo. KHÔNG TẠO file BLOCKED.md ở root ngoại trừ khi khẩn cấp. LƯU Ý QUAN TRỌNG: Chỉ được phép ghi 'Phase: ALL_DONE' vào H_docs/runtime/STATUS.md KHI VÀ CHỈ KHI TẤT CẢ các tasks trong Tasks_list.md đã được thực hiện, phản biện, xác minh pass 100% và đánh dấu [x] DONE (hoặc [!] BLOCKED). Khi đó mới cập nhật STATUS.md thành Phase: ALL_DONE và viết H_docs/runtime/PROOF_OF_SOLUTION.md. Nếu dự án còn task chưa hoàn thành, giữ Phase: IN_PROGRESS."

  log_info "[SINGLE-MODEL] Launching agy for Iteration ${iter}..."
  _run_agy_with_retry "$iter_prompt" "$PRINT_TIMEOUT" "$iter"
}

# ────────────────────────────────────────────────────────────────────────────
# Shared helper: run agy with retry logic (used by both single and dual mode)
# ────────────────────────────────────────────────────────────────────────────
_run_agy_with_retry() {
  local prompt="$1"
  local timeout="$2"
  local iter="$3"
  local model_flag="${4:-}"  # Optional: "--model MODEL_NAME" for reviewer calls

  local max_retries=3
  local attempt=1
  local success=false

  while (( attempt <= max_retries )); do
    local agy_cmd="agy"
    if [[ -n "$model_flag" ]]; then
      # shellcheck disable=SC2086  # Intentional word splitting for model flag
      if $agy_cmd $model_flag -p "$prompt" --dangerously-skip-permissions --print-timeout "$timeout"; then
        success=true; break
      fi
    else
      if $agy_cmd -p "$prompt" --dangerously-skip-permissions --print-timeout "$timeout"; then
        success=true; break
      fi
    fi
    log_warn "agy attempt ${attempt}/${max_retries} failed or timed out (iter ${iter})."
    if (( attempt < max_retries )); then log_info "Retrying in 5 seconds..."; sleep 5; fi
    ((attempt++))
  done

  if [[ "$success" == true ]]; then
    return 0
  else
    log_error "agy failed after ${max_retries} attempts (iter ${iter})."
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
    log_error "Create it or copy from boilerplate. See H_docs/core/HARNESS_PROTOCOL.md Section 6."
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
#      Then COMMIT + REPORT after reviewer approves (Phase 6-7)
#   2. Reviewer (REVIEW_MODEL): Phase 5 Cognitive Review on git diff
#   3. Retry loop: on REJECTED, executor fixes + re-verify, reviewer re-checks
#   4. Max retries exceeded: mark task BLOCKED, continue to next task
# ────────────────────────────────────────────────────────────────────────────
execute_iteration_dual_model() {
  local iter="$1"

  # ── STEP 1: Executor — Phase 0 (ORIENT) → Phase 4 (VERIFY) ───────────────
  # Explicitly instructs executor to STOP before Phase 5 (Review).
  # Phase 5 is handled by the reviewer model below.
  # Phase 6 (Commit) and Phase 7 (Report) will be done after APPROVED.
  local executor_prompt="[DUAL-MODEL MODE — EXECUTOR ROLE]

Đọc H_docs/core/AGENT_CONSTITUTION.md, H_docs/context/Tasks_list.md và H_docs/runtime/STATUS.md.
Tìm task đầu tiên có trạng thái [ ] TODO hoặc [/] IN_PROGRESS trong Tasks_list.md.
Đọc H_docs/runtime/PLAN.md (nếu chưa có plan cho task này thì tạo PLAN.md).

Thực hiện các Phase sau theo H_docs/core/WORKFLOW_STANDARDS.md:
  - PHASE 0 (ORIENT): Đọc context docs.
  - PHASE 1 (SPEC): Xác định acceptance criteria nếu chưa có.
  - PHASE 2 (PLAN): Chia bước nếu chưa có PLAN.md.
  - PHASE 3 (EXECUTE): Thực thi 1 bước atomic tiếp theo.
  - PHASE 4 (VERIFY): BẮT BUỘC chạy 'python3 H_docs/scripts/verify.py'.
    Nếu VERIFICATION_REPORT.md có lỗi → sửa ngay và chạy lại verify.py cho đến khi PASS.

⚠️ DỪNG LẠI SAU PHASE 4 — KHÔNG tự thực hiện Phase 5 (Review), Phase 6 (Commit), hay Phase 7 (Report).
Phase 5 sẽ được thực hiện bởi một Reviewer Model độc lập.
Phase 6 và 7 sẽ được thực hiện sau khi Reviewer phê duyệt.

NẾU GẶP BLOCKER mà không thể tự giải quyết: 1) Viết báo cáo chi tiết vào H_docs/runtime/BLOCKERS/<TASK_ID>.md. 2) Cập nhật task đó trong H_docs/context/Tasks_list.md thành [!] BLOCKED. 3) Cập nhật STATUS.md để chuyển sang task TODO tiếp theo.

LƯU Ý: Chỉ ghi 'Phase: ALL_DONE' vào STATUS.md khi TẤT CẢ tasks đã pass và marked [x] DONE hoặc [!] BLOCKED. Nếu còn tasks chưa xong, giữ Phase: IN_PROGRESS."

  log_info "[DUAL-MODEL] Step 1/2 — Launching EXECUTOR (Phase 0→4)..."
  if ! _run_agy_with_retry "$executor_prompt" "$PRINT_TIMEOUT" "$iter"; then
    log_error "[DUAL-MODEL] Executor failed on Iteration ${iter}. Skipping reviewer."
    return 1
  fi
  log_ok "[DUAL-MODEL] Executor Phase 0→4 complete."

  # ── STEP 2: Collect context for reviewer (token-efficient) ────────────────
  local tier1_summary
  tier1_summary=$(python3 H_docs/scripts/verify.py --summary 2>/dev/null \
    || echo "TIER1: UNKNOWN (verify.py failed to run)")

  # Cap git diff at ~400 lines to control token cost while covering most atomic commits
  local git_diff
  git_diff=$(git diff HEAD~1 HEAD 2>/dev/null | head -n 400 \
    || echo "(no diff available — possibly first commit or git error)")

  # ── STEP 3: Reviewer loop (max REVIEW_MAX_RETRIES) ───────────────────────
  local review_attempt=0
  local review_approved=false

  while (( review_attempt < REVIEW_MAX_RETRIES )); do
    (( review_attempt++ ))
    log_info "[DUAL-MODEL] Step 2/2 — Launching REVIEWER model '${REVIEW_MODEL}' (attempt ${review_attempt}/${REVIEW_MAX_RETRIES})..."

    # Build reviewer prompt from template
    local reviewer_prompt
    if ! reviewer_prompt=$(_build_reviewer_prompt "$iter" "$tier1_summary" "$git_diff"); then
      log_error "Failed to build reviewer prompt. Falling back to single-model self-review."
      break
    fi

    # Run reviewer as fresh agy conversation with specified model
    if ! _run_agy_with_retry "$reviewer_prompt" "$REVIEW_TIMEOUT" "$iter" "--model ${REVIEW_MODEL}"; then
      log_warn "[DUAL-MODEL] Reviewer model call failed/timed out on attempt ${review_attempt}."
      continue
    fi

    # Parse review result from DEBATE_LOG.md
    local debate_log="${RUNTIME_DIR}/DEBATE_LOG.md"
    if [[ -f "$debate_log" ]] && grep -q "Review Result: APPROVED" "$debate_log" 2>/dev/null; then
      # Check that APPROVED is in the LAST review entry (not an older one)
      local last_result
      last_result=$(grep "Review Result:" "$debate_log" | tail -1)
      if [[ "$last_result" == *"APPROVED"* ]]; then
        log_ok "[DUAL-MODEL] Reviewer APPROVED! Proceeding to Phase 6 (Commit) + Phase 7 (Report)."
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

Đọc đầy đủ H_docs/runtime/DEBATE_LOG.md để hiểu tất cả issues được nêu ra.
Sửa các vấn đề được chỉ ra (ưu tiên CRITICAL và HIGH trước).
Sau khi sửa, BẮT BUỘC chạy lại 'python3 H_docs/scripts/verify.py' và đảm bảo PASS.

⚠️ DỪNG SAU PHASE 4 — KHÔNG tự làm Phase 5 (Review). Reviewer sẽ kiểm tra lại."
      if ! _run_agy_with_retry "$fix_prompt" "$PRINT_TIMEOUT" "$iter"; then
        log_warn "[DUAL-MODEL] Executor fix attempt failed."
      fi
      # Refresh git diff after fix
      git_diff=$(git diff HEAD~1 HEAD 2>/dev/null | head -n 400 \
        || echo "(no diff available)")
      tier1_summary=$(python3 H_docs/scripts/verify.py --summary 2>/dev/null \
        || echo "TIER1: UNKNOWN")
    fi
  done

  # ── STEP 4: Handle final outcome ──────────────────────────────────────────
  if [[ "$review_approved" == true ]]; then
    # ── APPROVED: Executor runs Phase 6 (Commit) + Phase 7 (Report) ─────────
    log_info "[DUAL-MODEL] Running Phase 6 (Commit) + Phase 7 (Report) after approval..."
    local commit_prompt="[DUAL-MODEL MODE — COMMIT & REPORT ROLE]

Reviewer đã phê duyệt code (xem H_docs/runtime/DEBATE_LOG.md).
Thực hiện Phase 6 và Phase 7 theo H_docs/core/WORKFLOW_STANDARDS.md:
  - PHASE 7 (REPORT): BẮT BUỘC cập nhật PROGRESS_LOG.md, STATUS.md, đánh dấu step trong PLAN.md và Tasks_list.md ra filesystem.
  - PHASE 6 (COMMIT): CHỈ THỰC HIỆN GIT COMMIT KHI TASK ĐÃ HOÀN THÀNH ([x] DONE). Tạo 1 git commit rõ ràng, mạch lạc với message format: [TASK-ID] <type>(<scope>): <mô tả task đã hoàn thành>. KHÔNG commit nếu task chưa xong.

LƯU Ý: Chỉ ghi 'Phase: ALL_DONE' vào STATUS.md khi TẤT CẢ tasks đã pass 100% và marked [x] DONE hoặc [!] BLOCKED."
    _run_agy_with_retry "$commit_prompt" "5m0s" "$iter" || \
      log_warn "[DUAL-MODEL] Phase 6-7 executor call failed. Manual commit may be needed."
    return 0
  else
    # ── MAX RETRIES EXCEEDED: Mark task BLOCKED, continue to next ────────────
    log_warn "[DUAL-MODEL] Reviewer rejected ${REVIEW_MAX_RETRIES} times. Marking task as BLOCKED."
    log_info "[DUAL-MODEL] Instructing executor to write blocker report and move to next task..."
    local blocked_prompt="[DUAL-MODEL MODE — BLOCKER HANDLING]

O Dual-Model Review: Reviewer đã từ chối code ${REVIEW_MAX_RETRIES} lần liên tiếp trong Iteration ${iter}.
Xem chi tiết lý do trong H_docs/runtime/DEBATE_LOG.md.

Thực hiện Overnight Non-Blocking BLOCKED protocol:
1. Đọc task hiện tại đang [/] IN_PROGRESS trong H_docs/context/Tasks_list.md.
2. Tạo report chi tiết tại H_docs/runtime/BLOCKERS/<TASK_ID>.md với:
   - Lý do: Reviewer liên tục rejected sau ${REVIEW_MAX_RETRIES} lần retry.
   - Các issues: [tóm tắt từ DEBATE_LOG.md]
   - Action cần thiết từ human: [mô tả cụ thể]
3. Cập nhật dòng task đó trong Tasks_list.md thành [!] BLOCKED.
4. Cập nhật STATUS.md để giải phóng task này.
5. Tự động chọn task [ ] TODO tiếp theo trong Tasks_list.md để tiếp tục.

KHÔNG tạo BLOCKED.md ở root."
    _run_agy_with_retry "$blocked_prompt" "5m0s" "$iter" || \
      log_warn "[DUAL-MODEL] Blocker handling call failed. Check DEBATE_LOG.md manually."
    return 0  # Return 0 so harness continues to next iteration (Overnight Non-Blocking)
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

        local duration=$(( $(date +%s) - start_time ))
        local done_count
        done_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[x\]" || true)
        local blocked_count
        blocked_count=$(grep -E "^\|.*\`TASK-" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null | grep -c "\[!\]" || true)

        log_ok "Completed loop in ${iter} iterations ($(( duration / 60 ))m $(( duration % 60 ))s)"
        log_ok "Tasks Completed ([x] DONE): ${done_count}"
        log_warn "Tasks Blocked   ([!] BLOCKED): ${blocked_count} (See ${BLOCKERS_DIR}/ for reports)"
        log_ok "See H_docs/runtime/PROOF_OF_SOLUTION.md for verification"

        # Kiểm tra uncommitted changes — git commit là trách nhiệm của AI (Phase 6)
        # chỉ khi task [x] DONE theo format [TASK-ID] <type>(<scope>): <mô tả>
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
        log_warn "Review H_docs/runtime/PROGRESS_LOG.md for current state"
        log_warn "Increase --max-iter or review Tasks_list.md to continue"
        # KHÔNG auto-commit — AI sẽ đã commit theo task khi xong (Phase 6)
        # Uncommitted changes = task chưa done, đây là trạng thái đúng
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

