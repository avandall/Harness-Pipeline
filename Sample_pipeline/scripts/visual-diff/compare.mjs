// Compare two screenshot sets (original vs new) captured by capture.mjs.
// For each matching <viewport>.png it: normalizes dimensions, runs pixelmatch
// (a per-pixel diff), writes a diff image, builds a SIDE-BY-SIDE merged image
// (original | new) so a reviewer/agent sees both at once, and records a score.
// WHY: a migration is "done" only when new === original at every viewport; the
// merged image is for human/agent eyes, the score catches what the eye misses.
//
// Usage: node scripts/visual-diff/compare.mjs --orig <dir> --new <dir> [--out <dir>] [--threshold 0.01]
// Output: <out>/<viewport>.merged.png, <out>/<viewport>.diff.png, <out>/report.json
//
// Requires: npm i -D pixelmatch pngjs
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';

const arg = (n, d) => { const i = process.argv.indexOf(n); return i >= 0 ? process.argv[i + 1] : d; };
const origDir = arg('--orig'); const newDir = arg('--new');
const outDir = arg('--out', 'scripts/visual-diff/out/compare');
const threshold = Number(arg('--threshold', '0.01')); // max acceptable mismatched-pixel fraction
if (!origDir || !newDir) { console.error('usage: compare.mjs --orig <dir> --new <dir> [--out <dir>] [--threshold 0.01]'); process.exit(1); }
mkdirSync(outDir, { recursive: true });

// Resize an image onto a WxH canvas: crop overflow, pad shortfall with white.
const fit = (img, W, H) => {
  const out = new PNG({ width: W, height: H });
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const di = (y * W + x) * 4;
    if (y < img.height && x < img.width) {
      const si = (y * img.width + x) * 4;
      out.data[di] = img.data[si]; out.data[di + 1] = img.data[si + 1];
      out.data[di + 2] = img.data[si + 2]; out.data[di + 3] = img.data[si + 3];
    } else { out.data[di] = out.data[di + 1] = out.data[di + 2] = out.data[di + 3] = 255; }
  }
  return out;
};

const report = [];
let worst = 0;
for (const f of readdirSync(origDir).filter((f) => f.endsWith('.png'))) {
  const op = path.join(origDir, f), np = path.join(newDir, f);
  if (!existsSync(np)) { report.push({ page: f, error: 'missing in new' }); worst = 1; continue; }
  const a = PNG.sync.read(readFileSync(op)), b = PNG.sync.read(readFileSync(np));
  const W = Math.min(a.width, b.width);            // common width
  const H = Math.max(a.height, b.height);          // tallest (pad the shorter)
  const A = fit(a, W, H), B = fit(b, W, H);
  const diff = new PNG({ width: W, height: H });
  const mismatched = pixelmatch(A.data, B.data, diff.data, W, H, { threshold: 0.1 });
  const score = mismatched / (W * H);
  worst = Math.max(worst, score);
  writeFileSync(path.join(outDir, f.replace('.png', '.diff.png')), PNG.sync.write(diff));
  // side-by-side: original | 10px gutter | new
  const merged = new PNG({ width: W * 2 + 10, height: H });
  merged.data.fill(255);
  const blit = (img, offx) => { for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const si = (y * W + x) * 4, di = (y * (W * 2 + 10) + (x + offx)) * 4;
    merged.data[di] = img.data[si]; merged.data[di + 1] = img.data[si + 1];
    merged.data[di + 2] = img.data[si + 2]; merged.data[di + 3] = img.data[si + 3];
  } };
  blit(A, 0); blit(B, W + 10);
  writeFileSync(path.join(outDir, f.replace('.png', '.merged.png')), PNG.sync.write(merged));
  const pass = score <= threshold;
  report.push({ page: f, mismatchedPixels: mismatched, score: Number(score.toFixed(5)), pass });
  console.log(`${f}  score=${score.toFixed(5)}  ${pass ? 'PASS' : 'REVIEW'}`);
}
writeFileSync(path.join(outDir, 'report.json'), JSON.stringify({ threshold, worst: Number(worst.toFixed(5)), pages: report }, null, 2));
console.log('report ->', path.join(outDir, 'report.json'), '| worst score', worst.toFixed(5));
// Non-zero exit if any page exceeds threshold, so tests/CI can gate on it.
process.exit(worst <= threshold ? 0 : 1);
