#!/usr/bin/env bash
# =============================================================================
# selftest.sh — Zero-Token Offline Test Suite (Harness Engineering Step 9)
# Validates state transitions, break signals, exit codes, and verify.py without API cost.
# =============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ESC=$'\033'; C_OK="${ESC}[32m"; C_WARN="${ESC}[33m"; C_ERROR="${ESC}[31m"; C_OFF="${ESC}[0m"
PASSED=0
FAILED=0

test_assert() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${C_OK}✓ PASS:${C_OFF} $name"
    ((PASSED++))
  else
    echo -e "  ${C_ERROR}✗ FAIL:${C_OFF} $name (Expected: $expected, Got: $actual)"
    ((FAILED++))
  fi
}

echo "═══════════════════════════════════════════════════════════════"
echo " 🧪 RUNNING ZERO-TOKEN OFFLINE HARNESS SELF-TEST"
echo "═══════════════════════════════════════════════════════════════"

# Test 1: verify.py execution
echo "Test 1: verify.py deterministic verification"
VERIFY_OUT="$(python3 "$ROOT/scripts/verify.py" --summary 2>&1)"
VERIFY_CODE=$?
test_assert "verify.py exit code 0" "0" "$VERIFY_CODE"

# Test 2: plan.sh sealing and checking
echo "Test 2: plan.sh seal & drift detection"
"$ROOT/scripts/plan.sh" seal >/dev/null 2>&1
CHECK_CODE=0
"$ROOT/scripts/plan.sh" check >/dev/null 2>&1 || CHECK_CODE=$?
test_assert "plan.sh check passes after seal" "0" "$CHECK_CODE"

# Test 3: Log Analyzer on empty/clean logs
echo "Test 3: ralph-analyze.mjs deterministic error analyzer"
ANALYSIS_OUT="$(node "$ROOT/scripts/ralph-analyze.mjs" "$ROOT/docs/runtime" 2>&1)"
ANALYSIS_CODE=$?
test_assert "ralph-analyze reports cleanly" "0" "$ANALYSIS_CODE"

# Test 4: Agent runner preflight check
echo "Test 4: agent-runner.sh check"
CHECK_OUT="$("$ROOT/scripts/agent-runner.sh" --check 2>&1)"
RUNNER_CODE=$?
test_assert "agent-runner detects available CLI" "0" "$RUNNER_CODE"

# Test 5: Discrete exit codes verification (Dry-run mode)
echo "Test 5: harness.sh dry-run capability"
DRY_RUN_OUT="$("$ROOT/scripts/harness.sh" --dry-run --max-iter 1 2>&1)"
DRY_CODE=$?
test_assert "harness.sh dry-run exits cleanly" "0" "$DRY_CODE"

# Test 6: Agent-log parsing & compaction detection
echo "Test 6: agent-log.mjs compaction and error extraction"
TEST_LOG_FILE="/tmp/test_agent_log.log"
echo "compact_boundary: context exhausted" > "$TEST_LOG_FILE"
COMPACT_CHECK="$(node "$ROOT/scripts/agent-log.mjs" "$TEST_LOG_FILE" 2>&1)"
test_assert "agent-log detects compaction" "true" "$([[ "$COMPACT_CHECK" == *'"compacted":true'* ]] && echo "true" || echo "false")"
rm -f "$TEST_LOG_FILE"

echo "═══════════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  echo -e " ${C_OK}ALL $PASSED SELF-TESTS PASSED EMPIRICALLY ✓${C_OFF}"
  exit 0
else
  echo -e " ${C_ERROR}SELF-TESTS FAILED: $FAILED failed, $PASSED passed.${C_OFF}"
  exit 1
fi
