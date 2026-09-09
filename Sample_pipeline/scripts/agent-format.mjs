// Pretty-print provider JSONL streams without leaking provider details into the
// orchestration scripts. Unknown/non-JSON lines are passed through as plain text.
import { createInterface } from 'node:readline';

const provider = process.argv[2] || process.env.AGENT_PROVIDER || 'auto';
const C = { off: '\x1b[0m', dim: '\x1b[2m', cyan: '\x1b[36m', green: '\x1b[32m', red: '\x1b[31m', yellow: '\x1b[33m' };
const out = (value) => process.stdout.write(`${value}\n`);
const compact = (value, limit = 160) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, limit);

const claudeArg = (input) => {
  if (!input || typeof input !== 'object') return '';
  return compact(input.file_path || input.path || input.command || input.pattern || input.url
    || input.description || input.prompt, 90);
};

const renderClaudeMessage = (message) => {
  if (!message || !Array.isArray(message.content)) return;
  for (const item of message.content) {
    if (item.type === 'text' && item.text?.trim()) out(C.dim + item.text.trim() + C.off);
    else if (item.type === 'tool_use') out(`  ${C.cyan}🔧 ${item.name}${C.off} ${C.dim}${claudeArg(item.input)}${C.off}`);
    else if (item.type === 'tool_result' && item.is_error) {
      const detail = typeof item.content === 'string' ? item.content : JSON.stringify(item.content);
      out(`  ${C.red}↳ tool error${C.off} ${C.dim}${compact(detail, 120)}${C.off}`);
    }
  }
};

const renderCodexItem = (event) => {
  const item = event.item || {};
  const failed = item.status === 'failed' || (Number.isFinite(item.exit_code) && item.exit_code !== 0);
  if (item.type === 'agent_message' && item.text?.trim()) out(C.dim + item.text.trim() + C.off);
  else if (item.type === 'command_execution' && event.type === 'item.started') {
    out(`  ${C.cyan}🔧 shell${C.off} ${C.dim}${compact(item.command, 100)}${C.off}`);
  } else if (item.type === 'command_execution' && failed) {
    out(`  ${C.red}↳ command failed${C.off} ${C.dim}${compact(item.aggregated_output || item.output, 140)}${C.off}`);
  } else if (item.type === 'mcp_tool_call' && event.type === 'item.started') {
    out(`  ${C.cyan}🔧 ${item.server || 'mcp'}/${item.tool || item.name || '?'}${C.off}`);
  } else if (item.type === 'mcp_tool_call' && failed) {
    out(`  ${C.red}↳ MCP error${C.off} ${C.dim}${compact(item.error || item.result, 140)}${C.off}`);
  } else if (item.type === 'file_change' && event.type === 'item.completed') {
    const count = Array.isArray(item.changes) ? item.changes.length : 1;
    out(`  ${C.cyan}✎ file change${count === 1 ? '' : 's'}${C.off} ${C.dim}${count}${C.off}`);
  }
};

createInterface({ input: process.stdin }).on('line', (raw) => {
  const line = raw.trim();
  if (!line) return;
  let event;
  try { event = JSON.parse(line); } catch { out(C.dim + raw + C.off); return; }

  if (event.type === 'system' && event.subtype === 'init') {
    out(`${C.dim}· ${provider} session ${(event.session_id || '').slice(0, 8)} · model ${event.model || '?'}${C.off}`);
  } else if (event.type === 'assistant' || event.type === 'user') {
    renderClaudeMessage(event.message);
  } else if (event.type === 'result' || event.total_cost_usd != null) {
    const cost = event.total_cost_usd != null ? `$${Number(event.total_cost_usd).toFixed(4)}` : '?';
    const status = event.is_error ? `${C.red}ERROR${C.off}` : `${C.green}ok${C.off}`;
    out(`${C.green}✓ agent done${C.off} · ${status} · ${C.dim}cost ${cost}${C.off}`);
  } else if (event.type === 'thread.started') {
    out(`${C.dim}· codex thread ${(event.thread_id || '').slice(0, 8)}${C.off}`);
  } else if (event.type === 'item.started' || event.type === 'item.completed') {
    renderCodexItem(event);
  } else if (event.type === 'turn.completed') {
    const usage = event.usage || {};
    const tokens = Number(usage.input_tokens || 0) + Number(usage.output_tokens || 0);
    out(`${C.green}✓ agent done${C.off} · ${C.green}ok${C.off} · ${C.dim}${tokens.toLocaleString()} tokens${C.off}`);
  } else if (event.type === 'turn.failed' || event.type === 'agent_runner.failed' || event.type === 'error') {
    const detail = event.type === 'agent_runner.failed'
      ? `${event.provider || 'provider'} exited with status ${event.exit_code}`
      : (event.error?.message || event.message || event.error);
    out(`${C.red}✗ agent error${C.off} ${C.dim}${compact(detail, 180)}${C.off}`);
  } else if (event.type === 'agent.message' && event.text?.trim()) {
    out(C.dim + event.text.trim() + C.off);
  } else if (event.type === 'agent.tool') {
    out(`  ${C.cyan}🔧 ${event.name || 'tool'}${C.off} ${C.dim}${compact(event.detail, 100)}${C.off}`);
  } else if (event.type === 'agent.usage') {
    const usage = event.usage || {};
    const tokens = Number(usage.total_tokens || 0)
      || Number(usage.input_tokens || 0) + Number(usage.output_tokens || 0);
    out(`${C.green}✓ agent done${C.off} · ${C.dim}${tokens.toLocaleString()} tokens${C.off}`);
  } else if (event.type === 'agent.error' || event.type === 'agent.compacted') {
    out(`${C.red}✗ agent error${C.off} ${C.dim}${compact(event.message || event.error || event.type, 180)}${C.off}`);
  } else if (typeof event.message === 'string' || typeof event.text === 'string') {
    out(C.dim + compact(event.message || event.text, 500) + C.off);
  } else if (event.type && event.type !== 'rate_limit_event') {
    out(`${C.dim}· ${event.type}${C.off}`);
  }
});
