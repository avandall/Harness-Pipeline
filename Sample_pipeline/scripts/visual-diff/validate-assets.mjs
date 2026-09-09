// Validate a migration page's asset register.
//
// Default: verify migrations/<page>/source/assets/* still matches assets.json hashes.
// --public: also verify the BUILD copied each asset to its Shopify theme destination
//           (`theme/assets/<file>` — Shopify's single flat assets folder) byte-for-byte.
//
// Usage: node scripts/visual-diff/validate-assets.mjs migrations/<page>/assets.json [--public]
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

export function validateAssets(assetsPath, {
  checkPublic = false, cwd = process.cwd(), expectedContractHash, expectedPage,
} = {}) {
  const failures = [];
  if (!assetsPath || !existsSync(assetsPath)) {
    return { pass: false, failures: [`missing assets file: ${assetsPath || '(missing path)'}`], count: 0 };
  }

  let register;
  try {
    register = JSON.parse(readFileSync(assetsPath, 'utf8'));
  } catch (error) {
    return { pass: false, failures: [`invalid assets JSON: ${error.message}`], count: 0 };
  }

  if (!register || typeof register !== 'object' || Array.isArray(register)) {
    return { pass: false, failures: ['assets.json root must be an object'], count: 0 };
  }

  const baseDir = path.dirname(assetsPath);
  if (expectedContractHash && register.contractHash !== expectedContractHash) {
    failures.push(`assets.json contractHash ${register.contractHash || '(missing)'} != current ${expectedContractHash}`);
  }
  if (expectedPage && register.page !== expectedPage) {
    failures.push(`assets.json page "${register.page || ''}" does not match "${expectedPage}"`);
  }
  if (register.assetPass !== true) {
    failures.push(`assets.json assetPass is not true (${(register.failures || []).length} capture failure(s))`);
  }

  const assets = Array.isArray(register.assets) ? register.assets : [];
  if (!Array.isArray(register.assets)) failures.push('assets.json assets must be an array');

  for (const asset of assets) {
    if (!asset || typeof asset !== 'object' || Array.isArray(asset)) {
      failures.push('assets.json contains a non-object asset entry');
      continue;
    }
    const localRoot = path.resolve(baseDir, 'source', 'assets');
    const local = path.resolve(baseDir, asset.localPath || '');
    if (!asset.localPath || (local !== localRoot && !local.startsWith(`${localRoot}${path.sep}`))) {
      failures.push(`${asset.id || asset.sourceUrl}: captured path escapes source/assets: ${asset.localPath || '(missing)'}`);
      continue;
    }
    if (!existsSync(local)) {
      failures.push(`${asset.id || asset.sourceUrl}: missing captured file ${asset.localPath}`);
      continue;
    }
    const localHash = sha256(readFileSync(local));
    if (localHash !== asset.sha256) {
      failures.push(`${asset.id || asset.sourceUrl}: captured hash ${localHash} != recorded ${asset.sha256}`);
    }
    if (!asset.verifiedExact) {
      failures.push(`${asset.id || asset.sourceUrl}: verifiedExact is false`);
    }

    if (checkPublic) {
      const publicPath = asset.publicPath;
      const absPublic = path.resolve(cwd, publicPath || '');
      const publicMatch = String(publicPath || '').match(/^theme\/assets\//);
      const publicRoot = path.resolve(cwd, 'theme', 'assets');
      if (!publicMatch || !absPublic.startsWith(`${publicRoot}${path.sep}`)) {
        failures.push(`${asset.id || asset.sourceUrl}: invalid Shopify theme asset destination (expected theme/assets/<file>) ${publicPath || '(missing)'}`);
        continue;
      }
      if (!existsSync(absPublic)) {
        failures.push(`${asset.id || asset.sourceUrl}: missing public asset ${publicPath}`);
        continue;
      }
      const publicHash = sha256(readFileSync(absPublic));
      if (publicHash !== asset.sha256) {
        failures.push(`${asset.id || asset.sourceUrl}: public hash ${publicHash} != source hash ${asset.sha256}`);
      }
    }
  }

  return { pass: failures.length === 0, failures, count: assets.length, register };
}

function main() {
  const argv = process.argv.slice(2);
  const assetsPath = argv.find((a) => !a.startsWith('--'));
  const checkPublic = argv.includes('--public');
  if (!assetsPath) {
    console.error('usage: validate-assets.mjs <assets.json> [--public]');
    process.exit(2);
  }

  const result = validateAssets(assetsPath, { checkPublic });
  if (!result.pass) {
    console.error(`asset validation failed (${result.failures.length})`);
    for (const failure of result.failures) console.error(`  - ${failure}`);
    process.exit(1);
  }
  console.log(`asset validation passed: ${result.count} asset(s)${checkPublic ? ' + public copies' : ''}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
