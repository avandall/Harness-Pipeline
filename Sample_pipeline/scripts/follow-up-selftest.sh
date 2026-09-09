#!/usr/bin/env bash
# Offline regression tests for the post-migration follow-up runner.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0

copy_runner() {
  local dir="$1"
  mkdir -p "$dir/scripts/visual-diff" "$dir/prompts" "$dir/migrations/home/reports" "$dir/tests/fixtures"
  cp "$REPO/scripts/follow-up.sh" "$dir/scripts/follow-up.sh"
  cp "$REPO/scripts/agent-runner.sh" "$dir/scripts/agent-runner.sh"
  cp "$REPO/scripts/agent-format.mjs" "$dir/scripts/agent-format.mjs"
  cp "$REPO/scripts/agent-log.mjs" "$dir/scripts/agent-log.mjs"
  cp "$REPO/scripts/migration-state.mjs" "$dir/scripts/migration-state.mjs"
  cp "$REPO/scripts/env.mjs" "$dir/scripts/env.mjs"
  cp "$REPO/scripts/visual-diff/validate-assets.mjs" "$dir/scripts/visual-diff/validate-assets.mjs"
  cp "$REPO/scripts/visual-diff/validate-dynamics.mjs" "$dir/scripts/visual-diff/validate-dynamics.mjs"
  cp "$REPO/tests/fixtures/write-gate.mjs" "$dir/tests/fixtures/write-gate.mjs"
  cp "$REPO/prompts/PROMPT.md" "$dir/prompts/PROMPT.md"
  cp "$REPO/prompts/FOLLOW_UP.md" "$dir/prompts/FOLLOW_UP.md"
  chmod +x "$dir/scripts/follow-up.sh" "$dir/scripts/agent-runner.sh"
  printf '.ralph/\nstub.sh\nout.log\n' > "$dir/.gitignore"
  printf 'home\thttps://source.example/\n' > "$dir/migrations/_queue.tsv"
  node - "$dir/migrations/home" <<'NODE'
const fs=require('fs'),path=require('path'),crypto=require('crypto');const dir=process.argv[2];
const contract={page:'home',source:'https://source.example/',preview:'https://preview.example/',viewports:{desktop:1440},sections:[{key:'main',class:'content',sourceSelector:'main',replicaSelector:"[data-section-key='main']",mustMatch:['geometry'],targets:{desktop:{box:{x:0,y:0,w:1440,h:800},styles:{display:'block'}}}}]};
const text=JSON.stringify(contract,null,2)+'\n';fs.writeFileSync(path.join(dir,'contract.json'),text);
const contractHash=crypto.createHash('sha256').update(text).digest('hex');
fs.writeFileSync(path.join(dir,'assets.json'),JSON.stringify({page:'home',contractHash,assetPass:true,assets:[]})+'\n');
fs.writeFileSync(path.join(dir,'dynamics.json'),JSON.stringify({page:'home',contractHash,dynamicsPass:true,mustClassify:[]})+'\n');
fs.writeFileSync(path.join(dir,'interactions.md'),'# interactions\n');
fs.writeFileSync(path.join(dir,'visual-deltas.md'),'# visual deltas\n');
fs.writeFileSync(path.join(dir,'reports/final.md'),'gate complete\n');
fs.writeFileSync(path.join(dir,'reports/visual-verify.md'),'visual verify complete\n');
NODE
  ( cd "$dir" && node tests/fixtures/write-gate.mjs migrations/home )
}

init_repo() {
  local dir="$1" remote="$2"
  ( cd "$dir" && git init -q && git branch -M main && git config user.email test@example.com && git config user.name test-agent && git add -A && git commit -qm init )
  git init --bare -q "$remote"
  ( cd "$dir" && git remote add origin "$remote" && git push -qu -u origin main )
}

write_stub() {
  local file="$1" mode="$2"
  node - "$file" "$mode" <<'NODE'
const fs=require('fs');const [file,mode]=process.argv.slice(2);
let body=`#!/usr/bin/env bash
mkdir -p .ralph
cat > .ralph/captured-follow-up.prompt.md
echo invoked >> .ralph/follow-up-invocations
`;
if(mode==='success') body+=`printf 'implemented\\n' > follow-up-result.md
git add follow-up-result.md && git commit -qm 'implement follow-up tweak' && git push -q
echo '{"type":"turn.completed","usage":{"input_tokens":8,"output_tokens":3}}'
`;
else if(mode==='no-commit') body+=`echo '{"type":"turn.completed","usage":{"input_tokens":2,"output_tokens":1}}'
`;
else if(mode==='mutate-queue') body+=`printf 'home\\thttps://source.example/\\nother\\thttps://source.example/other\\n' > migrations/_queue.tsv
git add migrations/_queue.tsv && git commit -qm 'bad queue mutation' && git push -q
echo '{"type":"turn.completed","usage":{"input_tokens":2,"output_tokens":1}}'
`;
fs.writeFileSync(file,body);
NODE
  chmod +x "$file"
}

run_success_case() {
  local dir remote got calls
  dir="$(mktemp -d)"; remote="$(mktemp -d)/origin.git"; copy_runner "$dir"; init_repo "$dir" "$remote"; write_stub "$dir/stub.sh" success
  ( cd "$dir" && printf '%s' 'Make the announcement bar dismissible.' | env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/follow-up.sh ) >"$dir/out.log" 2>&1
  got=$?; calls="$(wc -l < "$dir/.ralph/follow-up-invocations" 2>/dev/null | tr -d ' ')"
  if [ "$got" = 0 ] && [ "$calls" = 1 ] \
    && grep -q 'Migrate one page (default-loop visual-first worker)' "$dir/.ralph/captured-follow-up.prompt.md" \
    && grep -q 'Load the project context before touching code' "$dir/.ralph/captured-follow-up.prompt.md" \
    && grep -q 'Make the announcement bar dismissible.' "$dir/.ralph/captured-follow-up.prompt.md" \
    && [ "$(cd "$dir" && git rev-parse HEAD)" = "$(cd "$dir" && git rev-parse origin/main)" ] \
    && [ "$(cd "$dir" && node scripts/migration-state.mjs remaining migrations)" = 0 ]; then
    printf '  PASS  SUCCESS   — context prompt + request ran once, committed, pushed, and stayed gated\n'; pass=$((pass + 1))
  else
    printf '  FAIL  SUCCESS   — exit=%s calls=%s\n' "$got" "${calls:-0}"; tail -15 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir" "${remote%/origin.git}"
}

run_incomplete_case() {
  local dir remote got
  dir="$(mktemp -d)"; remote="$(mktemp -d)/origin.git"; copy_runner "$dir"
  rm -f "$dir/migrations/home/reports/visual-verify.md" "$dir/migrations/home/gate.json"
  init_repo "$dir" "$remote"; write_stub "$dir/stub.sh" success
  ( cd "$dir" && printf '%s' tweak | env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/follow-up.sh ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = 2 ] && [ ! -f "$dir/.ralph/follow-up-invocations" ] && grep -q 'unlocks only after every queued page is DONE' "$dir/out.log"; then
    printf '  PASS  PREFLIGHT — incomplete migration cannot start a follow-up agent\n'; pass=$((pass + 1))
  else
    printf '  FAIL  PREFLIGHT — expected exit 2 without invocation, got %s\n' "$got"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir" "${remote%/origin.git}"
}

run_no_commit_case() {
  local dir remote got
  dir="$(mktemp -d)"; remote="$(mktemp -d)/origin.git"; copy_runner "$dir"; init_repo "$dir" "$remote"; write_stub "$dir/stub.sh" no-commit
  ( cd "$dir" && printf '%s' tweak | env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/follow-up.sh ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = 6 ] && grep -q 'without a new commit' "$dir/out.log"; then
    printf '  PASS  COMMIT    — an answer without an implementation commit is rejected\n'; pass=$((pass + 1))
  else
    printf '  FAIL  COMMIT    — expected exit 6, got %s\n' "$got"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir" "${remote%/origin.git}"
}

run_inventory_case() {
  local dir remote got
  dir="$(mktemp -d)"; remote="$(mktemp -d)/origin.git"; copy_runner "$dir"; init_repo "$dir" "$remote"; write_stub "$dir/stub.sh" mutate-queue
  ( cd "$dir" && printf '%s' tweak | env AGENT_PROVIDER=codex AGENT_BIN="$dir/stub.sh" AGENT_FLAGS=x bash scripts/follow-up.sh ) >"$dir/out.log" 2>&1
  got=$?
  if [ "$got" = 2 ] && grep -q 'sealed route inventory changed' "$dir/out.log"; then
    printf '  PASS  INVENTORY — follow-up cannot rewrite the sealed route scope\n'; pass=$((pass + 1))
  else
    printf '  FAIL  INVENTORY — expected exit 2, got %s\n' "$got"; tail -12 "$dir/out.log" | sed 's/^/        | /'; fail=$((fail + 1))
  fi
  rm -rf "$dir" "${remote%/origin.git}"
}

printf 'follow-up.sh post-migration self-test\n'
run_success_case
run_incomplete_case
run_no_commit_case
run_inventory_case
printf '\nresult: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
