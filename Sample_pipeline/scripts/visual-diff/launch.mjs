// Shared Chromium launcher for the visual-diff harness (capture.mjs, inspect.mjs).
//
// WHY this exists — two guarantees the Ralph loop needs from every browser it opens:
//   1. ALWAYS CLOSED. Callers wrap their browser use in `try { … } finally { await browser.close() }`
//      so a thrown error mid-capture can never leak an orphaned Chromium (the zombie problem).
//   2. IDENTIFIABLE + SCOPED. We tag the process with an inert marker switch so scripts/ralph.sh
//      can reap any browser a crashed/killed iteration left behind — WITHOUT ever touching the
//      chrome-devtools MCP's Chrome, the user's own browser, or a different loop's instances.
//      The tag is run-scoped (RALPH_CHROMIUM_TAG, exported per-run by ralph.sh) so a loop only
//      ever reaps browsers IT spawned; standalone (non-loop) runs fall back to a static marker.
//      Chrome ignores unknown switches, so the marker changes nothing about how the page renders.
//
// All harness browser launches MUST go through here — one launch path = one thing to reap.
import { chromium } from 'playwright';

// Per-run tag exported by ralph.sh, else a static fallback for standalone invocations.
export const CHROMIUM_TAG = process.env.RALPH_CHROMIUM_TAG || 'ralph-managed-chromium';

// Launch a marked Chromium. `opts` is forwarded to chromium.launch(); our marker switch is
// prepended to any caller-supplied args. The CALLER owns the lifecycle — close it in a finally.
export function launchChromium(opts = {}) {
  const { args = [], ...rest } = opts;
  return chromium.launch({ args: [`--${CHROMIUM_TAG}`, ...args], ...rest });
}
