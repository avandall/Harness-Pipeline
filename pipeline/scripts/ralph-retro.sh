#!/usr/bin/env bash
# =============================================================================
# ralph-retro.sh — Automated Self-Improvement Engine (Harness Step 10 & Tip 21)
# Analyzes stored run logs for recurring tool errors and prompts AI to improve docs/prompts.
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

if [[ -z "$RUN_DIR" ]]; then
  RUN_DIR="$(ls -dt "$ROOT/.ralph/runs"/*/ 2>/dev/null | head -1 || echo "$ROOT/.ralph")"
fi
RUN_DIR="${RUN_DIR%/}"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "No run directory found at '$RUN_DIR'. Run harness.sh first."
  exit 0
fi

REPORT="$RUN_DIR/analysis.md"
echo "🔍 [RETRO] Analyzing execution logs in $RUN_DIR..."
node "$ROOT/scripts/ralph-analyze.mjs" "$RUN_DIR" | tee "$REPORT"
echo ""

if grep -q '_none_' "$REPORT"; then
  echo "✅ [RETRO] No recurring tool errors detected. Harness is healthy."
  exit 0
fi

if grep -q 'TIMEOUT_OR_COMPACTION_ONLY' "$REPORT"; then
  echo "🛡️ [RETRO SAFEGUARD] Run chỉ bị gián đoạn do Timeout / Stall hoặc Stream quá dài."
  echo "🛡️ [RETRO SAFEGUARD] Không có lỗi công cụ hay hạ tầng. TUYỆT ĐỐI KHÔNG kích hoạt AI Retro sửa đổi BOUNDARIES.md hay TECH_CONTEXT.md."
  echo "💡 Khuyến nghị: Hãy kiểm tra kích thước task (sử dụng Complexity Guard) và gia hạn thời gian (Dynamic Budgeting)."
  exit 0
fi

if [[ "${RALPH_RETRO_IMPROVE:-1}" != "1" ]]; then
  echo "📄 [RETRO] Report saved to $REPORT. (Set RALPH_RETRO_IMPROVE=1 to run AI auto-improvement)."
  exit 0
fi

echo "⚡ [RETRO] Launching AI Auto-Improvement Agent on analysis report..."
PROMPT_TEMPLATE="$ROOT/prompts/RETRO.md"
if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Missing $PROMPT_TEMPLATE"
  exit 1
fi

ANALYSIS_CONTENT="$(cat "$REPORT")"
RETRO_PROMPT="$(cat "$PROMPT_TEMPLATE")"
RETRO_PROMPT="${RETRO_PROMPT//\{\{ANALYSIS_REPORT\}\}/${ANALYSIS_CONTENT}}"

"$ROOT/scripts/agent-runner.sh" --output "$RUN_DIR/retro_session.log" <<< "$RETRO_PROMPT" || true
echo "✅ [RETRO] Self-improvement pass complete."
