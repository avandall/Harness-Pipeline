#!/usr/bin/env node
// Normalize usage and terminal signals from supported provider JSONL streams.
// Classification is deliberately event-structured: tool output and assistant text
// are untrusted payloads and must never be interpreted as provider status.
// Usage: node scripts/agent-log.mjs <stream.jsonl>
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const finite = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
const serializedError = (event) => JSON.stringify({
  code: event?.code,
  status: event?.status ?? event?.status_code,
  subtype: event?.subtype,
  message: event?.message,
  error: event?.error,
  result: event?.type === 'result' && event?.is_error ? event?.result : undefined,
});

function usageTokens(usage, { includeClaudeCache = false } = {}) {
  if (!usage || typeof usage !== 'object') return 0;
  const direct = finite(usage.input_tokens) + finite(usage.output_tokens);
  const total = finite(usage.total_tokens);
  const cache = includeClaudeCache
    ? finite(usage.cache_read_input_tokens) + finite(usage.cache_creation_input_tokens)
    : 0;
  return (direct || total) + cache;
}

function isTerminalFailure(event) {
  return event?.type === 'turn.failed'
    || event?.type === 'agent_runner.failed'
    || event?.type === 'error'
    || event?.type === 'agent.error'
    || (event?.type === 'result' && event?.is_error === true);
}

function isCompaction(event) {
  if (event?.type === 'system' && event?.subtype === 'compact_boundary') return true;
  if (event?.type === 'agent.compacted' || (event?.compacted === true && event?.type === 'agent.error')) return true;
  if (!isTerminalFailure(event)) return false;
  return /context_length_exceeded|context window|ran out of context/i.test(serializedError(event));
}

function isRetryable(event) {
  if (event?.type === 'rate_limit_event') {
    const status = String(event?.rate_limit_info?.status || '').toLowerCase();
    return !!status && status !== 'allowed';
  }
  if (event?.type === 'system' && event?.subtype === 'api_retry') return true;
  if (event?.type === 'agent.error' && event?.retryable === true) return true;
  if (!isTerminalFailure(event)) return false;
  const status = finite(event?.status ?? event?.status_code ?? event?.error?.status ?? event?.error?.status_code);
  if (status === 429 || status >= 500) return true;
  return /internal server error|api error[^\d]*5\d\d|overloaded|service unavailable|rate[ _-]?limit|\b429\b/i
    .test(serializedError(event));
}

export function summarizeStream(text) {
  let costUsd = null;
  let claudeUsage = null;
  const codexUsages = [];
  const genericUsages = [];
  let failed = false;
  let compacted = false;
  let retryableApiError = false;

  for (const line of String(text || '').split('\n')) {
    if (!line.trim()) continue;
    let event;
    try { event = JSON.parse(line); } catch { continue; }

    const eventCost = event.total_cost_usd ?? event.cost_usd ?? event.costUsd;
    if (eventCost != null && Number.isFinite(Number(eventCost))) costUsd = Number(eventCost);

    if (event.type === 'result' && event.usage) claudeUsage = event.usage;
    else if (event.type === 'turn.completed' && event.usage) codexUsages.push(event.usage);
    else if (event.type === 'agent.usage' && event.usage) genericUsages.push(event.usage);

    if (isTerminalFailure(event)) failed = true;
    if (isCompaction(event)) compacted = true;
    if (isRetryable(event)) retryableApiError = true;
  }

  let tokens = 0;
  if (claudeUsage) tokens = usageTokens(claudeUsage, { includeClaudeCache: true });
  else if (codexUsages.length) tokens = codexUsages.reduce((sum, usage) => sum + usageTokens(usage), 0);
  else tokens = genericUsages.reduce((sum, usage) => sum + usageTokens(usage, { includeClaudeCache: true }), 0);

  return { costUsd, tokens, compacted, retryableApiError, failed };
}

function main() {
  const file = process.argv[2];
  if (!file) { console.error('usage: agent-log.mjs <stream.jsonl>'); process.exit(2); }
  let stream = '';
  try { stream = readFileSync(file, 'utf8'); } catch {}
  process.stdout.write(JSON.stringify(summarizeStream(stream)));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
