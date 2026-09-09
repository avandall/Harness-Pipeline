// Validate that a CAPTURE dynamic inventory was actually classified in interactions.md.
//
// Usage: node scripts/visual-diff/validate-dynamics.mjs migrations/<page>/dynamics.json
//        node scripts/visual-diff/validate-dynamics.mjs migrations/<page>/dynamics.json --interactions migrations/<page>/interactions.md
// Exit: 0 = all required dynamic items classified; 1 = missing/invalid; 2 = bad args.
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export function validateDynamics(dynamicsPath, { interactionsPath, expectedContractHash, expectedPage } = {}) {
  const failures = [];
  if (!dynamicsPath || !existsSync(dynamicsPath)) {
    return { pass: false, failures: [`missing dynamics file: ${dynamicsPath || '(missing path)'}`], count: 0 };
  }

  let dynamics;
  try {
    dynamics = JSON.parse(readFileSync(dynamicsPath, 'utf8'));
  } catch (error) {
    return { pass: false, failures: [`invalid dynamics JSON: ${error.message}`], count: 0 };
  }

  if (!dynamics || typeof dynamics !== 'object' || Array.isArray(dynamics)) {
    return { pass: false, failures: ['dynamics.json root must be an object'], count: 0 };
  }

  const resolvedInteractions = interactionsPath || path.join(path.dirname(dynamicsPath), 'interactions.md');
  if (expectedContractHash && dynamics.contractHash !== expectedContractHash) {
    failures.push(`dynamics.json contractHash ${dynamics.contractHash || '(missing)'} != current ${expectedContractHash}`);
  }
  if (expectedPage && dynamics.page !== expectedPage) {
    failures.push(`dynamics.json page "${dynamics.page || ''}" does not match "${expectedPage}"`);
  }
  if (dynamics.dynamicsPass !== true) {
    failures.push(`dynamicsPass is not true (${(dynamics.failures || []).length} scan failure(s))`);
  }

  const mustClassify = Array.isArray(dynamics.mustClassify) ? dynamics.mustClassify : [];
  if (!Array.isArray(dynamics.mustClassify)) failures.push('dynamics.json mustClassify must be an array');

  if (!existsSync(resolvedInteractions)) {
    failures.push(`missing interactions file: ${resolvedInteractions}`);
  } else {
    const lines = readFileSync(resolvedInteractions, 'utf8').split('\n');
    const classification = /(?:\s[-—:]\s)(REBUILD|DEFER(?:-to-app)?|DROP)\b/i;
    const knownIds = new Set(mustClassify.map((item) => item?.id).filter(Boolean));
    for (const item of mustClassify) {
      if (!item || typeof item !== 'object' || !item.id) {
        failures.push('dynamics.json contains a mustClassify entry without an id');
        continue;
      }
      const marker = `[dyn:${item.id}]`;
      const matching = lines.filter((line) => line.includes(marker));
      if (!matching.length) {
        failures.push(`${item.id}: missing ${marker} in interactions.md (${item.category}: ${item.title})`);
        continue;
      }
      if (matching.length !== 1) failures.push(`${item.id}: ${marker} must appear exactly once in interactions.md`);
      if (!matching.some((line) => classification.test(line))) {
        failures.push(`${item.id}: interaction line must classify as REBUILD, DEFER-to-app, or DROP`);
      }
    }

    for (const [index, line] of lines.entries()) {
      if (/^\s*-\s*\[[ xX]\].*\[dyn:[^\]]+\].*\b(DEFER(?:-to-app)?|DROP)\b/i.test(line)) {
        failures.push(`line ${index + 1}: DEFER/DROP rows must be plain bullets, not checkboxes`);
      }
      if (line.includes('[dyn:') && !classification.test(line)) {
        failures.push(`line ${index + 1}: dynamic row lacks REBUILD/DEFER-to-app/DROP classification`);
      }
      for (const marker of line.matchAll(/\[dyn:([^\]]+)\]/g)) {
        if (!knownIds.has(marker[1])) failures.push(`line ${index + 1}: unknown dynamic id "${marker[1]}"`);
      }
    }
  }

  return { pass: failures.length === 0, failures, count: mustClassify.length, dynamics };
}

function main() {
  const argv = process.argv.slice(2);
  const dynamicsPath = argv.find((a) => !a.startsWith('--'));
  const flag = (name, fallback) => {
    const index = argv.indexOf(name);
    return index >= 0 ? argv[index + 1] : fallback;
  };
  if (!dynamicsPath) {
    console.error('usage: validate-dynamics.mjs <dynamics.json> [--interactions interactions.md]');
    process.exit(2);
  }

  const result = validateDynamics(dynamicsPath, { interactionsPath: flag('--interactions') });
  if (!result.pass) {
    console.error(`dynamic validation failed (${result.failures.length})`);
    for (const failure of result.failures) console.error(`  - ${failure}`);
    process.exit(1);
  }
  console.log(`dynamic validation passed: ${result.count} required item(s) classified`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
