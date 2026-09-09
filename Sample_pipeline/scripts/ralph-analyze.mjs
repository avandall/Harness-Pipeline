// Scans provider JSONL logs for tool/command/MCP errors + API retries, aggregates
// them by tool + normalized message, and prints a markdown report. Deterministic (no LLM).
// Used by scripts/ralph-retro.sh. Usage: node scripts/ralph-analyze.mjs <dir>
//   <dir> = a run dir (.ralph/runs/<id>) or .ralph (flat) — reads every *.jsonl in it.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir || !existsSync(dir)) { console.error('usage: node ralph-analyze.mjs <runDir|.ralph>'); process.exit(1); }
const files = readdirSync(dir).filter((f) => f.endsWith('.jsonl')).sort();

const toolName = new Map();   // tool_use_id -> tool name
const errors = [];            // { iter, tool, msg }
const retries = [];           // { iter, status, error }

for (const f of files) {
  const iter = (f.match(/iter-(\d+)/) || [])[1] || f.replace('.jsonl', '');
  let lines; try { lines = readFileSync(path.join(dir, f), 'utf8').split('\n'); } catch { continue; }
  for (const line of lines) {
    const t = line.trim(); if (!t) continue;
    let o; try { o = JSON.parse(t); } catch { continue; }
    if (o.type === 'assistant' && o.message?.content) {
      for (const c of o.message.content) if (c.type === 'tool_use' && c.id) toolName.set(c.id, c.name);
    }
    if (o.type === 'user' && o.message?.content) {
      for (const c of o.message.content) if (c.type === 'tool_result' && c.is_error) {
        const msg = (typeof c.content === 'string' ? c.content : JSON.stringify(c.content)).replace(/\s+/g, ' ').trim();
        errors.push({ iter, tool: toolName.get(c.tool_use_id) || '?', msg });
      }
    }
    if (o.type === 'system' && o.subtype === 'api_retry') {
      retries.push({ iter, status: o.error_status || '?', error: String(o.error || '').replace(/\s+/g, ' ').slice(0, 160) });
    }
    if (o.type === 'item.completed' && o.item) {
      const item = o.item;
      const failed = item.status === 'failed' || (Number.isFinite(item.exit_code) && item.exit_code !== 0);
      if (failed && item.type === 'command_execution') {
        const msg = String(item.aggregated_output || item.output || item.command || 'command failed').replace(/\s+/g, ' ').trim();
        errors.push({ iter, tool: 'shell', msg });
      } else if (failed && item.type === 'mcp_tool_call') {
        const msg = String(item.error || item.result || 'MCP call failed').replace(/\s+/g, ' ').trim();
        errors.push({ iter, tool: `${item.server || 'mcp'}/${item.tool || item.name || '?'}`, msg });
      }
    }
    if (o.type === 'error' || o.type === 'turn.failed' || o.type === 'agent_runner.failed') {
      const error = String(o.error?.message || o.message || o.error || (o.type === 'agent_runner.failed' ? `${o.provider || 'provider'} exited ${o.exit_code}` : '')).replace(/\s+/g, ' ').slice(0, 160);
      retries.push({ iter, status: o.type, error });
    }
  }
}

// normalize a message into a signature so repeats group together
const sig = (m) => m.replace(/0x[0-9a-f]+/gi, '<hex>').replace(/[0-9a-f-]{12,}/gi, '<id>').replace(/\d+/g, 'N').slice(0, 140);
const agg = new Map();
for (const e of errors) {
  const k = e.tool + ' :: ' + sig(e.msg);
  const v = agg.get(k) || { tool: e.tool, count: 0, sample: e.msg, iters: new Set() };
  v.count++; v.iters.add(e.iter); agg.set(k, v);
}
const rows = [...agg.values()].sort((a, b) => b.count - a.count);

let md = `# Ralph run analysis — ${path.basename(path.resolve(dir))}\n\n`;
md += `- iterations logged: **${files.length}**\n- tool errors: **${errors.length}** (${rows.length} distinct)\n- API retries: **${retries.length}**\n\n`;
md += `## Tool errors (most frequent first)\n`;
if (!rows.length) md += `\n_none_ 🎉\n`;
for (const r of rows) md += `\n### \`${r.tool}\` ×${r.count}  (iters ${[...r.iters].join(', ')})\n\`\`\`\n${r.sample.slice(0, 400)}\n\`\`\`\n`;
if (retries.length) {
  md += `\n## API retries\n`;
  const ra = new Map();
  for (const x of retries) { const k = `${x.status} ${sig(x.error)}`; ra.set(k, (ra.get(k) || 0) + 1); }
  for (const [k, c] of [...ra].sort((a, b) => b[1] - a[1])) md += `- ×${c} — ${k}\n`;
}
process.stdout.write(md);
