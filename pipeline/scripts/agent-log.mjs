#!/usr/bin/env node
/**
 * agent-log.mjs — Extracts metrics (compaction, errors, turns) from run log
 * Optimized for AGY Subscription Quota Mode (no API billing checks needed)
 */
import fs from 'fs';

const file = process.argv[2];
if (!file || !fs.existsSync(file)) {
  console.log(JSON.stringify({ compacted: false, retryableApiError: false, failed: false }));
  process.exit(0);
}

try {
  const content = fs.readFileSync(file, 'utf-8');
  let compacted = false;
  let retryableApiError = false;
  let failed = false;

  // Check for auto-compaction triggers
  if (content.includes('compact_boundary') || content.includes('Context limit reached') || content.includes('Conversation history truncated')) {
    compacted = true;
  }

  // Check for API / 5xx / Timeout errors
  if (
    content.includes('500 Internal Server Error') ||
    content.includes('503 Service Unavailable') ||
    content.includes('Rate limit exceeded') ||
    content.includes('ECONNRESET') ||
    content.includes('timeout waiting for response') ||
    content.includes('ETIMEDOUT') ||
    content.includes('fetch failed')
  ) {
    retryableApiError = true;
  }

  // Check for failure
  if (content.includes('Execution failed') || content.includes('FATAL ERROR') || content.includes('Command timed out')) {
    failed = true;
  }

  console.log(JSON.stringify({
    compacted,
    retryableApiError,
    failed
  }));
} catch (e) {
  console.log(JSON.stringify({ compacted: false, retryableApiError: false, failed: true, error: e.message }));
}
