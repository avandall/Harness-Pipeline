#!/usr/bin/env bash
# Sync the theme from `main` (or $1) onto the theme-only `shopify-theme` branch — the branch the
# Shopify GitHub integration ("Online Store > Themes > Add theme > Connect from GitHub") reads.
#
# WHY THIS SCRIPT EXISTS (a harness-engineering pattern: keep the PRODUCT and the HARNESS apart):
#   - This repo keeps the theme under `theme/` and the harness (docs, prompts, scripts, evidence)
#     around it. The Shopify GitHub integration only connects branches whose ROOT matches the
#     theme folder structure (assets/ config/ layout/ locales/ sections/ snippets/ templates/
#     blocks/) — folders that don't match are ignored, and a subdirectory cannot be selected.
#   - So the connected branch must contain ONLY `theme/`'s contents at its root. `main` stays the
#     full project; this script copies just the theme onto `shopify-theme`. `main` is the truth.
#
# SAFETY: this script ONLY ever touches the theme paths below — never `git add -A`/`git add .` —
# so `.env` or any harness file can never leak onto the connected branch. It is a GO-LIVE tool:
# dev builds deploy to the unpublished theme with `shopify theme push --theme $SHOPIFY_THEME_ID`;
# the runner calls this only with RALPH_SYNC_LIVE=1 (see scripts/ralph.sh).
#
# NOTE on two-way sync: if someone edits the connected theme in the Shopify admin/theme editor,
# Shopify commits those edits back to `shopify-theme`. This script OVERWRITES the theme with
# `main`'s — pull such edits into `main` first, or treat `main` as the only place you edit.
#
# Usage:  scripts/sync-theme-branch.sh [source-branch]      (default: main)
set -euo pipefail
THEME_DIR="theme"   # the theme lives in a subfolder on main; it must sit at the ROOT of the connected branch
SRC="${1:-main}"
BR="shopify-theme"

# refuse to run with uncommitted TRACKED changes (untracked like .env are fine)
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ commit/stash your tracked changes first"; exit 1; }

SRC_COMMIT="$(git rev-parse --verify "${SRC}^{commit}")"
git fetch -q origin "$BR"                                # pick up anything Shopify pushed back
TARGET="origin/$BR"
git rev-parse --verify "$TARGET" >/dev/null 2>&1 || TARGET="$BR"
WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/shopify-theme-sync.XXXXXX")"
cleanup() { git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git worktree add -q --detach "$WORKTREE" "$TARGET"
cd "$WORKTREE"

# make the theme on this branch EXACTLY match SRC's theme/ (adds, edits, AND deletes) — theme paths only.
# `git read-tree --prefix` is not used because we need theme/ contents at the branch ROOT; so we
# delete the known theme folders, then extract SRC's theme/ subtree into the worktree root.
for d in assets blocks config layout locales sections snippets templates; do git rm -rq --ignore-unmatch "$d" 2>/dev/null || true; done
git archive "$SRC_COMMIT" "$THEME_DIR" | tar -x --strip-components=1 -C "$WORKTREE"
for d in assets blocks config layout locales sections snippets templates; do [ -e "$d" ] && git add -- "$d"; done

if git diff --cached --quiet; then
  echo "✓ $BR theme already matches $SRC — nothing to push"
else
  git commit -q -m "Sync theme from $SRC"
  git push -q origin "HEAD:$BR"
  echo "✓ synced theme: $SRC → $BR (pushed). Shopify will pick it up."
fi
