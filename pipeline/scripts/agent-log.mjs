#!/usr/bin/env node
/**
 * agent-log.mjs — Extracts metrics (compaction, errors, turns, timeouts, dynamic budgeting) from run log
 * Optimized for AGY Subscription Quota Mode (no API billing checks needed)
 */
import fs from 'fs';

const file = process.argv[2];
if (!file || !fs.existsSync(file)) {
  console.log(JSON.stringify({ compacted: false, retryableApiError: false, failed: false, timedOut: false, stalled: false, extended: false }));
  process.exit(0);
}

try {
  const content = fs.readFileSync(file, 'utf-8');
  let compacted = false;
  let retryableApiError = false;
  let failed = false;
  let timedOut = false;
  let stalled = false;
  let extended = false;

  // Check for auto-compaction triggers
  if (content.includes('compact_boundary') || content.includes('Context limit reached') || content.includes('Conversation history truncated')) {
    compacted = true;
  }

  // Check for Timeout & Watchdog triggers
  if (
    content.includes('print timeout after') ||
    content.includes('Command timed out') ||
    content.includes('Terminated due to timeout') ||
    content.includes('STALL WATCHDOG') ||
    content.includes('ETIMEDOUT')
  ) {
    timedOut = true;
  }

  if (content.includes('STALL WATCHDOG')) {
    stalled = true;
  }

  if (content.includes('DYNAMIC BUDGETING') || content.includes('Extended budget')) {
    extended = true;
  }

  // Check for API / 5xx / Network errors
  if (
    content.includes('500 Internal Server Error') ||
    content.includes('503 Service Unavailable') ||
    content.includes('Rate limit exceeded') ||
    content.includes('ECONNRESET') ||
    content.includes('timeout waiting for response') ||
    content.includes('fetch failed')
  ) {
    retryableApiError = true;
  }

  // Check for general failure
  if (content.includes('Execution failed') || content.includes('FATAL ERROR') || timedOut) {
    failed = true;
  }

  console.log(JSON.stringify({
    compacted,
    retryableApiError,
    failed,
    timedOut,
    stalled,
    extended
  }));
} catch (e) {
  console.log(JSON.stringify({ compacted: false, retryableApiError: false, failed: true, timedOut: false, stalled: false, extended: false, error: e.message }));
}
