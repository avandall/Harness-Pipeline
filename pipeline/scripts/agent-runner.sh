#!/usr/bin/env bash
# =============================================================================
# agent-runner.sh — Provider-Neutral Agent Runner Plug
# Supports: agy (default), claude, codex, custom
# =============================================================================
set -euo pipefail

PROVIDER="${AGENT_PROVIDER:-agy}"
OUTPUT_FILE=""
ERROR_FILE=""
MODEL=""
EFFORT="high"
ROOT_DIR="$(pwd)"
TIMEOUT="${PRINT_TIMEOUT:-15m0s}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      if [[ "$PROVIDER" == "agy" ]]; then
        if command -v agy >/dev/null 2>&1; then
          echo "agy ($(agy --version 2>/dev/null || echo 'installed'))"
          exit 0
        else
          echo "agy CLI not found in PATH" >&2
          exit 1
        fi
      elif [[ "$PROVIDER" == "claude" ]]; then
        if command -v claude >/dev/null 2>&1; then
          echo "claude ($(claude --version 2>/dev/null || echo 'installed'))"
          exit 0
        else
          echo "claude CLI not found in PATH" >&2
          exit 1
        fi
      elif [[ "$PROVIDER" == "codex" ]]; then
        echo "codex (configured)"
        exit 0
      else
        echo "custom provider: $PROVIDER"
        exit 0
      fi
      ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --error) ERROR_FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --root) ROOT_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

PROMPT_INPUT="$(cat)"

# Ensure target directory exists for output
if [[ -n "$OUTPUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi
if [[ -n "$ERROR_FILE" ]]; then
  mkdir -p "$(dirname "$ERROR_FILE")"
fi

case "$PROVIDER" in
  agy)
    MODEL_ARGS=()
    if [[ -n "$MODEL" ]]; then
      MODEL_ARGS=("--model" "$MODEL")
    fi
    if [[ -n "$OUTPUT_FILE" ]]; then
      agy "${MODEL_ARGS[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions --print-timeout "$TIMEOUT" 2>&1 | tee "$OUTPUT_FILE"
    else
      agy "${MODEL_ARGS[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions --print-timeout "$TIMEOUT"
    fi
    ;;
  claude)
    MODEL_ARGS=()
    if [[ -n "$MODEL" ]]; then
      MODEL_ARGS=("--model" "$MODEL")
    fi
    if [[ -n "$OUTPUT_FILE" ]]; then
      claude "${MODEL_ARGS[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions 2>&1 | tee "$OUTPUT_FILE"
    else
      claude "${MODEL_ARGS[@]}" -p "$PROMPT_INPUT" --dangerously-skip-permissions
    fi
    ;;
  codex)
    if [[ -n "$OUTPUT_FILE" ]]; then
      echo "$PROMPT_INPUT" | codex exec 2>&1 | tee "$OUTPUT_FILE"
    else
      echo "$PROMPT_INPUT" | codex exec
    fi
    ;;
  custom)
    if [[ -n "${AGENT_BIN:-}" ]]; then
      if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$PROMPT_INPUT" | $AGENT_BIN 2>&1 | tee "$OUTPUT_FILE"
      else
        echo "$PROMPT_INPUT" | $AGENT_BIN
      fi
    else
      echo "ERROR: AGENT_BIN not set for custom provider" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unknown provider: $PROVIDER" >&2
    exit 2
    ;;
esac
