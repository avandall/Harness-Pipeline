#!/usr/bin/env bash
# =============================================================================
# plan-refine.sh — Dual-Model Architectural Interview & Plan Refinement Loop
# Automates the interactive requirements interview (USER_GUIDE.md Tips 12 & 14)
# Loops between Critic (Lead Architect) and Planner (Author) until 100% APPROVED.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOCS_DIR="${PIPELINE_DIR}/docs"
CONTEXT_DIR="${DOCS_DIR}/context"
RUNTIME_DIR="${DOCS_DIR}/runtime"
PROMPTS_DIR="${PIPELINE_DIR}/prompts"
DEBATE_LOG="${RUNTIME_DIR}/PLAN_DEBATE.md"
PLAN_DIFF_LOG="${RUNTIME_DIR}/PLAN_DIFF.md"
export PYTHONPATH=".:./src:${PIPELINE_DIR}/..:${PYTHONPATH:-}"

MAX_TURNS=5
TIMEOUT="10m0s"
CRITIC_MODEL="${CRITIC_MODEL:-}"
PLANNER_MODEL="${PLANNER_MODEL:-}"
PROVIDER_OVERRIDE=""
AUTO_SEAL=true
VERBOSE=false

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'
BOLD=$'\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }

show_help() {
  cat <<EOF
${BOLD}plan-refine.sh${NC} — Dual-Model Plan Refinement & Interview Loop

${BOLD}USAGE:${NC}
  ./pipeline/scripts/plan-refine.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  --critic-model, -c MODEL    Model name for Critic (Lead Architect Interviewer)
  --planner-model, -p MODEL   Model name for Planner (Author / Refiner)
  --max-turns, -n TURNS       Maximum debate turns (default: 5)
  --timeout TIME              Timeout per turn (default: 10m0s)
  --provider NAME             Agent CLI provider (default: agy)
  --no-seal                   Do not auto-seal after 100% approval
  --verbose, -v               Verbose logging output
  --help, -h                  Show this help message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --critic-model|-c) CRITIC_MODEL="$2"; shift 2 ;;
      --planner-model|-p) PLANNER_MODEL="$2"; shift 2 ;;
      --max-turns|-n) MAX_TURNS="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      --provider) PROVIDER_OVERRIDE="$2"; shift 2 ;;
      --no-seal) AUTO_SEAL=false; shift ;;
      --verbose|-v) VERBOSE=true; shift ;;
      --help|-h) show_help; exit 0 ;;
      *) echo "Unknown option: $1" >&2; show_help; exit 2 ;;
    esac
  done
}

preflight_check() {
  mkdir -p "$RUNTIME_DIR" "${PIPELINE_DIR}/.ralph/runs"

  for f in "${CONTEXT_DIR}/PROJECT_BRIEF.md" "${CONTEXT_DIR}/Tasks_list.md" "${CONTEXT_DIR}/BOUNDARIES.md" "${CONTEXT_DIR}/TECH_CONTEXT.md" "${CONTEXT_DIR}/INTERVIEW_PLAN.md"; do
    if [[ ! -f "$f" ]]; then
      log_error "Missing context file: $f. Please initialize context and define INTERVIEW_PLAN.md first."
      exit 1
    fi
  done

  if [[ ! -f "${PROMPTS_DIR}/PLAN_CRITIC.md" || ! -f "${PROMPTS_DIR}/PLAN_PLANNER.md" ]]; then
    log_error "Missing prompt templates PLAN_CRITIC.md or PLAN_PLANNER.md in ${PROMPTS_DIR}."
    exit 1
  fi
}

run_turn() {
  local prompt="$1"
  local model_override="$2"
  local role_name="$3"
  local turn="$4"
  local out_log="${RUN_DIR}/turn-${turn}-${role_name}.log"
  local err_log="${RUN_DIR}/turn-${turn}-${role_name}.err"

  local runner_args=("--output" "$out_log" "--error" "$err_log" "--timeout" "$TIMEOUT")
  if [[ -n "$model_override" ]]; then
    runner_args+=("--model" "$model_override")
  fi

  log_info "⚡ [${role_name}] AI is running (Turn ${turn})..."
  set +e
  "${PIPELINE_DIR}/scripts/agent-runner.sh" "${runner_args[@]}" <<< "$prompt"
  local code=$?
  set -e

  if [[ $code -ne 0 ]]; then
    log_warn "[${role_name}] returned non-zero exit code: $code. Check $out_log."
  fi
  return $code
}

is_approved() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    return 1
  fi
  # Check last 30 lines of debate log or latest session output for approval keyword
  if tail -n 30 "$log_file" | grep -qE "^PLAN_REVIEW:[[:space:]]*APPROVED"; then
    return 0
  fi
  return 1
}

snapshot_context() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  for f in "${CONTEXT_DIR}"/*.md; do
    if [[ -f "$f" ]]; then
      cp -f "$f" "$target_dir/" 2>/dev/null || true
    fi
  done
}

diff_and_log_context() {
  local before_dir="$1"
  local turn_num="$2"
  local diff_file="${RUN_DIR}/turn-${turn_num}-changes.diff"
  local has_changes=false
  local diff_content=""
  local turn_diff_md=""

  # Initialize PLAN_DIFF_LOG header if not present
  if [[ ! -f "$PLAN_DIFF_LOG" ]]; then
    cat > "$PLAN_DIFF_LOG" <<EOF
# 📋 PLAN SPECIFICATION DIFF & CHANGELOG
> **Recorded by:** \`plan-refine.sh\` | **Run ID:** ${RUN_ID}
> *Tracks all modifications made to context files (\`Tasks_list.md\`, \`INTERVIEW_PLAN.md\`, etc.) across turns, independent of git.*

---
EOF
  fi

  log_section "CHANGELOG & DIFF INSPECTION (TURN ${turn_num})"

  # 1. Check all files currently in CONTEXT_DIR
  for f in "${CONTEXT_DIR}"/*.md; do
    [[ -f "$f" ]] || continue
    local fname="$(basename "$f")"
    local before_f="${before_dir}/${fname}"

    if [[ ! -f "$before_f" ]]; then
      has_changes=true
      local lines_added
      lines_added=$(wc -l < "$f" 2>/dev/null || echo 0)
      log_info "➕ [NEW FILE] ${fname} (+${lines_added} lines)"
      local file_diff
      file_diff="$(diff -u /dev/null "$f" 2>/dev/null || true)"
      diff_content+="${file_diff}"$'\n'
      turn_diff_md+=$'\n'"#### ➕ Created: \`${fname}\` (+${lines_added} lines)"$'\n'
      turn_diff_md+=$'```diff\n'"${file_diff}"$'\n```\n'
    elif ! cmp -s "$before_f" "$f"; then
      has_changes=true
      local file_diff
      file_diff="$(diff -u "$before_f" "$f" 2>/dev/null || true)"
      local added
      added=$(echo "$file_diff" | grep -c '^+' | grep -v '^+++' || echo 0)
      local removed
      removed=$(echo "$file_diff" | grep -c '^-' | grep -v '^---' || echo 0)
      log_info "📝 [MODIFIED] ${fname} (+${added} / -${removed} lines)"
      diff_content+="${file_diff}"$'\n'
      turn_diff_md+=$'\n'"#### 📝 Modified: \`${fname}\` (+${added} / -${removed} lines)"$'\n'
      turn_diff_md+=$'```diff\n'"${file_diff}"$'\n```\n'
    fi
  done

  # 2. Check if any file in before_dir was deleted
  for f in "${before_dir}"/*.md; do
    [[ -f "$f" ]] || continue
    local fname="$(basename "$f")"
    if [[ ! -f "${CONTEXT_DIR}/${fname}" ]]; then
      has_changes=true
      log_warn "🗑️ [DELETED] ${fname}"
      local file_diff
      file_diff="$(diff -u "$f" /dev/null 2>/dev/null || true)"
      diff_content+="${file_diff}"$'\n'
      turn_diff_md+=$'\n'"#### 🗑️ Deleted: \`${fname}\`"$'\n'
      turn_diff_md+=$'```diff\n'"${file_diff}"$'\n```\n'
    fi
  done

  if [[ "$has_changes" == true ]]; then
    # Write turn diff file
    echo "$diff_content" > "$diff_file"

    # Append to PLAN_DIFF_LOG
    cat >> "$PLAN_DIFF_LOG" <<EOF

## 🔄 Turn ${turn_num} — Planner Context Updates ($(date '+%Y-%m-%d %H:%M:%S'))
${turn_diff_md}
---
EOF

    # Append to DEBATE_LOG so Critic and User have full visibility in session history
    cat >> "$DEBATE_LOG" <<EOF

---
### 🔄 Context Specification Changes (Turn ${turn_num} Diff Summary)
${turn_diff_md}
---
EOF

    log_ok "Changes recorded to: ${PLAN_DIFF_LOG}"
  else
    log_info "No context file modifications detected in Turn ${turn_num}."
  fi
}

generate_cumulative_diff() {
  local initial_dir="$1"
  local summary_md=""
  local has_changes=false

  log_section "CUMULATIVE PLAN SPECIFICATION CHANGELOG"

  for f in "${CONTEXT_DIR}"/*.md; do
    [[ -f "$f" ]] || continue
    local fname="$(basename "$f")"
    local init_f="${initial_dir}/${fname}"

    if [[ ! -f "$init_f" ]]; then
      has_changes=true
      local lines_added
      lines_added=$(wc -l < "$f" 2>/dev/null || echo 0)
      summary_md+="- **${fname}**: ➕ Created (+${lines_added} lines)"$'\n'
      log_ok "  ➕ ${fname}: Created (+${lines_added} lines)"
    elif ! cmp -s "$init_f" "$f"; then
      has_changes=true
      local file_diff
      file_diff="$(diff -u "$init_f" "$f" 2>/dev/null || true)"
      local added
      added=$(echo "$file_diff" | grep -c '^+' | grep -v '^+++' || echo 0)
      local removed
      removed=$(echo "$file_diff" | grep -c '^-' | grep -v '^---' || echo 0)
      summary_md+="- **${fname}**: 📝 Modified (+${added} / -${removed} lines)"$'\n'
      log_ok "  📝 ${fname}: Modified (+${added} / -${removed} lines)"
    else
      summary_md+="- **${fname}**: ⏸️ Unchanged"$'\n'
      log_info "  ⏸️ ${fname}: Unchanged"
    fi
  done

  if [[ "$has_changes" == true ]]; then
    cat >> "$PLAN_DIFF_LOG" <<EOF

## 📊 Final Cumulative Summary (All Turns)
${summary_md}
EOF
    log_ok "Complete diff and history saved in: ${PLAN_DIFF_LOG}"
  fi
}

main() {
  parse_args "$@"
  preflight_check

  if [[ -n "$PROVIDER_OVERRIDE" ]]; then
    export AGENT_PROVIDER="$PROVIDER_OVERRIDE"
  fi

  RUN_ID="$(date +%Y%m%d-%H%M%S)"
  RUN_DIR="${PIPELINE_DIR}/.ralph/runs/plan-refine-${RUN_ID}"
  mkdir -p "$RUN_DIR"

  log_section "DUAL-MODEL PLAN REFINEMENT & INTERVIEW LOOP"
  log_info "Max Turns: ${MAX_TURNS} | Per-Turn Timeout: ${TIMEOUT}"
  log_info "Critic Model:  ${CRITIC_MODEL:-default provider model}"
  log_info "Planner Model: ${PLANNER_MODEL:-default provider model}"
  local interview_plan_path="${CONTEXT_DIR}/INTERVIEW_PLAN.md"
  local original_tasks_path="${CONTEXT_DIR}/Original_Tasks.md"
  log_info "User Interview Plan (Read First): ${interview_plan_path}"
  if [[ -f "$original_tasks_path" ]]; then
    log_info "Human Intent Anchor: ${original_tasks_path}"
  fi
  log_info "Debate History: ${DEBATE_LOG}"
  log_info "Changelog Diff: ${PLAN_DIFF_LOG}"

  # Capture initial context state before Turn 1
  INITIAL_SNAPSHOT="${RUN_DIR}/snapshot-initial"
  snapshot_context "${INITIAL_SNAPSHOT}"

  # Initialize DEBATE_LOG header if not present
  if [[ ! -f "$DEBATE_LOG" ]]; then
    cat > "$DEBATE_LOG" <<EOF
# 🎙️ PLAN DEBATE & ARCHITECTURAL INTERVIEW LOG
> **Session Started:** $(date '+%Y-%m-%d %H:%M:%S') | **Run ID:** ${RUN_ID}

This log records the multi-turn adversarial debate and refinement between Lead Architect (Critic) and System Architect (Planner) across two sequential phases:
1. Phase 1 (First Priority): Deep critique of the user's interview plan in INTERVIEW_PLAN.md (logic holes, edge cases, implicit assumptions).
2. Phase 2 (Technical Execution): Verification of execution breakdown in Tasks_list.md (atomic sizing, bottom-up dependencies, TDD test gates).

---
EOF
  fi

  local turn=0
  local approved=false

  while (( turn < MAX_TURNS )); do
    turn=$((turn + 1))
    log_section "TURN ${turn} / ${MAX_TURNS} — CRITIC REVIEW (PHASE 1: USER PLAN ➔ PHASE 2: TECH SPECS)"

    # 1. Step 1: CRITIC Turn
    local critic_template
    critic_template="$(cat "${PROMPTS_DIR}/PLAN_CRITIC.md")"
    local critic_prompt="$critic_template"
    critic_prompt="${critic_prompt//\{\{TURN\}\}/${turn}}"
    critic_prompt="${critic_prompt//\{\{MAX_TURNS\}\}/${MAX_TURNS}}"
    critic_prompt="${critic_prompt//\{\{DEBATE_LOG_PATH\}\}/${DEBATE_LOG}}"
    critic_prompt="${critic_prompt//\{\{INTERVIEW_PLAN_PATH\}\}/${interview_plan_path}}"
    critic_prompt="${critic_prompt//\{\{ORIGINAL_TASKS_PATH\}\}/${original_tasks_path}}"

    run_turn "$critic_prompt" "$CRITIC_MODEL" "CRITIC" "$turn" || true

    # Check if Critic approved
    if is_approved "$DEBATE_LOG" || is_approved "${RUN_DIR}/turn-${turn}-CRITIC.log"; then
      approved=true
      log_ok "🎉 [PLAN-REFINE] Plan has been 100% APPROVED by Lead Architect at Turn ${turn}!"
      break
    fi

    log_warn "Critic identified concerns or requested clarification. Proceeding to Planner response..."

    # 2. Step 2: PLANNER Turn
    log_section "TURN ${turn} / ${MAX_TURNS} — PLANNER REFINEMENT (INTERVIEW_PLAN.md & Tasks_list.md)"

    # Snapshot context before Planner modifications
    local turn_before_dir="${RUN_DIR}/snapshot-before-turn-${turn}"
    snapshot_context "${turn_before_dir}"

    local planner_template
    planner_template="$(cat "${PROMPTS_DIR}/PLAN_PLANNER.md")"
    local planner_prompt="$planner_template"
    planner_prompt="${planner_prompt//\{\{TURN\}\}/${turn}}"
    planner_prompt="${planner_prompt//\{\{MAX_TURNS\}\}/${MAX_TURNS}}"
    planner_prompt="${planner_prompt//\{\{DEBATE_LOG_PATH\}\}/${DEBATE_LOG}}"
    planner_prompt="${planner_prompt//\{\{INTERVIEW_PLAN_PATH\}\}/${interview_plan_path}}"
    planner_prompt="${planner_prompt//\{\{ORIGINAL_TASKS_PATH\}\}/${original_tasks_path}}"

    run_turn "$planner_prompt" "$PLANNER_MODEL" "PLANNER" "$turn" || true
    log_ok "Planner completed filesystem updates for Turn ${turn}."

    # Inspect, diff, and log all changes made by Planner in this turn
    diff_and_log_context "${turn_before_dir}" "${turn}"
  done

  # Generate consolidated session changelog
  generate_cumulative_diff "${INITIAL_SNAPSHOT}"

  if [[ "$approved" == true ]]; then
    log_section "FINALIZING APPROVED PLAN"

    # Check if git has changes in context (and git is not ignoring context)
    if git rev-parse --git-dir >/dev/null 2>&1; then
      if git check-ignore -q "${CONTEXT_DIR}" 2>/dev/null; then
        log_info "ℹ️ pipeline/ is in .gitignore; context diff is preserved in: ${PLAN_DIFF_LOG}"
      elif [[ -n "$(git status --porcelain "${CONTEXT_DIR}" 2>/dev/null)" ]]; then
        log_info "Committing finalized context specifications to git..."
        local commit_msg="docs(plan): finalize implementation plan via dual-model debate (turn ${turn})

## Summary
- Validated and refined task queue and architecture specifications through dual-model debate.
- Verified task dependencies and scaffolding readiness for autonomous execution.

## Verification
- Dual-model debate consensus reached (Turn ${turn}/${MAX_TURNS})
"
        if git add -A -- "${CONTEXT_DIR}" && git commit -m "$commit_msg" -- "${CONTEXT_DIR}"; then
          log_ok "Context cleanly committed to git."
        else
          log_warn "Notice: Could not commit context specifications to git (possibly ignored). Diff preserved in ${PLAN_DIFF_LOG}."
        fi
      fi
    fi

    # Auto-seal if requested
    if [[ "$AUTO_SEAL" == true ]]; then
      log_info "🔒 Sealing verified plan specifications..."
      "${PIPELINE_DIR}/scripts/plan.sh" seal
      log_ok "Plan sealed successfully! Ready for overnight autonomous loop (harness.sh)."
    fi
    exit 0
  else
    log_error "❌ Maximum debate turns (${MAX_TURNS}) reached without 100% approval."
    log_warn "Inspect ${DEBATE_LOG}, ${PLAN_DIFF_LOG}, and ${RUN_DIR} for outstanding feedback."
    exit 1
  fi
}

main "$@"
