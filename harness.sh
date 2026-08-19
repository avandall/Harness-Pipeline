#!/usr/bin/env bash
# =============================================================================
# Root Convenience Wrapper for Enterprise Agent Pipeline Harness
# Executed via: ./harness.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/pipeline/scripts/harness.sh" ]]; then
  exec "${SCRIPT_DIR}/pipeline/scripts/harness.sh" "$@"
else
  echo "❌ Error: Could not locate harness.sh in pipeline/scripts/"
  exit 1
fi
