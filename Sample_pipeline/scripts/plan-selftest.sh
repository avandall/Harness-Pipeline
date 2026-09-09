#!/usr/bin/env bash
# Offline regression tests for full-site discovery, per-page iteration, progress, and queue integrity.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

copy_runner() {
  local dir="$1"
  mkdir -p "$dir/scripts/visual-diff" "$dir/prompts" "$dir/migrations" "$dir/tests/fixtures"
  cp "$REPO/scripts/plan.sh" "$dir/scripts/plan.sh"
  cp "$REPO/scripts/agent-runner.sh" "$dir/scripts/agent-runner.sh"
  cp "$REPO/scripts/agent-format.mjs" "$dir/scripts/agent-format.mjs"
  cp "$REPO/scripts/agent-log.mjs" "$dir/scripts/agent-log.mjs"
  cp "$REPO/scripts/migration-state.mjs" "$dir/scripts/migration-state.mjs"
  cp "$REPO/scripts/env.mjs" "$dir/scripts/env.mjs"
  cp "$REPO/scripts/visual-diff/validate-assets.mjs" "$dir/scripts/visual-diff/validate-assets.mjs"
  cp "$REPO/scripts/visual-diff/validate-dynamics.mjs" "$dir/scripts/visual-diff/validate-dynamics.mjs"
  cp "$REPO/tests/fixtures/plan-agent-stub.sh" "$dir/stub.sh"
  cp "$REPO/tests/fixtures/write-gate.mjs" "$dir/tests/fixtures/write-gate.mjs"
  chmod +x "$dir/scripts/plan.sh" "$dir/scripts/agent-runner.sh" "$dir/stub.sh"
  printf 'test prompt\n' > "$dir/prompts/PLAN.md"
}

execution_mode_rejected_case() {
  local dir got; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/plan.sh --one-go https://source.example ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = 2 ] && grep -q 'usage: scripts/plan.sh' "$dir/out.log" && [ ! -e "$dir/.ralph/plan-order" ]; then
    printf '  PASS  MODE      — Execute-only --one-go is rejected by Plan\n'; pass=$((pass + 1))
  else
    report_failure MODE "$dir" "expected exit=2 with no agent invocation; got $got"
  fi
  rm -rf "$dir"
}

report_failure() {
  local name="$1" dir="$2" message="$3"
  printf '  FAIL  %-9s — %s\n' "$name" "$message"
  tail -16 "$dir/out.log" 2>/dev/null | sed 's/^/        | /'
  fail=$((fail + 1))
}

multi_site_case() {
  local dir got order; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x PLAN_MAX_ITERATIONS=10 bash scripts/plan.sh https://source.example ) >"$dir/out.log" 2>&1
  got=$?
  order="$(tr '\n' ' ' < "$dir/.ralph/plan-order" 2>/dev/null | sed 's/ $//')"
  if [ "$got" = 0 ] && [ "$order" = 'home about contact' ] \
    && ( cd "$dir" && node scripts/migration-state.mjs planned migrations >/dev/null ) \
    && grep -q '3 queued page(s)' "$dir/out.log"; then
    printf '  PASS  MULTI     — one Plan run discovered and validated home, about, contact\n'
    pass=$((pass + 1))
  else
    report_failure MULTI "$dir" "exit=$got order=\"$order\""
  fi
  rm -rf "$dir"
}

content_progress_case() {
  local dir got order; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env STUB_MODE=content_progress CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x PLAN_MAX_ITERATIONS=6 bash scripts/plan.sh --page https://source.example/ home ) >"$dir/out.log" 2>&1
  got=$?
  order="$(tr '\n' ' ' < "$dir/.ralph/plan-order" 2>/dev/null | sed 's/ $//')"
  if [ "$got" = 0 ] && [ "$order" = 'home home home' ] && grep -q 'advanced but is not valid yet' "$dir/out.log"; then
    printf '  PASS  CONTENT   — same-file edits count as progress and retry to validation\n'
    pass=$((pass + 1))
  else
    report_failure CONTENT "$dir" "exit=$got order=\"$order\""
  fi
  rm -rf "$dir"
}

reference_case() {
  local dir got order scope_source; dir="$(mktemp -d)"; copy_runner "$dir"
  mkdir -p "$dir/reference/build"
  printf '<main>home</main>\n' > "$dir/reference/build/index.html"
  printf '<main>about</main>\n' > "$dir/reference/build/about.html"
  mkdir -p "$dir/reference/build/legal"
  printf '<main>privacy</main>\n' > "$dir/reference/build/legal/privacy.html"
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x PLAN_MAX_ITERATIONS=6 bash scripts/plan.sh --from-reference build --url https://backup.example ) >"$dir/out.log" 2>&1
  got=$?
  order="$(tr '\n' ' ' < "$dir/.ralph/plan-order" 2>/dev/null | sed 's/ $//')"
  scope_source="$(node -e 'const s=require(process.argv[1]);process.stdout.write(s.source)' "$dir/migrations/_scope.json" 2>/dev/null)"
  if [ "$got" = 0 ] && [ "$order" = 'home about legal-privacy' ] && [ "$scope_source" = 'build|backup=https://backup.example' ] \
    && grep -q $'home\t__REF__/build/index.html' "$dir/migrations/_queue.tsv" \
    && grep -q $'legal-privacy\t__REF__/build/legal/privacy.html' "$dir/migrations/_queue.tsv"; then
    printf '  PASS  REFERENCE — deterministic recursive HTML queue + optional gap-fill URL\n'
    pass=$((pass + 1))
  else
    report_failure REFERENCE "$dir" "exit=$got order=\"$order\" scope=\"$scope_source\""
  fi
  rm -rf "$dir"
}

no_progress_case() {
  local dir got calls; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env STUB_MODE=no_progress CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x PLAN_NO_PROGRESS=3 PLAN_MAX_ITERATIONS=10 bash scripts/plan.sh --page https://source.example/ home ) >"$dir/out.log" 2>&1
  got=$?
  calls="$(wc -l < "$dir/.ralph/plan-order" | tr -d ' ')"
  if [ "$got" = 6 ] && [ "$calls" = 3 ] && grep -q 'no durable progress' "$dir/out.log"; then
    printf '  PASS  STUCK     — unchanged pack stops at the configured retry threshold\n'
    pass=$((pass + 1))
  else
    report_failure STUCK "$dir" "exit=$got calls=$calls"
  fi
  rm -rf "$dir"
}

signal_case() { # label expected stub-mode [ENV=VALUE...]
  local label="$1" expected="$2" mode="$3"; shift 3
  local dir got; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env STUB_MODE="$mode" CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x "$@" bash scripts/plan.sh --page https://source.example/ home ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = "$expected" ]; then
    printf '  PASS  %-9s — exit %s\n' "$label" "$got"; pass=$((pass + 1))
  else
    report_failure "$label" "$dir" "expected exit=$expected got=$got"
  fi
  rm -rf "$dir"
}

queue_mutation_case() {
  local dir got resumed; dir="$(mktemp -d)"; copy_runner "$dir"
  ( cd "$dir" && env STUB_MODE=mutate_queue CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x PLAN_MAX_ITERATIONS=10 bash scripts/plan.sh https://source.example ) >"$dir/out.log" 2>&1
  got=$?
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x bash scripts/plan.sh ) >"$dir/resume.log" 2>&1
  resumed=$?
  if [ "$got" = 2 ] && [ "$resumed" = 2 ] && grep -q 'route inventory' "$dir/out.log" \
    && grep -q 'sealed inventory' "$dir/resume.log"; then
    printf '  PASS  INVENTORY — a page agent cannot drop routes, even across resume\n'
    pass=$((pass + 1))
  else
    report_failure INVENTORY "$dir" "first exit=$got resume exit=$resumed"
    tail -10 "$dir/resume.log" 2>/dev/null | sed 's/^/        | resume: /'
  fi
  rm -rf "$dir"
}

printf 'plan.sh full-site orchestration self-test\n'
multi_site_case
execution_mode_rejected_case
content_progress_case
reference_case
no_progress_case
signal_case BLOCKED 3 blocked
signal_case CAP 4 no_progress PLAN_MAX_ITERATIONS=1 PLAN_NO_PROGRESS=10
signal_case BUDGET 5 costly PLAN_MAX_BUDGET_USD=5 PLAN_NO_PROGRESS=10
signal_case COMPACT 7 compacted
signal_case API-ERR 8 apierr PLAN_API_MAX=3 PLAN_API_BACKOFF=0 PLAN_NO_PROGRESS=10
signal_case PROVIDER 8 providerfail
queue_mutation_case

printf '\nresult: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
