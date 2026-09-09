#!/usr/bin/env bash
# RETRO — the LAST step after a Ralph loop. Two parts:
#   1. ANALYZE the run's stored logs for the tool errors the agent hit (deterministic).
#   2. IMPROVE: feed that report to the selected agent provider to improve the reusable setup/docs
#      so the recurring errors don't happen again, appends a LEARNINGS entry, and commits.
#
# Usage:  scripts/ralph-retro.sh [runDir]      (default: newest .ralph/runs/* , else .ralph)
# Env:    RALPH_RETRO_IMPROVE=0  -> analyze only (no agent, no commits)
#         AGENT_PROVIDER=<name>  -> claude, codex, or custom
#         RALPH_MODEL=<id>       -> optional provider model override
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 2
AGENT_RUNNER="$ROOT/scripts/agent-runner.sh"
BRANCH="$(git branch --show-current)"
[ -n "$BRANCH" ] || { echo "retro requires a named git branch" >&2; exit 2; }

RUN_DIR="${1:-$(ls -dt .ralph/runs/*/ 2>/dev/null | head -1)}"
RUN_DIR="${RUN_DIR:-.ralph}"; RUN_DIR="${RUN_DIR%/}"
[ -d "$RUN_DIR" ] || { echo "no logs at '$RUN_DIR' — run the loop first"; exit 1; }
REPORT="$RUN_DIR/analysis.md"

echo "→ analyzing tool errors in $RUN_DIR"
node "$ROOT/scripts/ralph-analyze.mjs" "$RUN_DIR" | tee "$REPORT"
echo

if grep -q '_none_' "$REPORT"; then echo "✓ no tool errors logged — nothing to improve."; exit 0; fi
if [ "${RALPH_RETRO_IMPROVE:-1}" != "1" ]; then
  echo "report saved: $REPORT  (set RALPH_RETRO_IMPROVE=1 to run the improvement agent)"; exit 0
fi

echo "→ running the improvement agent (${AGENT_PROVIDER:-claude}, model ${RALPH_MODEL:-default}) on the report…"
PROMPT="You are improving a Shopify theme migration agent toolkit by learning from its own run.
Below is a tool-error analysis from the latest autonomous loop. Identify the RECURRING or
SYSTEMIC tool errors (ignore one-off noise) and improve the REUSABLE setup so they don't recur:
edit the proper home per the source-of-truth routing — \`docs/*\`, \`AGENT_GUIDE.md\`, provider-specific rules,
or \`prompts/PROMPT.md\` (most reusable first) — and append ONE dated entry to
\`LEARNINGS.md\` summarizing what you changed and why. Then commit + push the current branch
\`$BRANCH\` with a detailed message. Do NOT run scripts/sync-theme-branch.sh (no live deploy). If nothing is systemic, make
no changes and say so.

--- TOOL-ERROR ANALYSIS ($RUN_DIR) ---
$(cat "$REPORT")"

[ -x "$AGENT_RUNNER" ] || { echo "provider runner missing: $AGENT_RUNNER" >&2; exit 2; }
printf '%s' "$PROMPT" | "$AGENT_RUNNER" --output "$RUN_DIR/retro.jsonl" --error "$RUN_DIR/retro.err" \
  --model "${RALPH_MODEL:-${AGENT_MODEL:-}}" --effort "${RALPH_EFFORT:-${AGENT_EFFORT:-high}}" --root "$ROOT"
echo "✓ retro complete — report: $REPORT"
