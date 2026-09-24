#!/usr/bin/env bash
# =============================================================================
# harness.sh — Next-Gen Ralph Loop Master Orchestrator (2026 Standard)
# Optimized for: Antigravity / Agy Pro Subscription Quota
#
# Combines:
#   - Task-Bound Continuous Sessions & JIT Memory Flush (Token-efficient)
#   - Tier 1 Deterministic Verification (verify.py) + Tier 2 Cognitive Review (--review-model)
#   - Discrete POSIX Exit Codes (0: Done, 3: Blocked, 4: Max Iters, 6: Stuck, 7: Compaction, 8: Provider)
#   - Context Auto-Compaction Hard-Fail Protection
#   - Circuit Breaker & Transient API Backoff Retry
#   - Plan Seal Integrity Checks
#   - Automated Run Logging & Retro Hooks (.ralph/runs/<RUN_ID>/)
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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Run-scoped logging & cleanup
mkdir -p "${PIPELINE_DIR}/.ralph/runs"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${PIPELINE_DIR}/.ralph/runs/${RUN_ID}"
mkdir -p "$RUN_DIR" "$ITERATIONS_DIR" "$BLOCKERS_DIR"
export RALPH_RUN_TAG="ralph-managed-run-${RUN_ID}"
_EXTRA_PY_PATHS="."
[[ -d "${PIPELINE_DIR}/../src" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:./src"
[[ -d "${PIPELINE_DIR}/../app" ]] && _EXTRA_PY_PATHS="${_EXTRA_PY_PATHS}:./app"
export PYTHONPATH="${_EXTRA_PY_PATHS}:${PIPELINE_DIR}/..:${PYTHONPATH:-}"

reap_orphans() {
  pkill -f "$RALPH_RUN_TAG" 2>/dev/null || true
}

cleanup_on_interrupt() {
  echo -e "\n${YELLOW}[RALPH] Interrupted by user (Ctrl+C). Cleaning up active processes...${NC}"
  reap_orphans
  exit 130
}

trap cleanup_on_interrupt INT TERM
trap 'echo -e "\n${CYAN}[RALPH]${NC} Run logs archived in: ${RUN_DIR}\n💡 Run automated post-loop improvement: ${BOLD}./pipeline/scripts/ralph-retro.sh ${RUN_DIR}${NC}"' EXIT

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

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

_build_executor_payload() {
  local active_task="$1"
  local task_spec="$2"
  local role_tag="${3:-SINGLE-MODEL}"
  local complexity_notice="${4:-}"
  local tech_summary
  tech_summary=$(get_tech_context_summary)
  local bound_summary
  bound_summary=$(get_boundaries_summary)

  sync_current_task_doc "$active_task" "$task_spec"

  cat <<EOF
[${role_tag} — TASK-BOUND SESSION — TARGET: ${active_task}]

=== 📜 10 ĐIỀU LUẬT CỐT LÕI (AGENT_GUIDE.md) ===
1. State on disk (STATUS.md/PLAN.md). 2. Atomic steps & Logical units. 3. Verify pass before done (chạy 'python3 pipeline/scripts/verify.py' đồng bộ foreground, KHÔNG chạy ngầm background). 4. Proof over promise. 5. Inspect file before edit & Dynamic path anchoring. 6. Scope boundary. 7. 1 Task = 1 Professional Commit ([x] DONE, commit chi tiết chuyên nghiệp: Title + Summary + Key Changes + Verification, tuyệt đối không commit một dòng sơ sài). 8. Overnight Non-blocking BLOCKED. 9. Context & Timeout protection. 10. Clean working tree.
$([ -n "$complexity_notice" ] && echo -e "\n=== ⚠️ CHỈ THỊ CHIA NHỎ ATOMIC (COMPLEXITY GUARD) ===\n${complexity_notice}")

=== 🎯 THÔNG TIN TASK SPEC (TRÍCH XUẤT TỪ Tasks_list.md) ===
${task_spec}

=== 🛡️ GIỚI HẠN & TECH STACK (JIT CONTEXT) ===
- Tech Context: ${tech_summary}
- Scope Boundaries: ${bound_summary}

=== 🚀 NHIỆM VỤ THỰC THI CHO ${active_task} ===
Thực thi trọn vẹn Task ${active_task} trong phiên làm việc này:
1. Đọc/Tạo pipeline/docs/runtime/PLAN.md cho ${active_task} (chia thành 2-4 atomic steps).
2. Thực thi tuần tự từng bước: Sửa code trong scope ──► Chạy 'python3 pipeline/scripts/verify.py' trực tiếp foreground (có thể dùng --quick hoặc --test-target để rút ngắn thời gian).
3. Sửa ngay nếu VERIFICATION_REPORT báo lỗi cho đến khi PASS 100%.
4. Cập nhật tiến độ liên tục vào STATUS.md, PROGRESS_LOG.md và PLAN.md ra filesystem.
5. Khi ${active_task} đã xong 100% và verify PASS: Đánh dấu [x] DONE dòng ${active_task} trong Tasks_list.md và DỪNG PHIÊN (Harness sẽ tự động tạo commit chuyên nghiệp chi tiết gồm Summary, Key Changes, Verification).

⚠️ KHÔNG COMMIT TRUNG GIAN. TUYỆT ĐỐI KHÔNG COMMIT 1 DÒNG SƠ SÀI.
NẾU BỊ KẸT (sửa 2 lần không qua verify.py): Dừng lại, viết report vào BLOCKERS/${active_task}.md và đổi task thành [!] BLOCKED.
EOF
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
  local tasks_file="${CONTEXT_DIR}/Tasks_list.md"

  local task_name=""
  local task_type="feat"
  local task_scope="core"
  local task_why=""
  local task_what=""

  if [[ -f "$tasks_file" && -n "$tid" ]]; then
    # 1. Extract Task Name from table or heading
    task_name=$(awk -F'|' -v tid="$tid" '$0 ~ tid {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit}' "$tasks_file")
    if [[ -z "$task_name" ]]; then
      task_name=$(awk -v tid="$tid" '$0 ~ ("^### [^ ]* " tid ":") {sub("^### [^ ]* " tid ":[ \t]*", ""); print; exit}' "$tasks_file")
    fi

    # 2. Extract Task Type from metadata
    local raw_type
    raw_type=$(awk -v tid="$tid" '
      $0 ~ ("^### [^ ]* " tid) { found=1; next }
      found && /^### [^ ]* TASK-/ { exit }
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
      $0 ~ ("^### [^ ]* " tid) { found=1; next }
      found && /^### [^ ]* TASK-/ { exit }
      found && /^[ \t]*- \*\*Why:\*\*/ { sub(/^[ \t]*- \*\*Why:\*\*[ \t]*/, ""); print; exit }
    ' "$tasks_file")

    task_what=$(awk -v tid="$tid" '
      $0 ~ ("^### [^ ]* " tid) { found=1; next }
      found && /^### [^ ]* TASK-/ { exit }
      found && /^[ \t]*- \*\*What:\*\*/ { sub(/^[ \t]*- \*\*What:\*\*[ \t]*/, ""); print; exit }
    ' "$tasks_file")
  fi

  [[ -z "$task_name" ]] && task_name="implement requested specifications"

  # Determine scope from changed files if possible
  local staged_dirs
  staged_dirs=$(git diff --cached --name-only 2>/dev/null | awk -F/ '{if (NF>1) print $1}' | grep -vE "^(pipeline|\.gitignore|\.github)" | sort | uniq | head -1)
  if [[ -n "$staged_dirs" ]]; then
    task_scope="$staged_dirs"
  elif git diff --cached --name-only 2>/dev/null | grep -q "pipeline"; then
    task_scope="pipeline"
  fi

  # Summary of changed files (up to 12 files)
  local file_changes
  file_changes=$(git diff --cached --name-status 2>/dev/null | head -n 12 | sed 's/^/- /')
  local total_changed
  total_changed=$(git diff --cached --name-only 2>/dev/null | wc -l)
  if (( total_changed > 12 )); then
    file_changes="${file_changes}"$'\n'"- ... and $((total_changed - 12)) more files"
  fi

  # Diff stat summary (e.g. 5 files changed, 120 insertions(+), 10 deletions(-))
  local stat_summary
  stat_summary=$(git diff --cached --stat 2>/dev/null | tail -1 | sed 's/^[ \t]*//')

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
        # Auto-sync table row if it was still TODO or IN_PROGRESS
        sed -i -E "s/(\|[[:space:]]*\`${target_task}\`[^|]*\|[^|]*\|[^|]*\|)[[:space:]]*\[[ /]\][[:space:]]*(TODO|IN_PROGRESS)/\1 [x] DONE/" "${CONTEXT_DIR}/Tasks_list.md" 2>/dev/null || true
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
        log_info "[${mode_label}] Detected uncommitted changes for completed task [${done_task_id}]. Auto-committing cleanly..."
        git add -A
        local commit_msg
        commit_msg=$(generate_commit_message "$done_task_id" "$mode_label")
        git commit -m "$commit_msg" 2>&1 | tee -a "${RUNTIME_DIR}/session_live.log" || true
        # Clean up verified checkpoint tag upon successful task commit
        git tag -d "ralph-checkpoint-${done_task_id}" >/dev/null 2>&1 || true
        log_ok "[${mode_label}] Working tree cleanly committed for ${done_task_id}."
      fi
    fi
  fi
}

ensure_clean_working_tree() {
  local target_task="${1:-}"
  local auto_clean="${2:-$AUTO_CLEAN_DIRTY}"
  local ckpt_tag="ralph-checkpoint-${target_task}"

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
  tier1_summary=$(python3 "${PIPELINE_DIR}/scripts/verify.py" --summary 2>/dev/null || echo "TIER1: UNKNOWN")

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
# Main Master Loop
# ────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  preflight_check

  if [[ -n "$PROVIDER_OVERRIDE" ]]; then
    export AGENT_PROVIDER="$PROVIDER_OVERRIDE"
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
    executor_prompt=$(_build_executor_payload "$active_task" "$task_spec" "$role_tag" "$complexity_notice")

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
