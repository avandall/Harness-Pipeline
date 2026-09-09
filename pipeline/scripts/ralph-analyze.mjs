#!/usr/bin/env node
/**
 * ralph-analyze.mjs — Deterministic log analyzer for tool errors and friction points
 */
import fs from 'fs';
import path from 'path';

const targetDir = process.argv[2] || '.ralph';
if (!fs.existsSync(targetDir)) {
  console.log('No run logs found in ' + targetDir);
  process.exit(0);
}

function findLogFiles(dir) {
  let files = [];
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        files = files.concat(findLogFiles(full));
      } else if (e.name.endsWith('.log') || e.name.endsWith('.jsonl') || e.name.endsWith('.err')) {
        files.push(full);
      }
    }
  } catch {}
  return files;
}

const logFiles = findLogFiles(targetDir);
if (logFiles.length === 0) {
  console.log('# Log Analysis Report\n_none_ — No logs found.');
  process.exit(0);
}

const errors = {};
let totalErrors = 0;

for (const f of logFiles) {
  try {
    const text = fs.readFileSync(f, 'utf-8');
    const lines = text.split('\n');
    for (const l of lines) {
      if (/status tracking|`PENDING`|`RUNNING`|`COMPLETED`|`FAILED`/i.test(l) && !/FAILED test_|❌/i.test(l)) {
        continue;
      }
      if (/error:|failed|exception|enoent|command not found|traceback/i.test(l)) {
        const cleaned = l.trim().substring(0, 140);
        errors[cleaned] = (errors[cleaned] || 0) + 1;
        totalErrors++;
      }
    }
  } catch {}
}

console.log('# 📊 Ralph Loop Execution Analysis (' + targetDir + ')');
console.log(`- Total log files analyzed: ${logFiles.length}`);
console.log(`- Total error occurrences detected: ${totalErrors}\n`);

if (totalErrors === 0) {
  console.log('### Status: _none_ (Clean run — zero recurring errors detected ✓)');
} else {
  console.log('### Top Recurring Tool Errors & Friction Points:');
  const sorted = Object.entries(errors).sort((a, b) => b[1] - a[1]).slice(0, 10);
  for (const [msg, count] of sorted) {
    console.log(`- [x${count}] \`${msg}\``);
  }
}
