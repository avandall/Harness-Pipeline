#!/usr/bin/env bash
# Offline contract tests for provider argument mapping, prompt transport, JSONL
# normalization, and the custom-provider escape hatch.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$ROOT/tests/fixtures/agent-cli-stub.sh"
runner="$ROOT/scripts/agent-runner.sh"
pass=0; fail=0

check() {
  local label="$1"; shift
  if "$@"; then printf '  PASS  %s\n' "$label"; pass=$((pass + 1)); else printf '  FAIL  %s\n' "$label"; fail=$((fail + 1)); fi
}

invoke() {
  local provider="$1" stream="$2" prompt="$3"; shift 3
  : > "$tmp/args"; : > "$tmp/env"; : > "$tmp/prompt"
  printf '%s' "$prompt" | env AGENT_PROVIDER="$provider" AGENT_BIN="$stub" AGENT_FLAGS="${TEST_FLAGS:-}" \
    STUB_STREAM="$stream" STUB_ARGS_FILE="$tmp/args" STUB_ENV_FILE="$tmp/env" STUB_PROMPT_FILE="$tmp/prompt" \
    "$runner" --output "$tmp/$provider.jsonl" --error "$tmp/$provider.err" --model test-model --effort xhigh --root "$ROOT" --no-format "$@"
}

printf 'agent provider adapter self-test\n'

TEST_FLAGS='--claude-json'; export TEST_FLAGS
invoke claude claude 'claude prompt'
claude_exit=$?
check 'CLAUDE ARGS — flags/model/effort mapped' sh -c "[ '$claude_exit' = 0 ] && grep -Fx -- '--claude-json' '$tmp/args' >/dev/null && grep -Fx -- '--model' '$tmp/args' >/dev/null && grep -Fx -- 'test-model' '$tmp/args' >/dev/null && grep -Fx -- '--effort' '$tmp/args' >/dev/null && [ \"\$(cat '$tmp/prompt')\" = 'claude prompt' ]"

TEST_FLAGS='exec --json --ephemeral --sandbox workspace-write'; export TEST_FLAGS
invoke codex codex 'codex prompt'
codex_exit=$?
check 'CODEX ARGS  — exec/JSON/root/stdin mapped' sh -c "[ '$codex_exit' = 0 ] && grep -Fx -- 'exec' '$tmp/args' >/dev/null && grep -Fx -- '--json' '$tmp/args' >/dev/null && grep -Fx -- '-C' '$tmp/args' >/dev/null && grep -Fx -- '$ROOT' '$tmp/args' >/dev/null && [ \"\$(tail -n1 '$tmp/args')\" = '-' ] && [ \"\$(cat '$tmp/prompt')\" = 'codex prompt' ]"

: > "$tmp/args"; : > "$tmp/env"; : > "$tmp/prompt"
printf '%s' 'login-shell prompt' | env PATH=/usr/bin:/bin SHELL="$ROOT/tests/fixtures/login-shell-stub.sh" \
  LOGIN_SHELL_BIN="$stub" AGENT_PROVIDER=codex CODEX_BIN=codex-outside-panel-path AGENT_FLAGS='exec --json' \
  STUB_STREAM=codex STUB_ARGS_FILE="$tmp/args" STUB_ENV_FILE="$tmp/env" STUB_PROMPT_FILE="$tmp/prompt" \
  "$runner" --output "$tmp/login-shell.jsonl" --error "$tmp/login-shell.err" --root "$ROOT" --no-format
login_shell_exit=$?
check 'PATH FALLBACK — login shell resolves a GUI-hidden CLI' sh -c "[ '$login_shell_exit' = 0 ] && [ \"\$(cat '$tmp/prompt')\" = 'login-shell prompt' ]"

mkdir -p "$tmp/gui-home/.cursor/extensions/openai.chatgpt-test/bin/test-arch"
ln -s "$stub" "$tmp/gui-home/.cursor/extensions/openai.chatgpt-test/bin/test-arch/codex"
: > "$tmp/args"; : > "$tmp/env"; : > "$tmp/prompt"
printf '%s' 'ide-extension prompt' | env HOME="$tmp/gui-home" PATH=/usr/bin:/bin SHELL=/missing-shell \
  AGENT_PROVIDER=codex AGENT_FLAGS='exec --json' STUB_STREAM=codex STUB_ARGS_FILE="$tmp/args" \
  STUB_ENV_FILE="$tmp/env" STUB_PROMPT_FILE="$tmp/prompt" \
  "$runner" --output "$tmp/ide-extension.jsonl" --error "$tmp/ide-extension.err" --root "$ROOT" --no-format
ide_extension_exit=$?
check 'PATH FALLBACK — IDE-bundled Codex resolves outside panel PATH' sh -c "[ '$ide_extension_exit' = 0 ] && [ \"\$(cat '$tmp/prompt')\" = 'ide-extension prompt' ]"

TEST_FLAGS='--vendor-mode'; export TEST_FLAGS
invoke custom codex 'custom prompt'
custom_exit=$?
check 'CUSTOM      — generic binary + model env works' sh -c "[ '$custom_exit' = 0 ] && grep -Fx -- '--vendor-mode' '$tmp/args' >/dev/null && [ \"\$(cat '$tmp/env')\" = $'test-model\\txhigh' ] && [ \"\$(cat '$tmp/prompt')\" = 'custom prompt' ]"

TEST_FLAGS='exec --json'; export TEST_FLAGS
invoke codex nonzero 'failure prompt'
nonzero_exit=$?
nonzero_summary="$(node "$ROOT/scripts/agent-log.mjs" "$tmp/codex.jsonl")"
check 'FAILURE     — non-zero provider exit is preserved' node -e 'const [code,json]=process.argv.slice(1);const s=JSON.parse(json);process.exit(code==="9"&&s.failed?0:1)' "$nonzero_exit" "$nonzero_summary"

claude_summary="$(node "$ROOT/scripts/agent-log.mjs" "$tmp/claude.jsonl")"
TEST_FLAGS='exec --json --ephemeral --sandbox workspace-write'; export TEST_FLAGS
invoke codex codex 'codex usage prompt'
codex_summary="$(node "$ROOT/scripts/agent-log.mjs" "$tmp/codex.jsonl")"
check 'USAGE       — Claude cost/cache/tokens normalized' node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.costUsd===1.25&&s.tokens===16?0:1)' "$claude_summary"
check 'USAGE       — Codex tokens normalized' node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.costUsd===null&&s.tokens===15?0:1)' "$codex_summary"
check 'CLASSIFY    — allowed rate event is not retryable' node -e 'const s=JSON.parse(process.argv[1]);process.exit(!s.retryableApiError?0:1)' "$claude_summary"
check 'CLASSIFY    — tool text is not compaction' node -e 'const s=JSON.parse(process.argv[1]);process.exit(!s.compacted?0:1)' "$claude_summary"

TEST_FLAGS='exec --json'; export TEST_FLAGS
invoke codex error 'structured provider failure'
error_summary="$(node "$ROOT/scripts/agent-log.mjs" "$tmp/codex.jsonl")"
check 'CLASSIFY    — structured 503 is retryable + failed' node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.failed&&s.retryableApiError?0:1)' "$error_summary"

printf '%s\n' '{"type":"system","subtype":"compact_boundary"}' > "$tmp/compacted.jsonl"
compacted_summary="$(node "$ROOT/scripts/agent-log.mjs" "$tmp/compacted.jsonl")"
check 'CLASSIFY    — structured compact boundary detected' node -e 'const s=JSON.parse(process.argv[1]);process.exit(s.compacted?0:1)' "$compacted_summary"

printf '\nresult: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
