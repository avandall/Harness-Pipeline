#!/usr/bin/env bash
# Offline regression tests for Ralph's queue, page advancement, and exit conditions.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0

copy_runner() {
  local dir="$1"
  mkdir -p "$dir/scripts/visual-diff" "$dir/prompts" "$dir/migrations" "$dir/tests/fixtures"
  cp "$REPO/scripts/ralph.sh" "$dir/scripts/ralph.sh"
  cp "$REPO/scripts/agent-runner.sh" "$dir/scripts/agent-runner.sh"
  cp "$REPO/scripts/agent-format.mjs" "$dir/scripts/agent-format.mjs"
  cp "$REPO/scripts/agent-log.mjs" "$dir/scripts/agent-log.mjs"
  cp "$REPO/scripts/active-migration-page.mjs" "$dir/scripts/active-migration-page.mjs"
  cp "$REPO/scripts/migration-state.mjs" "$dir/scripts/migration-state.mjs"
  cp "$REPO/scripts/env.mjs" "$dir/scripts/env.mjs"
  cp "$REPO/scripts/visual-diff/validate-assets.mjs" "$dir/scripts/visual-diff/validate-assets.mjs"
  cp "$REPO/scripts/visual-diff/validate-dynamics.mjs" "$dir/scripts/visual-diff/validate-dynamics.mjs"
  cp "$REPO/tests/fixtures/write-gate.mjs" "$dir/tests/fixtures/write-gate.mjs"
  chmod +x "$dir/scripts/ralph.sh" "$dir/scripts/agent-runner.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/scripts/sync-theme-branch.sh"
  chmod +x "$dir/scripts/sync-theme-branch.sh"
  printf 'SELFTEST_EXECUTE_BASE_ONLY\n' > "$dir/prompts/PROMPT.md"
  printf 'SELFTEST_EXECUTE_ONE_GO_OVERLAY\n' > "$dir/prompts/IMPLEMENT_ALL.md"
  printf '.ralph/\n' > "$dir/.gitignore"
}

one_go_case() {
  local dir got order calls; dir="$(mktemp -d)"; copy_runner "$dir"
  printf 'home\thttps://source.example/\nabout\thttps://source.example/about\ncontact\thttps://source.example/contact\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" home 0 0; write_pack "$dir" about 0 0; write_pack "$dir" contact 0 0
  init_repo "$dir"
  cp "$REPO/tests/fixtures/plan-agent-stub.sh" "$dir/stub.sh"; chmod +x "$dir/stub.sh"
  ( cd "$dir" && env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/ralph.sh --one-go ) >"$dir/out.log" 2>&1
  got=$?; order="$(tr '\n' ' ' < "$dir/.ralph/execute-order" 2>/dev/null | sed 's/ $//')"
  calls="$(wc -l < "$dir/.ralph/execute-invocations" 2>/dev/null | tr -d ' ')"
  if [ "$got" = 0 ] && [ "$calls" = 1 ] && [ "$order" = 'home about contact' ] \
    && [ "$(cd "$dir" && node scripts/migration-state.mjs remaining migrations)" = 0 ] \
    && grep -q 'one implementation invocation' "$dir/out.log"; then
    printf '  PASS  ONE-GO   — Codex adapter gated every page in exactly one invocation\n'; pass=$((pass + 1))
  else
    printf '  FAIL  ONE-GO   — exit=%s calls=%s order="%s"\n' "$got" "$calls" "$order"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir"
}

one_go_partial_case() {
  local dir got order calls; dir="$(mktemp -d)"; copy_runner "$dir"
  printf 'home\thttps://source.example/\nabout\thttps://source.example/about\ncontact\thttps://source.example/contact\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" home 0 0; write_pack "$dir" about 0 0; write_pack "$dir" contact 0 0
  init_repo "$dir"
  cp "$REPO/tests/fixtures/plan-agent-stub.sh" "$dir/stub.sh"; chmod +x "$dir/stub.sh"
  ( cd "$dir" && env STUB_MODE=one_go_incomplete AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/ralph.sh --one-go ) >"$dir/out.log" 2>&1
  got=$?; order="$(tr '\n' ' ' < "$dir/.ralph/execute-order" 2>/dev/null | sed 's/ $//')"
  calls="$(wc -l < "$dir/.ralph/execute-invocations" 2>/dev/null | tr -d ' ')"
  if [ "$got" = 6 ] && [ "$calls" = 1 ] && [ "$order" = home ] \
    && [ "$(cd "$dir" && node scripts/migration-state.mjs remaining migrations)" -gt 0 ] \
    && grep -q 'ended before the full queue passed' "$dir/out.log"; then
    printf '  PASS  PARTIAL  — stopping after home fails without starting another invocation\n'; pass=$((pass + 1))
  else
    printf '  FAIL  PARTIAL  — exit=%s calls=%s order="%s"\n' "$got" "$calls" "$order"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir"
}

one_go_inventory_case() {
  local dir got order calls; dir="$(mktemp -d)"; copy_runner "$dir"
  printf 'home\thttps://source.example/\nabout\thttps://source.example/about\ncontact\thttps://source.example/contact\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" home 0 0; write_pack "$dir" about 0 0; write_pack "$dir" contact 0 0
  init_repo "$dir"
  cp "$REPO/tests/fixtures/plan-agent-stub.sh" "$dir/stub.sh"; chmod +x "$dir/stub.sh"
  ( cd "$dir" && env STUB_MODE=one_go_mutate_inventory AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/ralph.sh --one-go ) >"$dir/out.log" 2>&1
  got=$?; order="$(tr '\n' ' ' < "$dir/.ralph/execute-order" 2>/dev/null | sed 's/ $//')"
  calls="$(wc -l < "$dir/.ralph/execute-invocations" 2>/dev/null | tr -d ' ')"
  if [ "$got" = 2 ] && [ "$calls" = 1 ] && [ "$order" = home ] \
    && grep -q 'sealed route inventory changed during one-go Execute' "$dir/out.log"; then
    printf '  PASS  INVENTORY— shrinking the queue cannot manufacture one-go success\n'; pass=$((pass + 1))
  else
    printf '  FAIL  INVENTORY— exit=%s calls=%s order="%s"\n' "$got" "$calls" "$order"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir"
}

write_pack() { # dir page unchecked-boxes gated(0|1)
  local root="$1" page="$2" boxes="$3" gated="$4" dir
  dir="$root/migrations/$page"
  mkdir -p "$dir/reports"
  node - "$dir/contract.json" "$page" <<'NODE'
const fs=require('fs');const [file,page]=process.argv.slice(2);
const source=page==='home'?'https://source.example/':`https://source.example/${page}`;
fs.writeFileSync(file,JSON.stringify({page,source,preview:`https://preview.example/${page}`,viewports:{desktop:1440},sections:[{key:'main',class:'content',sourceSelector:'main',replicaSelector:"[data-section-key='main']",mustMatch:['geometry'],targets:{desktop:{box:{x:0,y:0,w:1440,h:800},styles:{display:'block'}}}}]},null,2)+'\n');
NODE
  node - "$dir" "$page" <<'NODE'
const fs=require('fs'),path=require('path'),crypto=require('crypto');const [dir,page]=process.argv.slice(2);const contractHash=crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,'contract.json'))).digest('hex');fs.writeFileSync(path.join(dir,'assets.json'),JSON.stringify({page,contractHash,assetPass:true,assets:[]})+'\n');fs.writeFileSync(path.join(dir,'dynamics.json'),JSON.stringify({page,contractHash,dynamicsPass:true,mustClassify:[]})+'\n');
NODE
  printf '# interactions\n' > "$dir/interactions.md"
  {
    printf '# visual deltas\n'
    i=1; while [ "$i" -le "$boxes" ]; do printf -- '- [ ] delta %s\n' "$i"; i=$((i + 1)); done
  } > "$dir/visual-deltas.md"
  if [ "$gated" = 1 ]; then
    printf 'gate complete\n' > "$dir/reports/final.md"
    printf 'visual verify complete\n' > "$dir/reports/visual-verify.md"
    ( cd "$root" && node tests/fixtures/write-gate.mjs "migrations/$page" )
  fi
}

init_repo() {
  local dir="$1"
  ( cd "$dir" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -qm init )
}

make_repo() { # unchecked boxes
  local boxes="$1" dir; dir="$(mktemp -d)"
  copy_runner "$dir"
  printf 'test-page\thttps://source.example/test-page\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" test-page "$boxes" 1
  init_repo "$dir"
  printf '%s' "$dir"
}

write_stub() { # path kind
  local file="$1" kind="$2"
  case "$kind" in
    progress)
      node - "$file" <<'NODE'
const fs=require('fs');fs.writeFileSync(process.argv[2],`#!/usr/bin/env bash
node -e 'const f=process.argv[1],s=require("fs");s.writeFileSync(f,s.readFileSync(f,"utf8").replace("- [ ]","- [x]"))' migrations/test-page/visual-deltas.md
node tests/fixtures/write-gate.mjs migrations/test-page
git add -A >/dev/null 2>&1; git commit -qm tick >/dev/null 2>&1
echo '{"total_cost_usd":0}'
`);
NODE
      ;;
    stuck) printf '#!/usr/bin/env bash\necho '\''{"total_cost_usd":0}'\''\n' > "$file" ;;
    blocked)
      node - "$file" <<'NODE'
const fs=require('fs');fs.writeFileSync(process.argv[2],`#!/usr/bin/env bash
mkdir -p .ralph; echo "needs a human decision" > .ralph/BLOCKED
echo '{"total_cost_usd":0}'
`);
NODE
      ;;
    costly)
      node - "$file" <<'NODE'
const fs=require('fs');fs.writeFileSync(process.argv[2],`#!/usr/bin/env bash
node -e 'const f=process.argv[1],s=require("fs");s.writeFileSync(f,s.readFileSync(f,"utf8").replace("- [ ]","- [x]"))' migrations/test-page/visual-deltas.md
node tests/fixtures/write-gate.mjs migrations/test-page
git add -A >/dev/null 2>&1; git commit -qm tick >/dev/null 2>&1
echo '{"total_cost_usd":10}'
`);
NODE
      ;;
    compacted) printf '#!/usr/bin/env bash\necho '\''{"type":"system","subtype":"compact_boundary"}'\''\necho '\''{"total_cost_usd":0}'\''\n' > "$file" ;;
    apierr) printf '#!/usr/bin/env bash\necho '\''{"type":"turn.failed","error":{"status":500,"message":"internal server error"}}'\''\n' > "$file" ;;
  esac
  chmod +x "$file"
}

run_case() { # name expected boxes kind [ENV=VALUE...]
  local name="$1" expected="$2" boxes="$3" kind="$4"; shift 4
  local dir got; dir="$(make_repo "$boxes")"; write_stub "$dir/stub.sh" "$kind"
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x "$@" bash scripts/ralph.sh ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = "$expected" ]; then printf '  PASS  %s\n' "$name"; pass=$((pass + 1))
  else printf '  FAIL  %s — expected exit %s, got %s\n' "$name" "$expected" "$got"; sed 's/^/        | /' "$dir/out.log" | tail -10; fail=$((fail + 1)); fi
  rm -rf "$dir"
}

multi_page_case() {
  local dir got order; dir="$(mktemp -d)"; copy_runner "$dir"
  printf 'home\thttps://source.example/\nabout\thttps://source.example/about\ncontact\thttps://source.example/contact\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" home 0 0; write_pack "$dir" about 0 0; write_pack "$dir" contact 0 0
  init_repo "$dir"
  node - "$dir/stub.sh" <<'NODE'
const fs=require('fs');fs.writeFileSync(process.argv[2],`#!/usr/bin/env bash
page_path="$(cat .ralph/ACTIVE_PAGE)"; page="\${page_path##*/}"
echo "$page" >> .ralph/order
mkdir -p "$page_path/reports"
echo checked > "$page_path/visual-deltas.md"
echo '# interactions' > "$page_path/interactions.md"
echo final > "$page_path/reports/final.md"
echo verified > "$page_path/reports/visual-verify.md"
node tests/fixtures/write-gate.mjs "$page_path"
git add -A >/dev/null 2>&1; git commit -qm "gate $page" >/dev/null 2>&1
echo '{"total_cost_usd":0}'
`);
NODE
  chmod +x "$dir/stub.sh"
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x RALPH_MAX_ITERATIONS=10 bash scripts/ralph.sh ) >"$dir/out.log" 2>&1
  got=$?; order="$(tr '\n' ' ' < "$dir/.ralph/order" | sed 's/ $//')"
  if [ "$got" = 0 ] && [ "$order" = 'home about contact' ] && grep -q 'Full migration complete' "$dir/out.log"; then
    printf '  PASS  MULTI    — one run gated all pages in queue order\n'; pass=$((pass + 1))
  else
    printf '  FAIL  MULTI    — exit=%s order="%s"\n' "$got" "$order"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir"
}

incomplete_plan_case() {
  local dir got; dir="$(mktemp -d)"; copy_runner "$dir"
  printf 'home\thttps://source.example/\nabout\thttps://source.example/about\n' > "$dir/migrations/_queue.tsv"
  write_pack "$dir" home 0 1; init_repo "$dir"; write_stub "$dir/stub.sh" stuck
  ( cd "$dir" && env CLAUDE_BIN="$dir/stub.sh" CLAUDE_FLAGS=x bash scripts/ralph.sh ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = 2 ] && grep -q 'about: contract: missing contract' "$dir/out.log"; then
    printf '  PASS  PREFLIGHT— missing queued page cannot become false DONE\n'; pass=$((pass + 1))
  else
    printf '  FAIL  PREFLIGHT— expected exit 2 for missing queued page, got %s\n' "$got"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir"
}

reaper_case() {
  local tag="ralph-managed-chromium-SELFTEST-$$" marked other marked_alive=0 other_alive=0
  bash -c "exec -a 'chromium --$tag --type=browser' sleep 30" & marked=$!
  bash -c "exec -a 'chromium --unrelated-flag --type=browser' sleep 30" & other=$!
  sleep 1; pkill -f "$tag" 2>/dev/null; sleep 1
  kill -0 "$marked" 2>/dev/null && marked_alive=1
  kill -0 "$other" 2>/dev/null && other_alive=1
  if [ "$marked_alive" = 0 ] && [ "$other_alive" = 1 ]; then printf '  PASS  REAPER   — killed only the tagged process\n'; pass=$((pass + 1))
  else printf '  FAIL  REAPER   — tagged_alive=%s unrelated_alive=%s\n' "$marked_alive" "$other_alive"; fail=$((fail + 1)); fi
  kill "$marked" "$other" 2>/dev/null; wait "$marked" "$other" 2>/dev/null
}

printf 'ralph.sh queue + exit self-test\n'
run_case 'DONE     — all boxes closed'         0 3 progress  RALPH_MAX_ITERATIONS=10
run_case 'STUCK    — no commit N loops'        6 3 stuck     RALPH_MAX_ITERATIONS=10 RALPH_NO_PROGRESS=3
run_case 'BLOCKED  — marker stops the loop'    3 3 blocked   RALPH_MAX_ITERATIONS=10
run_case 'CAP      — max iterations'           4 5 progress  RALPH_MAX_ITERATIONS=2
run_case 'BUDGET   — cost ceiling'             5 5 costly    RALPH_MAX_ITERATIONS=10 RALPH_MAX_BUDGET_USD=5
run_case 'COMPACTED— context boundary'         7 3 compacted RALPH_MAX_ITERATIONS=10
run_case 'API ERR  — independent retry cap'    8 3 apierr    RALPH_MAX_ITERATIONS=10 RALPH_NO_PROGRESS=3 RALPH_API_MAX=3 RALPH_API_BACKOFF=0
multi_page_case
one_go_case
one_go_partial_case
one_go_inventory_case
incomplete_plan_case
reaper_case

printf '\nresult: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
