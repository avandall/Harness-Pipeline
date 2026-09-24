#!/usr/bin/env node
/**
 * ralph-analyze.mjs — Smart Multi-Layer Deterministic Log Analyzer
 * 
 * Accurately isolates REAL Tool Errors, Runtime Crashes, and Test Failures
 * while strictly filtering out false positives (code declarations, git diffs,
 * passing test summaries, markdown documentation, exception handling specs).
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

const timeoutEvents = [];
const runtimeErrors = {};
const testFailures = {};

let totalTimeouts = 0;
let totalRuntimeErrors = 0;
let totalTestFailures = 0;

// Patterns that identify TRUE runtime / tool / test failures
const PATTERNS_RUNTIME_ERROR = [
  /command not found/i,
  /permission denied/i,
  /Traceback \(most recent call last\):/,
  /^\s*(TypeError|NameError|AttributeError|KeyError|IndexError|ValueError|ImportError|ModuleNotFoundError|SyntaxError|IndentationError):/,
  /fatal error:/i,
  /UnhandledPromiseRejection/i,
  /Uncaught \w+Error:/,
  /Tool execution failed/i,
  /MCP error/i,
  /ECONNREFUSED/i,
  /ENOENT: no such file or directory/i,
  /fatal: [^\n]+/
];

const PATTERNS_TIMEOUT = [
  /print timeout after/i,
  /\[agy\] print timeout/i,
  /Command timed out/i,
  /Terminated due to timeout/i,
  /timed out after/i,
  /timeout after \d+/i,
  /STALL WATCHDOG/i,
  /exit code 124/i,
  /timeout waiting for response/i,
  /ETIMEDOUT/i
];

function isFalsePositive(line, trimmed) {
  // 1. Git diff lines (+ / - / @@)
  if (/^[+-]{1,3}\s/.test(trimmed) || /^@@\s+-\d+/.test(trimmed) || /^\+\+\+\s+[ab]\//.test(trimmed) || /^---\s+[ab]\//.test(trimmed)) {
    return true;
  }

  // 2. Code declarations, imports, type annotations
  if (
    /^(class|def|async def|function|const|let|var|import|from|export|interface|type)\s/.test(trimmed) ||
    /^(except|catch|throw new|raise|return)\s/.test(trimmed) ||
    /^\s*(logger\.|console\.|print\()/.test(trimmed)
  ) {
    return true;
  }

  // 3. Passing test summaries or benign test runs
  if (
    /(0 failed|without error|passed in|\[100%\]|\d+ passed,\s*0 failed)/i.test(trimmed) ||
    /(\.py\s+PASSED|test_\w+\s+PASSED)/.test(trimmed) ||
    /OK\s*\(passes=\d+\)/.test(trimmed)
  ) {
    return true;
  }

  // 4. Git status / file paths / commit subjects
  if (
    /^(modified:|new file:|deleted:|renamed:|Untracked files:|Changes not staged)/.test(trimmed) ||
    /^\[TASK-\d+\]/.test(trimmed) ||
    /^(commit|Author:|Date:)\s/.test(trimmed)
  ) {
    return true;
  }

  // 5. Documentation, Markdown bullet points, status logs
  if (/^[-*#]\s+|\d+\.\s+/.test(trimmed)) {
    // Only consider as real error if it has explicit failure indicators
    if (!/FAILED|Traceback|❌|TOOL ERROR|Exit code [^0]/i.test(trimmed)) {
      return true;
    }
  }

  // 6. JSON fields & prompt transcripts
  if (/^"role":\s*"(user|assistant|system)"/.test(trimmed) || /^{\s*"(command|tool_name|task|title)"/i.test(trimmed)) {
    return true;
  }

  // 7. General explanatory phrases
  if (
    /Handling error|error handler|gracefully|sanitization|Edge Cases|Error handling strategy/i.test(trimmed) &&
    !/Traceback|FAILED|Command not found|Permission denied/i.test(trimmed)
  ) {
    return true;
  }

  return false;
}

for (const f of logFiles) {
  try {
    const text = fs.readFileSync(f, 'utf-8');
    const lines = text.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!trimmed) continue;

      // Check for Timeout & Stall first
      let matchedTimeout = false;
      for (const p of PATTERNS_TIMEOUT) {
        if (p.test(trimmed)) {
          const entry = `${path.basename(f)}: ${trimmed.substring(0, 120)}`;
          if (!timeoutEvents.includes(entry)) {
            timeoutEvents.push(entry);
          }
          totalTimeouts++;
          matchedTimeout = true;
          break;
        }
      }
      if (matchedTimeout) continue;

      // Skip false positives
      if (isFalsePositive(line, trimmed)) {
        continue;
      }

      // Check Pytest failure lines
      if (/^FAILED\s+tests\/[^\s]+/.test(trimmed)) {
        const cleaned = trimmed.substring(0, 140);
        testFailures[cleaned] = (testFailures[cleaned] || 0) + 1;
        totalTestFailures++;
        continue;
      }

      // Check Real Runtime / Tool errors
      for (const p of PATTERNS_RUNTIME_ERROR) {
        if (p.test(trimmed)) {
          const cleaned = trimmed.substring(0, 140);
          runtimeErrors[cleaned] = (runtimeErrors[cleaned] || 0) + 1;
          totalRuntimeErrors++;
          break;
        }
      }
    }
  } catch {}
}

console.log('# 📊 Ralph Loop Execution Analysis (' + targetDir + ')');
console.log(`- Total log files analyzed: ${logFiles.length}`);
console.log(`- Timeout / Stall events: ${totalTimeouts}`);
console.log(`- Real runtime / tool errors: ${totalRuntimeErrors}`);
console.log(`- Test suite failures: ${totalTestFailures}\n`);

if (totalRuntimeErrors === 0 && totalTestFailures === 0 && totalTimeouts === 0) {
  console.log('### Status: _none_ (Clean run — zero errors or timeouts detected ✓)');
  process.exit(0);
}

if (totalRuntimeErrors === 0 && totalTestFailures === 0 && totalTimeouts > 0) {
  console.log('### Verdict: TIMEOUT_OR_COMPACTION_ONLY');
  console.log('> ℹ️ **Không phát hiện lỗi công cụ (tool error) hay lỗi cú pháp/hạ tầng nào.** Các lượt chạy chỉ kết thúc do vượt quá Time Budget hoặc chờ LLM stream.');
  console.log('> **Khuyến nghị kiến trúc:**');
  console.log('> 1. TUYỆT ĐỐI KHÔNG sửa đổi `BOUNDARIES.md` hay `TECH_CONTEXT.md` vì các tài liệu này hoàn toàn chính xác.');
  console.log('> 2. Chia nhỏ task lớn thành các atomic micro-steps (dưới 3 microservices hoặc dưới 5 files) trong `Tasks_list.md`.');
  console.log('> 3. Kích hoạt tính năng Stall Watchdog & Dynamic Budgeting của Ralph Loop để tự động cấp thêm thời gian khi agent đang tích cực xử lý.\n');
  console.log('#### Ghi nhận Timeout / Stall gần nhất:');
  for (const t of timeoutEvents.slice(0, 8)) {
    console.log(`- \`${t}\``);
  }
  process.exit(0);
}

if (totalRuntimeErrors > 0) {
  console.log('### 🚨 Top Recurring Tool & Runtime Errors:');
  const sorted = Object.entries(runtimeErrors).sort((a, b) => b[1] - a[1]).slice(0, 10);
  for (const [msg, count] of sorted) {
    console.log(`- [x${count}] \`${msg}\``);
  }
  console.log('');
}

if (totalTestFailures > 0) {
  console.log('### 🧪 Test Failures:');
  const sortedTests = Object.entries(testFailures).sort((a, b) => b[1] - a[1]).slice(0, 5);
  for (const [msg, count] of sortedTests) {
    console.log(`- [x${count}] \`${msg}\``);
  }
  console.log('');
}
