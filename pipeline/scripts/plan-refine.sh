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

  for f in "${CONTEXT_DIR}/PROJECT_BRIEF.md" "${CONTEXT_DIR}/Tasks_list.md" "${CONTEXT_DIR}/BOUNDARIES.md" "${CONTEXT_DIR}/TECH_CONTEXT.md"; do
    if [[ ! -f "$f" ]]; then
      log_error "Missing context file: $f. Please initialize context first."
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
  log_info "Debate History: ${DEBATE_LOG}"

  # Initialize DEBATE_LOG header if not present
  if [[ ! -f "$DEBATE_LOG" ]]; then
    cat > "$DEBATE_LOG" <<EOF
# 🎙️ PLAN DEBATE & ARCHITECTURAL INTERVIEW LOG
> **Session Started:** $(date '+%Y-%m-%d %H:%M:%S') | **Run ID:** ${RUN_ID}

This log records the multi-turn adversarial debate and refinement between Lead Architect (Critic) and System Architect (Planner) to formalize context and specifications.

---
EOF
  fi

  local turn=0
  local approved=false

  while (( turn < MAX_TURNS )); do
    ((turn++))
    log_section "TURN ${turn} / ${MAX_TURNS} — CRITIC REVIEW & ADVERSARIAL INTERVIEW"

    # 1. Step 1: CRITIC Turn
    local critic_template
    critic_template="$(cat "${PROMPTS_DIR}/PLAN_CRITIC.md")"
    local critic_prompt="$critic_template"
    critic_prompt="${critic_prompt//\{\{TURN\}\}/${turn}}"
    critic_prompt="${critic_prompt//\{\{MAX_TURNS\}\}/${MAX_TURNS}}"
    critic_prompt="${critic_prompt//\{\{DEBATE_LOG_PATH\}\}/${DEBATE_LOG}}"

    run_turn "$critic_prompt" "$CRITIC_MODEL" "CRITIC" "$turn" || true

    # Check if Critic approved
    if is_approved "$DEBATE_LOG" || is_approved "${RUN_DIR}/turn-${turn}-CRITIC.log"; then
      approved=true
      log_ok "🎉 [PLAN-REFINE] Plan has been 100% APPROVED by Lead Architect at Turn ${turn}!"
      break
    fi

    log_warn "Critic identified concerns or requested clarification. Proceeding to Planner response..."

    # 2. Step 2: PLANNER Turn
    log_section "TURN ${turn} / ${MAX_TURNS} — PLANNER SPECIFICATION REFINEMENT"
    local planner_template
    planner_template="$(cat "${PROMPTS_DIR}/PLAN_PLANNER.md")"
    local planner_prompt="$planner_template"
    planner_prompt="${planner_prompt//\{\{TURN\}\}/${turn}}"
    planner_prompt="${planner_prompt//\{\{MAX_TURNS\}\}/${MAX_TURNS}}"
    planner_prompt="${planner_prompt//\{\{DEBATE_LOG_PATH\}\}/${DEBATE_LOG}}"

    run_turn "$planner_prompt" "$PLANNER_MODEL" "PLANNER" "$turn" || true
    log_ok "Planner completed filesystem updates for Turn ${turn}."
  done

  if [[ "$approved" == true ]]; then
    log_section "FINALIZING APPROVED PLAN"

    # Check if git has changes in context
    if git rev-parse --git-dir >/dev/null 2>&1; then
      if [[ -n "$(git status --porcelain "${CONTEXT_DIR}" 2>/dev/null)" ]]; then
        log_info "Committing finalized context specifications to git..."
        git add "${CONTEXT_DIR}"
        git commit -m "docs(plan): finalize implementation plan via dual-model debate (turn ${turn})" || true
        log_ok "Context cleanly committed to git."
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
    log_warn "Inspect ${DEBATE_LOG} and ${RUN_DIR} for outstanding feedback."
    exit 1
  fi
}

main "$@"
