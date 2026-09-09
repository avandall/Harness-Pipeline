#!/usr/bin/env bash
# =============================================================================
# ralph-retro.sh — Automated Self-Improvement Engine (Harness Step 10 & Tip 21)
# Analyzes stored run logs for recurring tool errors and prompts AI to improve docs/prompts.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_DIR="${1:-$(ls -dt .ralph/runs/*/ 2>/dev/null | head -1 || echo ".ralph")}"
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
