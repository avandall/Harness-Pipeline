#!/usr/bin/env bash
set -uo pipefail

printf '%s\n' "$@" > "${STUB_ARGS_FILE:?}"
printf '%s\t%s\n' "${AGENT_SELECTED_MODEL:-}" "${AGENT_SELECTED_EFFORT:-}" > "${STUB_ENV_FILE:?}"
cat > "${STUB_PROMPT_FILE:?}"

case "${STUB_STREAM:-claude}" in
  claude)
    printf '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"stub ok"}]}}\n'
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"docs mention compact_boundary and ran out of context","is_error":false}]}}\n'
    printf '{"type":"result","total_cost_usd":1.25,"usage":{"input_tokens":7,"cache_read_input_tokens":4,"cache_creation_input_tokens":2,"output_tokens":3}}\n'
    ;;
  codex)
    printf '{"type":"thread.started","thread_id":"stub-thread"}\n'
    printf '{"type":"turn.completed","usage":{"input_tokens":11,"output_tokens":4}}\n'
    ;;
  error)
    printf '{"type":"turn.failed","error":{"status":503,"message":"service unavailable"}}\n'
    ;;
  nonzero)
    exit 9
    ;;
esac
