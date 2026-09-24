#!/usr/bin/env bash
# =============================================================================
# follow-up.sh — Operator Follow-up Request Runner (Harness Step 10)
# Handles post-completion change requests through identical verification gates.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQUEST="${1:-}"
if [[ -z "$REQUEST" ]]; then
  if [[ ! -t 0 ]]; then
    REQUEST="$(cat)"
  else
    echo "Usage: scripts/follow-up.sh "Your change request" or printf '...' | scripts/follow-up.sh"
    exit 1
  fi
fi

echo "🎯 [FOLLOW-UP] Received Operator Request: '$REQUEST'"
PROMPT_TEMPLATE="$ROOT/prompts/FOLLOW_UP.md"
PROMPT="$(cat "$PROMPT_TEMPLATE")"
PROMPT="${PROMPT//\{\{OPERATOR_REQUEST\}\}/${REQUEST}}"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$ROOT/.ralph/runs/follow-up-$RUN_ID"
mkdir -p "$RUN_DIR"

echo "⚡ [FOLLOW-UP] Executing change request with verification..."
"$ROOT/scripts/agent-runner.sh" --output "$RUN_DIR/session.log" <<< "$PROMPT"

echo "🧪 [FOLLOW-UP] Running Quality Verification..."
if python3 "$ROOT/scripts/verify.py"; then
  echo "✅ [FOLLOW-UP] Verification passed 100%."
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    git add -A
    file_changes=$(git diff --cached --name-status 2>/dev/null | head -n 12 | sed 's/^/- /')
    stat_summary=$(git diff --cached --stat 2>/dev/null | tail -1 | sed 's/^[ \t]*//')
    commit_msg=$(cat <<EOF
[FOLLOW-UP] feat: ${REQUEST}

## Summary
- Request: ${REQUEST}
- Verified clean implementation with zero regressions across codebase.

## Key Changes
${file_changes}
$([ -n "$stat_summary" ] && echo "(${stat_summary})")

## Verification
- Deterministic Quality Verification: PASS 100% (python3 pipeline/scripts/verify.py)
EOF
)
    git commit -m "$commit_msg"
    echo "✅ [FOLLOW-UP] Committed cleanly to git."
  fi
else
  echo "❌ [FOLLOW-UP] Verification failed. Inspect $RUN_DIR/session.log."
  exit 1
fi
