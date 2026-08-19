#!/usr/bin/env bash
# =============================================================================
# Root Convenience Wrapper for Enterprise Agent Pipeline Harness
# Executed via: ./harness.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/pipeline/docs/harness.sh" ]]; then
  exec "${SCRIPT_DIR}/pipeline/docs/harness.sh" "$@"
elif [[ -f "${SCRIPT_DIR}/H_docs/harness.sh" ]]; then
  exec "${SCRIPT_DIR}/H_docs/harness.sh" "$@"
else
  echo "❌ Error: Could not locate harness.sh in pipeline/docs or H_docs"
  exit 1
fi
