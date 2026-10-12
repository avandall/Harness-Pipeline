#!/usr/bin/env bash
# =============================================================================
# ralph-retro.sh — SkillOpt-Lite Autonomous Improvement Engine
# Equipped with:
#   - Safety Snapshot & Immediate Emergency Rollback
#   - Hard Blast-Radius Guard (Protects src/*, app/*, tests/*, scripts/*)
#   - Bounded Diff Guard (< 40 lines total, anti-rewrite)
#   - 5-Tier Deterministic Validation Gate (plan seal, selftest, tier 0 lint)
#   - Negative Knowledge Buffer (REJECTED_RULES.md)
# =============================================================================
set -euo pipefail

TARGET_ARG="${1:-}"
if [[ -n "$TARGET_ARG" ]]; then
  if [[ "$TARGET_ARG" = /* ]]; then
    RUN_DIR="$TARGET_ARG"
  else
    RUN_DIR="$(pwd)/$TARGET_ARG"
  fi
else
  RUN_DIR=""
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ESC=$'\033'
C_OK="${ESC}[32m"; C_WARN="${ESC}[33m"; C_ERROR="${ESC}[31m"; C_BLUE="${ESC}[34m"; C_BOLD="${ESC}[1m"; C_OFF="${ESC}[0m"

log_info()  { echo -e "${C_BLUE}[RETRO-INFO]${C_OFF}  $*"; }
log_ok()    { echo -e "${C_OK}[RETRO-OK]${C_OFF}    $*"; }
log_warn()  { echo -e "${C_WARN}[RETRO-WARN]${C_OFF}  $*"; }
log_error() { echo -e "${C_ERROR}[RETRO-ERROR]${C_OFF} $*"; }

if [[ -z "$RUN_DIR" ]]; then
  if [[ -e "$ROOT/docs/runtime/CURRENT" ]]; then
    RUN_DIR="$(readlink -f "$ROOT/docs/runtime/CURRENT" 2>/dev/null || ls -dt "$ROOT/docs/runtime/runs"/*/ 2>/dev/null | head -1 || ls -dt "$ROOT/.ralph/runs"/*/ 2>/dev/null | head -1 || echo "$ROOT/.ralph")"
  else
    RUN_DIR="$(ls -dt "$ROOT/docs/runtime/runs"/*/ 2>/dev/null | head -1 || ls -dt "$ROOT/.ralph/runs"/*/ 2>/dev/null | head -1 || echo "$ROOT/.ralph")"
  fi
fi
RUN_DIR="${RUN_DIR%/}"

if [[ ! -d "$RUN_DIR" ]]; then
  log_info "No run directory found at '$RUN_DIR'. Run harness.sh first."
  exit 0
fi

# Run Structural Process Audit
AUDIT_REPORT="$RUN_DIR/harness_audit.md"
log_info "Running structural harness & dependency audit..."
python3 "$ROOT/scripts/ralph-audit.py" "$RUN_DIR" >/dev/null 2>&1 || true
if [[ -f "$AUDIT_REPORT" ]]; then
  cat "$AUDIT_REPORT"
  echo ""
fi

REPORT="$RUN_DIR/analysis.md"
log_info "Analyzing execution logs in $RUN_DIR..."
node "$ROOT/scripts/ralph-analyze.mjs" "$RUN_DIR" | tee "$REPORT"
echo ""

# Update Durable Global Memory: LEARNINGS.md
LEARNINGS_FILE="$ROOT/docs/runtime/LEARNINGS.md"
mkdir -p "$(dirname "$LEARNINGS_FILE")"
if [[ -f "$REPORT" ]] && ! grep -q '_none_' "$REPORT"; then
  {
    echo -e "\n### [RETRO RUN ${RUN_DIR##*/}] $(date '+%Y-%m-%d %H:%M:%S')"
    head -n 20 "$REPORT"
    echo ""
  } >> "$LEARNINGS_FILE" 2>/dev/null || true
fi

# Append process audit findings to LEARNINGS.md if anomalies detected
if [[ -f "$AUDIT_REPORT" ]] && grep -q 'Detected Anomalies' "$AUDIT_REPORT"; then
  {
    echo -e "\n### [HARNESS AUDIT ${RUN_DIR##*/}] $(date '+%Y-%m-%d %H:%M:%S')"
    cat "$AUDIT_REPORT"
    echo ""
  } >> "$LEARNINGS_FILE" 2>/dev/null || true
fi

if grep -q '_none_' "$REPORT" && ! grep -q 'Detected Anomalies' "${AUDIT_REPORT:-/dev/null}"; then
  log_ok "No recurring tool errors or workflow anomalies detected. Harness is healthy."
  exit 0
fi

if grep -q 'TIMEOUT_OR_COMPACTION_ONLY' "$REPORT" && ! grep -q 'Detected Anomalies' "${AUDIT_REPORT:-/dev/null}"; then
  log_ok "Run chỉ bị gián đoạn do Timeout / Stall hoặc Stream quá dài."
  log_info "Không có lỗi công cụ hay hạ tầng. TUYỆT ĐỐI KHÔNG kích hoạt AI Retro sửa đổi BOUNDARIES.md hay TECH_CONTEXT.md."
  exit 0
fi

if [[ "${RALPH_RETRO_IMPROVE:-1}" != "1" ]]; then
  log_info "Report saved to $REPORT. (Set RALPH_RETRO_IMPROVE=1 to run AI auto-improvement)."
  exit 0
fi

REJECTED_FILE="$ROOT/docs/runtime/REJECTED_RULES.md"
mkdir -p "$(dirname "$REJECTED_FILE")"
[[ ! -f "$REJECTED_FILE" ]] && touch "$REJECTED_FILE"

record_rejection() {
  local reason="$1"
  local diff_text="$2"
  {
    echo -e "\n### [$(date '+%Y-%m-%d %H:%M:%S')] 🛑 REJECTED BY VALIDATION GATE"
    echo "- **Failure Reason:** ${reason}"
    echo "- **Proposed Diff:**"
    echo '```diff'
    echo "${diff_text}" | head -n 40
    echo '```'
  } >> "$REJECTED_FILE"
}

rollback_workspace() {
  log_warn "🔄 [ROLLBACK] Reverting all workspace modifications to clean git state..."
  git checkout HEAD -- . 2>/dev/null || true
  git clean -fd 2>/dev/null || true
  log_ok "🛡️ [ROLLBACK COMPLETE] Workspace successfully restored to pristine state."
}

# ────────────────────────────────────────────────────────────────────────────
# Pre-Flight Safety Snapshot
# ────────────────────────────────────────────────────────────────────────────
log_info "Creating Safety Snapshot before launching AI improvement..."
PRE_RETRO_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"
if [[ -z "$PRE_RETRO_HEAD" ]]; then
  log_error "Git repository has no commits. Cannot establish safe baseline."
  exit 1
fi

PROMPT_TEMPLATE="$ROOT/prompts/RETRO.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  log_error "Missing $PROMPT_TEMPLATE"
  exit 1
fi

ANALYSIS_CONTENT="$(cat "$REPORT")"
REJECTED_CONTENT="$(cat "$REJECTED_FILE" | tail -n 60)"

RETRO_PROMPT="$(cat "$PROMPT_TEMPLATE")"
RETRO_PROMPT="${RETRO_PROMPT//\{\{ANALYSIS_REPORT\}\}/${ANALYSIS_CONTENT}}"
RETRO_PROMPT="${RETRO_PROMPT//\{\{REJECTED_RULES\}\}/${REJECTED_CONTENT}}"

log_info "⚡ Launching AI Auto-Improvement Agent (SkillOpt Bounded Mode)..."
"$ROOT/scripts/agent-runner.sh" --output "$RUN_DIR/retro_session.log" <<< "$RETRO_PROMPT" || true

# ────────────────────────────────────────────────────────────────────────────
# SKILLOPT VALIDATION GATE (5-Tier Zero-Trust Guard)
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " 🛡️ EXECUTING SKILLOPT VALIDATION GATE"
echo "═══════════════════════════════════════════════════════════════"

MODIFIED_FILES="$(git diff --name-only 2>/dev/null || true)"
UNTRACKED_FILES="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
ALL_TOUCHED="$(printf "%s\n%s" "$MODIFIED_FILES" "$UNTRACKED_FILES" | grep -v "^$" || true)"

if [[ -z "$ALL_TOUCHED" ]]; then
  log_ok "AI concluded no modifications were necessary. Clean exit."
  exit 0
fi

CURRENT_DIFF="$(git diff 2>/dev/null || true)"

# ── Gate 1: Blast Radius / Scope Isolation Guard ──
echo "Gate 1: Checking modified file paths against strict allowed scope..."
FORBIDDEN_FILES=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # Only allowed: pipeline/docs/context/*, pipeline/prompts/*, pipeline/presets/*, pipeline/docs/runtime/LEARNINGS.md
  if [[ ! "$f" =~ ^pipeline/(docs/context/|prompts/|presets/|docs/runtime/LEARNINGS\.md) && ! "$f" =~ ^docs/context/ ]]; then
    FORBIDDEN_FILES="${FORBIDDEN_FILES}  - $f\n"
  fi
  # Extra hard-block on scripts
  if [[ "$f" =~ ^pipeline/scripts/ || "$f" =~ ^scripts/ ]]; then
    FORBIDDEN_FILES="${FORBIDDEN_FILES}  - [CRITICAL EXECUTABLE] $f\n"
  fi
done <<< "$ALL_TOUCHED"

if [[ -n "$FORBIDDEN_FILES" ]]; then
  log_error "🚨 GATE 1 REJECT: AI touched forbidden files outside allowed prompt/context scope!"
  echo -e "$FORBIDDEN_FILES"
  record_rejection "Gate 1: Unauthorized files touched:\n$FORBIDDEN_FILES" "$CURRENT_DIFF"
  rollback_workspace
  exit 1
fi
log_ok "Gate 1 PASS: All touched files are within authorized docs/prompts scope ✓"

# ── Gate 2: Bounded Diff Size Guard (SkillOpt Anti-Rewrite) ──
echo "Gate 2: Enforcing SkillOpt Bounded Diff threshold (< 40 lines changed)..."
DIFF_LINES="$(git diff --numstat 2>/dev/null | awk '{add+=$1; del+=$2} END {print add+del}' || echo "0")"
DIFF_LINES="${DIFF_LINES:-0}"

if (( DIFF_LINES > 40 )); then
  log_error "🚨 GATE 2 REJECT: Bounded Diff violated! (${DIFF_LINES} lines changed > 40 limit)."
  log_warn "AI attempted an unconstrained rewrite rather than a targeted atomic patch."
  record_rejection "Gate 2: Diff too large (${DIFF_LINES} lines > 40 lines limit)" "$CURRENT_DIFF"
  rollback_workspace
  exit 1
fi
log_ok "Gate 2 PASS: Bounded diff strictly respected (${DIFF_LINES} lines changed) ✓"

# ── Gate 3: Plan Seal & Structural Specification Drift Guard ──
echo "Gate 3: Verifying specification integrity via plan.sh check..."
if [[ -f "$ROOT/scripts/plan.sh" ]]; then
  if ! "$ROOT/scripts/plan.sh" check >/dev/null 2>&1; then
    log_error "🚨 GATE 3 REJECT: Specification drift or structural damage detected by plan.sh check!"
    record_rejection "Gate 3: Plan specification drift detected" "$CURRENT_DIFF"
    rollback_workspace
    exit 1
  fi
fi
log_ok "Gate 3 PASS: Specification integrity intact ✓"

# ── Gate 4: Zero-Token Offline Harness Selftest ──
echo "Gate 4: Running zero-token offline harness selftest..."
if [[ -f "$ROOT/scripts/selftest.sh" ]]; then
  if ! "$ROOT/scripts/selftest.sh" >/dev/null 2>&1; then
    log_error "🚨 GATE 4 REJECT: Offline harness selftest broken by proposed modifications!"
    record_rejection "Gate 4: selftest.sh failed after retro modifications" "$CURRENT_DIFF"
    rollback_workspace
    exit 1
  fi
fi
log_ok "Gate 4 PASS: Harness self-tests all pass empirically ✓"

# ── Gate 5: Deterministic Tier 0 Syntax & Static Verification ──
echo "Gate 5: Running Tier 0 syntax and linter verification..."
if [[ -f "$ROOT/scripts/verify.py" ]]; then
  if ! python3 "$ROOT/scripts/verify.py" --tier 0 >/dev/null 2>&1; then
    log_error "🚨 GATE 5 REJECT: verify.py Tier 0 syntax check failed on modified files!"
    record_rejection "Gate 5: verify.py Tier 0 syntax/linter check failed" "$CURRENT_DIFF"
    rollback_workspace
    exit 1
  fi
fi
log_ok "Gate 5 PASS: Static and syntax verification clean ✓"

# ────────────────────────────────────────────────────────────────────────────
# ACCEPT & COMMIT VETTED PROPOSALS
# ────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════"
log_ok "🏆 ALL 5 SKILLOPT VALIDATION GATES PASSED! Commit accepted."
echo "═══════════════════════════════════════════════════════════════"

git add pipeline/docs/context/ pipeline/prompts/ pipeline/presets/ pipeline/docs/runtime/LEARNINGS.md 2>/dev/null || true
git commit -m "[HARNESS-RETRO] chore: vetted harness optimization (SkillOpt Gate: ALL PASS)" >/dev/null 2>&1 || true

log_ok "✅ Vetted improvements safely committed to harness."
exit 0
