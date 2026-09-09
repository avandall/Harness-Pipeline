#!/usr/bin/env bash
# End-to-end offline proof for both public Execute modes. The one-go case proves
# that Plan stays canonical while Execute uses exactly one provider invocation.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
loop_dir="$(mktemp -d)"
one_dir="$(mktemp -d)"
trap 'rm -rf "$loop_dir" "$one_dir"' EXIT

setup_repo() {
  local dir="$1"
  mkdir -p "$dir/scripts/visual-diff" "$dir/prompts" "$dir/migrations" "$dir/tests/fixtures"
  cp "$REPO/scripts/migrate.sh" "$dir/scripts/migrate.sh"
  cp "$REPO/scripts/plan.sh" "$dir/scripts/plan.sh"
  cp "$REPO/scripts/ralph.sh" "$dir/scripts/ralph.sh"
  cp "$REPO/scripts/agent-runner.sh" "$dir/scripts/agent-runner.sh"
  cp "$REPO/scripts/agent-format.mjs" "$dir/scripts/agent-format.mjs"
  cp "$REPO/scripts/agent-log.mjs" "$dir/scripts/agent-log.mjs"
  cp "$REPO/scripts/active-migration-page.mjs" "$dir/scripts/active-migration-page.mjs"
  cp "$REPO/scripts/migration-state.mjs" "$dir/scripts/migration-state.mjs"
  cp "$REPO/scripts/env.mjs" "$dir/scripts/env.mjs"
  cp "$REPO/scripts/visual-diff/validate-assets.mjs" "$dir/scripts/visual-diff/validate-assets.mjs"
  cp "$REPO/scripts/visual-diff/validate-dynamics.mjs" "$dir/scripts/visual-diff/validate-dynamics.mjs"
  cp "$REPO/tests/fixtures/plan-agent-stub.sh" "$dir/stub.sh"
  cp "$REPO/tests/fixtures/write-gate.mjs" "$dir/tests/fixtures/write-gate.mjs"
  chmod +x "$dir/scripts/migrate.sh" "$dir/scripts/plan.sh" "$dir/scripts/ralph.sh" "$dir/scripts/agent-runner.sh" "$dir/stub.sh"
  printf 'PLAN SELFTEST WORKER\n' > "$dir/prompts/PLAN.md"
  printf 'SELFTEST_EXECUTE_BASE_ONLY\n' > "$dir/prompts/PROMPT.md"
  printf 'SELFTEST_EXECUTE_ONE_GO_OVERLAY\n' > "$dir/prompts/IMPLEMENT_ALL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/scripts/sync-theme-branch.sh"
  chmod +x "$dir/scripts/sync-theme-branch.sh"
  printf '.ralph/\nout.log\nresume.log\n' > "$dir/.gitignore"
  ( cd "$dir" && git init -q && git config user.email test@example.com && git config user.name test && git add -A && git commit -qm init )
}

setup_repo "$loop_dir"
( cd "$loop_dir" && env CLAUDE_BIN="$loop_dir/stub.sh" CLAUDE_FLAGS=x PLAN_MAX_ITERATIONS=10 RALPH_MAX_ITERATIONS=10 bash scripts/migrate.sh https://source.example ) > "$loop_dir/out.log" 2>&1
loop_exit=$?
( cd "$loop_dir" && env CLAUDE_BIN="$loop_dir/stub.sh" CLAUDE_FLAGS=x bash scripts/migrate.sh --resume ) > "$loop_dir/resume.log" 2>&1
resume_exit=$?
loop_plan="$(tr '\n' ' ' < "$loop_dir/.ralph/plan-order" 2>/dev/null | sed 's/ $//')"
loop_execute="$(tr '\n' ' ' < "$loop_dir/.ralph/execute-order" 2>/dev/null | sed 's/ $//')"
loop_remaining="$(cd "$loop_dir" && node scripts/migration-state.mjs remaining migrations 2>/dev/null || printf error)"

setup_repo "$one_dir"
( cd "$one_dir" && env AGENT_PROVIDER=codex AGENT_BIN="$one_dir/stub.sh" AGENT_FLAGS=x bash scripts/migrate.sh --provider codex --one-go https://source.example ) > "$one_dir/out.log" 2>&1
one_exit=$?
( cd "$one_dir" && env AGENT_PROVIDER=codex AGENT_BIN="$one_dir/stub.sh" AGENT_FLAGS=x bash scripts/migrate.sh --provider codex --one-go --resume ) > "$one_dir/resume.log" 2>&1
one_resume_exit=$?
one_plan="$(tr '\n' ' ' < "$one_dir/.ralph/plan-order" 2>/dev/null | sed 's/ $//')"
one_execute="$(tr '\n' ' ' < "$one_dir/.ralph/execute-order" 2>/dev/null | sed 's/ $//')"
one_discovery_calls="$(wc -l < "$one_dir/.ralph/plan-calls" 2>/dev/null | tr -d ' ')"
one_execute_calls="$(wc -l < "$one_dir/.ralph/execute-invocations" 2>/dev/null | tr -d ' ')"
one_remaining="$(cd "$one_dir" && node scripts/migration-state.mjs remaining migrations 2>/dev/null || printf error)"

printf 'migrate.sh end-to-end multi-page self-test\n'
fail=0
if [ "$loop_exit" = 0 ] && [ "$resume_exit" = 0 ] && [ "$loop_plan" = 'home about contact' ] \
  && [ "$loop_execute" = 'home about contact' ] && [ "$loop_remaining" = 0 ] \
  && grep -q 'Full migration complete' "$loop_dir/out.log" && grep -q 'Full migration complete' "$loop_dir/resume.log"; then
  printf '  PASS  LOOP      — all pages completed in order; resume is idempotent\n'
else
  printf '  FAIL  LOOP      — exit=%s resume=%s plan="%s" execute="%s" remaining=%s\n' "$loop_exit" "$resume_exit" "$loop_plan" "$loop_execute" "$loop_remaining"
  tail -20 "$loop_dir/out.log" | sed 's/^/        | /'; fail=1
fi

if [ "$one_exit" = 0 ] && [ "$one_resume_exit" = 0 ] && [ "$one_discovery_calls" = 1 ] && [ "$one_execute_calls" = 1 ] \
  && [ "$one_plan" = 'home about contact' ] && [ "$one_execute" = 'home about contact' ] && [ "$one_remaining" = 0 ]; then
  printf '  PASS  ONE-GO    — Plan stayed page-looped; Execute completed in one invocation; resume added none\n'
else
  printf '  FAIL  ONE-GO    — exit=%s resume=%s discovery_calls=%s execute_calls=%s plan="%s" execute="%s" remaining=%s\n' "$one_exit" "$one_resume_exit" "$one_discovery_calls" "$one_execute_calls" "$one_plan" "$one_execute" "$one_remaining"
  tail -20 "$one_dir/out.log" | sed 's/^/        | /'; fail=1
fi

[ "$fail" = 0 ]
