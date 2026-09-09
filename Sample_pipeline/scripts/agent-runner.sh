#!/usr/bin/env bash
# Provider-neutral, non-interactive agent launcher.
#
# Reads one prompt from stdin, stores the provider's raw JSONL stream, and prints a
# human-readable stream. Orchestration scripts call only this file; provider CLI
# differences stay here.
#
# Common env:
#   AGENT_PROVIDER=claude|codex|custom   (default: claude)
#   AGENT_BIN=/path/to/cli               (optional override)
#   AGENT_FLAGS="..."                    (optional override; simple space-separated flags)
#   AGENT_UNATTENDED=1                   (dangerous; use only in an external sandbox/VM)
#
# Backward-compatible provider env:
#   CLAUDE_BIN / CLAUDE_FLAGS
#   CODEX_BIN  / CODEX_FLAGS
#
# GUI-launched panels often inherit a smaller PATH than an interactive terminal.
# When a bare command is not visible there, the runner also asks the user's login
# shell for its executable path. Explicit paths remain authoritative.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE=""
ERROR_FILE="/dev/null"
MODEL=""
EFFORT=""
WORK_ROOT="$ROOT"
FORMAT=1
CHECK_ONLY=0

usage() {
  cat >&2 <<'EOF'
usage: scripts/agent-runner.sh --output <jsonl> [--error <log>] [--model <id>] [--effort <level>] [--root <dir>] [--no-format]
       scripts/agent-runner.sh --check
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) [ "$#" -ge 2 ] || { usage; exit 2; }; OUTPUT_FILE="$2"; shift 2 ;;
    --error) [ "$#" -ge 2 ] || { usage; exit 2; }; ERROR_FILE="$2"; shift 2 ;;
    --model) [ "$#" -ge 2 ] || { usage; exit 2; }; MODEL="$2"; shift 2 ;;
    --effort) [ "$#" -ge 2 ] || { usage; exit 2; }; EFFORT="$2"; shift 2 ;;
    --root) [ "$#" -ge 2 ] || { usage; exit 2; }; WORK_ROOT="$2"; shift 2 ;;
    --no-format) FORMAT=0; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

PROVIDER="${AGENT_PROVIDER:-claude}"
FLAGS=""
case "$PROVIDER" in
  claude)
    BIN="${AGENT_BIN:-${CLAUDE_BIN:-claude}}"
    if [ -n "${AGENT_FLAGS+x}" ]; then
      FLAGS="$AGENT_FLAGS"
    elif [ -n "${CLAUDE_FLAGS+x}" ]; then
      FLAGS="$CLAUDE_FLAGS"
    elif [ "${AGENT_UNATTENDED:-0}" = "1" ]; then
      FLAGS="-p --output-format stream-json --verbose --dangerously-skip-permissions"
    else
      FLAGS="-p --output-format stream-json --verbose"
    fi
    [ -n "$MODEL" ] || MODEL="claude-opus-4-8[1m]"
    [ -n "$EFFORT" ] || EFFORT="high"
    ;;
  codex)
    BIN="${AGENT_BIN:-${CODEX_BIN:-codex}}"
    if [ -n "${AGENT_FLAGS+x}" ]; then
      FLAGS="$AGENT_FLAGS"
    elif [ -n "${CODEX_FLAGS+x}" ]; then
      FLAGS="$CODEX_FLAGS"
    elif [ "${AGENT_UNATTENDED:-0}" = "1" ]; then
      FLAGS="exec --json --ephemeral --dangerously-bypass-approvals-and-sandbox"
    else
      FLAGS="exec --json --ephemeral --sandbox workspace-write"
    fi
    [ -n "$EFFORT" ] || EFFORT="high"
    ;;
  custom)
    BIN="${AGENT_BIN:-}"
    FLAGS="${AGENT_FLAGS:-}"
    [ -n "$BIN" ] || { echo "[agent] AGENT_PROVIDER=custom requires AGENT_BIN" >&2; exit 2; }
    ;;
  *)
    echo "[agent] unsupported AGENT_PROVIDER '$PROVIDER' (expected claude, codex, or custom)" >&2
    exit 2
    ;;
esac

resolve_agent_bin() {
  local requested="$1" resolved="" login_shell="${SHELL:-/bin/sh}" candidate="" agent_user_home="${HOME:-}"

  # An explicit path is a deliberate override. Never silently replace a broken
  # override with some other installation of the same CLI.
  if [[ "$requested" == */* ]]; then
    [ -x "$requested" ] || return 1
    printf '%s\n' "$requested"
    return 0
  fi

  resolved="$(command -v -- "$requested" 2>/dev/null || true)"
  if [ -n "$resolved" ] && [ -x "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  # Desktop apps and IDE task runners commonly omit shell-managed paths (nvm,
  # Homebrew, extension CLIs, etc.). Resolve through the configured login shell,
  # passing the command as data so it cannot be interpreted as shell syntax.
  if [ -x "$login_shell" ]; then
    while IFS= read -r candidate; do
      [ -n "$candidate" ] && [ -x "$candidate" ] && resolved="$candidate"
    done < <(AGENT_LOOKUP_BIN="$requested" "$login_shell" -lic 'command -v -- "$AGENT_LOOKUP_BIN"' 2>/dev/null || true)
  fi

  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  # Also cover GUI environments whose login shell cannot reconstruct the IDE's
  # injected PATH. Prefer stable user/package-manager installs, then a matching
  # provider extension bundled by Cursor or VS Code.
  if [ -n "$agent_user_home" ]; then
    for candidate in \
      "$agent_user_home/.local/bin/$requested" \
      "$agent_user_home/.codex/bin/$requested" \
      "$agent_user_home/.bun/bin/$requested" \
      "$agent_user_home/.volta/bin/$requested" \
      "$agent_user_home/.asdf/shims/$requested" \
      "$agent_user_home/.local/share/mise/shims/$requested" \
      /opt/homebrew/bin/"$requested" \
      /usr/local/bin/"$requested"; do
      if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done

    resolved=""
    for candidate in "$agent_user_home"/.nvm/versions/node/*/bin/"$requested"; do
      [ -x "$candidate" ] && resolved="$candidate"
    done
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi

    resolved=""
    case "$PROVIDER" in
      codex)
        for candidate in \
          "$agent_user_home"/.cursor/extensions/openai.chatgpt-*/bin/*/codex \
          "$agent_user_home"/.vscode/extensions/openai.chatgpt-*/bin/*/codex \
          "$agent_user_home"/.vscode-insiders/extensions/openai.chatgpt-*/bin/*/codex; do
          [ -x "$candidate" ] && resolved="$candidate"
        done
        ;;
      claude)
        for candidate in \
          "$agent_user_home"/.cursor/extensions/anthropic.claude-code-*/resources/native-binary/claude \
          "$agent_user_home"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude \
          "$agent_user_home"/.vscode-insiders/extensions/anthropic.claude-code-*/resources/native-binary/claude; do
          [ -x "$candidate" ] && resolved="$candidate"
        done
        ;;
    esac
  fi

  [ -n "$resolved" ] || return 1
  printf '%s\n' "$resolved"
}

REQUESTED_BIN="$BIN"
BIN="$(resolve_agent_bin "$REQUESTED_BIN")" || {
  case "$PROVIDER" in
    claude) hint="Set CLAUDE_BIN to the absolute path printed by: command -v claude" ;;
    codex) hint="Install Codex or set CODEX_BIN to the absolute path printed by: command -v codex" ;;
    *) hint="Set AGENT_BIN to an absolute executable path" ;;
  esac
  echo "[agent] '$REQUESTED_BIN' not found for provider '$PROVIDER'. $hint." >&2
  exit 2
}
# Keep sibling runtimes/helpers visible too (notably `node` beside an nvm-installed
# npm CLI). This matters when the executable itself was absent from the panel PATH.
BIN_DIR="$(cd "$(dirname "$BIN")" 2>/dev/null && pwd)"
case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *) export PATH="$BIN_DIR${PATH:+:$PATH}" ;;
esac
if [ "$CHECK_ONLY" = "1" ]; then
  printf '%s\t%s\n' "$PROVIDER" "$BIN"
  exit 0
fi
[ -n "$OUTPUT_FILE" ] || { usage; exit 2; }

mkdir -p "$(dirname "$OUTPUT_FILE")" "$(dirname "$ERROR_FILE")"

cmd=("$BIN")
if [ -n "$FLAGS" ]; then
  # Deliberately matches the old CLAUDE_FLAGS behavior. Keep flags simple; use a
  # provider profile/config file when a value itself must contain whitespace.
  read -r -a flag_parts <<< "$FLAGS"
  cmd+=("${flag_parts[@]}")
fi

case "$PROVIDER" in
  claude)
    [ -z "$MODEL" ] || cmd+=(--model "$MODEL")
    [ -z "$EFFORT" ] || cmd+=(--effort "$EFFORT")
    ;;
  codex)
    [ -z "$MODEL" ] || cmd+=(--model "$MODEL")
    [ -z "$EFFORT" ] || cmd+=(-c "model_reasoning_effort=$EFFORT")
    cmd+=(-C "$WORK_ROOT" -)
    ;;
  custom)
    export AGENT_SELECTED_MODEL="$MODEL"
    export AGENT_SELECTED_EFFORT="$EFFORT"
    ;;
esac

if [ "$FORMAT" = "1" ] && [ -f "$ROOT/scripts/agent-format.mjs" ]; then
  "${cmd[@]}" 2>>"$ERROR_FILE" | tee "$OUTPUT_FILE" | node "$ROOT/scripts/agent-format.mjs" "$PROVIDER"
  status="${PIPESTATUS[0]}"
else
  "${cmd[@]}" 2>>"$ERROR_FILE" | tee "$OUTPUT_FILE"
  status="${PIPESTATUS[0]}"
fi

if [ "$status" -ne 0 ]; then
  printf '{"type":"agent_runner.failed","provider":"%s","exit_code":%s}\n' "$PROVIDER" "$status" >> "$OUTPUT_FILE"
  printf '[agent] %s exited with status %s\n' "$PROVIDER" "$status" >&2
fi

exit "$status"
