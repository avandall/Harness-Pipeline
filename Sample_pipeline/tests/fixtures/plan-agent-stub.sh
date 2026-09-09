#!/usr/bin/env bash
# Offline fake agent used by scripts/plan-selftest.sh. It consumes the same stdin task as the
# real CLI and writes deterministic evidence packs without network or browser access.

set -uo pipefail

prompt="$(cat)"
mode="${STUB_MODE:-valid}"
mkdir -p .ralph migrations

write_pack() {
  local page="$1" source="$2" dir="migrations/$1"
  mkdir -p "$dir"
  node - "$dir" "$page" "$source" <<'NODE'
const fs = require('fs');
const path = require('path');
const [dir, page, source] = process.argv.slice(2);
const contract = {
  page,
  source,
  preview: `https://preview.example/${page}`,
  viewports: { desktop: 1440, mobile: 390 },
  sections: [{
    key: 'main', class: 'content', sourceSelector: 'main',
    replicaSelector: "[data-section-key='main']", mustMatch: ['geometry'],
    targets: {
      desktop: { box: { x: 0, y: 0, w: 1440, h: 800 }, styles: { display: 'block' } },
      mobile: { box: { x: 0, y: 0, w: 390, h: 600 }, styles: { display: 'block' } },
    },
  }],
};
fs.writeFileSync(path.join(dir, 'contract.json'), `${JSON.stringify(contract, null, 2)}\n`);
const crypto = require('crypto');
const contractHash = crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, 'contract.json'))).digest('hex');
fs.writeFileSync(path.join(dir, 'assets.json'), `${JSON.stringify({ page, contractHash, assetPass: true, assets: [] })}\n`);
fs.writeFileSync(path.join(dir, 'dynamics.json'), `${JSON.stringify({ page, contractHash, dynamicsPass: true, mustClassify: [] })}\n`);
fs.writeFileSync(path.join(dir, 'interactions.md'), `# ${page} interactions\n`);
NODE
}

gate_page() {
  local page="$1" page_dir="migrations/$1"
  printf '%s\n' "$page" >> .ralph/execute-order
  mkdir -p "$page_dir/reports"
  printf '# visual deltas\n- [x] all within tolerance\n' > "$page_dir/visual-deltas.md"
  printf '# interactions\n- [x] verified\n' > "$page_dir/interactions.md"
  printf '# final\nPASS\n' > "$page_dir/reports/final.md"
  printf '# visual verify\nPASS\n' > "$page_dir/reports/visual-verify.md"
  node tests/fixtures/write-gate.mjs "$page_dir"
}

if printf '%s' "$prompt" | grep -q 'SELFTEST_EXECUTE_ONE_GO_OVERLAY'; then
  printf '%s' "$prompt" | grep -q 'SELFTEST_EXECUTE_BASE_ONLY' \
    || { printf 'one-go Execute prompt omitted the canonical base prompt\n' >&2; exit 9; }
  printf 'one-go\n' >> .ralph/execute-invocations
  while IFS=$'\t' read -r page source _rest; do
    case "${page:-}" in ''|\#*) continue ;; esac
    [ "$mode" != one_go_incomplete ] || [ "$page" = home ] || break
    [ "$mode" != one_go_mutate_inventory ] || [ "$page" = home ] || break
    gate_page "$page"
  done < migrations/_queue.tsv
  if [ "$mode" = one_go_mutate_inventory ]; then
    printf 'home\thttps://source.example/\n' > migrations/_queue.tsv
  fi
  git add migrations >/dev/null 2>&1
  git commit -qm 'gate complete queue' >/dev/null 2>&1
  printf '{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":8}}\n'
  exit 0
fi

if printf '%s' "$prompt" | grep -q 'SELFTEST_EXECUTE_BASE_ONLY'; then
  page_dir="$(cat .ralph/ACTIVE_PAGE)"
  page="${page_dir##*/}"
  gate_page "$page"
  git add migrations >/dev/null 2>&1
  git commit -qm "gate $page" >/dev/null 2>&1
  printf '{"total_cost_usd":0}\n'
  exit 0
fi

if printf '%s' "$prompt" | grep -q 'DISCOVERY ONLY'; then
  printf 'discovery\n' >> .ralph/plan-calls
  cat > migrations/_queue.tsv <<'QUEUE'
home	https://source.example/
about	https://source.example/about
contact	https://source.example/contact
QUEUE
  exit 0
fi

page="$(printf '%s' "$prompt" | sed -n 's/.*(page key: \([^)]*\)).*/\1/p')"
[ -n "$page" ] || { printf 'stub could not extract page key\n' >&2; exit 2; }
printf '%s\n' "$page" >> .ralph/plan-order

attempt_file=".ralph/plan-attempt-$page"
attempt=0
[ ! -f "$attempt_file" ] || attempt="$(cat "$attempt_file")"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"

if [ "$mode" = blocked ]; then
  printf 'needs a human decision\n' > .ralph/BLOCKED
  exit 0
fi
if [ "$mode" = compacted ]; then
  printf '%s\n' '{"type":"system","subtype":"compact_boundary"}'
  exit 0
fi
if [ "$mode" = apierr ]; then
  printf '%s\n' '{"type":"turn.failed","error":{"status":503,"message":"service unavailable"}}'
  exit 0
fi
if [ "$mode" = providerfail ]; then
  printf '%s\n' '{"type":"turn.failed","error":{"status":400,"message":"bad request"}}'
  exit 0
fi
if [ "$mode" = costly ]; then
  printf '%s\n' '{"type":"result","total_cost_usd":10,"usage":{"input_tokens":1,"output_tokens":1}}'
  exit 0
fi
if [ "$mode" = no_progress ]; then
  exit 0
fi

dir="migrations/$page"
mkdir -p "$dir"
source="$(printf '%s' "$prompt" | sed -n 's/.*local reference entry \([^ ]*\).*/\1/p')"
if [ -z "$source" ]; then
  source="https://source.example/"
  [ "$page" = home ] || source="${source}${page}"
fi

if [ "$mode" = content_progress ] && [ "$page" = home ] && [ "$attempt" -lt 3 ]; then
  # Both attempts update the same lone file. A file-count progress check incorrectly stops on attempt 2;
  # the production runner's content fingerprint must notice the durable edit and continue.
  node -e 'const fs=require("fs");const [file,page,attempt]=process.argv.slice(1);fs.writeFileSync(file,JSON.stringify({page,_attempt:Number(attempt)},null,2)+"\n")' "$dir/contract.json" "$page" "$attempt"
  exit 0
fi

write_pack "$page" "$source"

if [ "$mode" = mutate_queue ] && [ "$page" = home ]; then
  printf 'home\thttps://source.example/\n' > migrations/_queue.tsv
fi
