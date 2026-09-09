#!/usr/bin/env bash
# =============================================================================
# plan.sh — Plan Sealer, Integrity Check & Auto-Restore (Harness Steps 3 & 4)
# Calculates, validates, and restores SHA-256 fingerprint over context specifications.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOCS_DIR="$ROOT/docs"
RUNTIME_DIR="$DOCS_DIR/runtime"
CONTEXT_DIR="$DOCS_DIR/context"
SEAL_FILE="$RUNTIME_DIR/PLAN_SEAL.sha256"
SEAL_COMMIT_FILE="$RUNTIME_DIR/PLAN_SEAL_COMMIT"

mkdir -p "$RUNTIME_DIR"

compute_seal() {
  local target_dir="${1:-$CONTEXT_DIR}"
  local count=0
  local hashes=()

  for f_name in "PROJECT_BRIEF.md" "Tasks_list.md" "BOUNDARIES.md" "TECH_CONTEXT.md"; do
    local f_path="$target_dir/$f_name"
    if [[ -f "$f_path" ]]; then
      ((count++))
      local file_hash
      if [[ "$f_name" == "Tasks_list.md" ]]; then
        file_hash="$(sed -E 's/\[[ xX/!]\]/[ ]/g; s/(DONE|IN_PROGRESS|BLOCKED)/TODO/g' "$f_path" | sha256sum | awk '{print $1}')"
      else
        file_hash="$(sha256sum "$f_path" | awk '{print $1}')"
      fi
      hashes+=("$file_hash")
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "NO_CONTEXT_FILES"
    return
  fi

  printf '%s\n' "${hashes[@]}" | sha256sum | awk '{print $1}'
}

compute_seal_from_git() {
  local commit="$1"
  local rel_context="$2"
  local count=0
  local hashes=()

  for f_name in "PROJECT_BRIEF.md" "Tasks_list.md" "BOUNDARIES.md" "TECH_CONTEXT.md"; do
    if git cat-file -e "${commit}:${rel_context}/${f_name}" 2>/dev/null; then
      ((count++))
      local file_hash
      if [[ "$f_name" == "Tasks_list.md" ]]; then
        file_hash="$(git show "${commit}:${rel_context}/${f_name}" | sed -E 's/\[[ xX/!]\]/[ ]/g; s/(DONE|IN_PROGRESS|BLOCKED)/TODO/g' | sha256sum | awk '{print $1}')"
      else
        file_hash="$(git show "${commit}:${rel_context}/${f_name}" | sha256sum | awk '{print $1}')"
      fi
      hashes+=("$file_hash")
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "NO_CONTEXT_FILES"
    return
  fi

  printf '%s\n' "${hashes[@]}" | sha256sum | awk '{print $1}'
}

restore_context() {
  if [[ ! -f "$SEAL_FILE" ]]; then
    echo "⚠️ [PLAN] No seal file found at $SEAL_FILE. Cannot restore."
    return 1
  fi
  local expected_hash
  expected_hash="$(head -n 1 "$SEAL_FILE" | tr -d '[:space:]')"

  local current_hash
  current_hash="$(compute_seal)"
  if [[ "$current_hash" == "$expected_hash" ]]; then
    echo "✅ [PLAN] Current context already matches plan seal."
    return 0
  fi

  echo "🔍 [PLAN] Searching git history for context matching seal ${expected_hash:0:16}..."

  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")"
  local rel_context
  if command -v realpath >/dev/null 2>&1; then
    rel_context="$(realpath --relative-to="$git_root" "$CONTEXT_DIR" 2>/dev/null || echo "pipeline/docs/context")"
  else
    rel_context="pipeline/docs/context"
    [[ -d "docs/context" ]] && rel_context="docs/context"
  fi

  # 1. Check if git HEAD matches (for uncommitted local changes)
  local head_hash
  head_hash="$(compute_seal_from_git "HEAD" "$rel_context")"
  if [[ "$head_hash" == "$expected_hash" ]]; then
    echo "🔄 [PLAN] Matching seal found at git HEAD. Reverting uncommitted modifications..."
    git checkout HEAD -- "$CONTEXT_DIR" 2>/dev/null || git checkout HEAD -- "$rel_context"
    echo "✅ [PLAN] Context specifications cleanly restored from git HEAD."
    return 0
  fi

  # 2. Check hint commit file if available
  if [[ -f "$SEAL_COMMIT_FILE" ]]; then
    local hint_commit
    hint_commit="$(cat "$SEAL_COMMIT_FILE" | tr -d '[:space:]')"
    if [[ -n "$hint_commit" ]] && git cat-file -e "${hint_commit}^{commit}" 2>/dev/null; then
      local hint_hash
      hint_hash="$(compute_seal_from_git "$hint_commit" "$rel_context")"
      if [[ "$hint_hash" == "$expected_hash" ]]; then
        echo "🔄 [PLAN] Found matching seal at hint commit ${hint_commit:0:9}. Restoring..."
        git checkout "$hint_commit" -- "$CONTEXT_DIR" 2>/dev/null || git checkout "$hint_commit" -- "$rel_context"
        echo "✅ [PLAN] Context specifications cleanly restored from git commit ${hint_commit:0:9}."
        return 0
      fi
    fi
  fi

  # 3. Scan git history (commits touching context dir)
  local commits=()
  while IFS= read -r c; do
    [[ -n "$c" ]] && commits+=("$c")
  done < <(git log -n 50 --format="%H" -- "$rel_context" 2>/dev/null || git rev-list -n 50 HEAD 2>/dev/null || true)

  for commit in "${commits[@]}"; do
    local c_hash
    c_hash="$(compute_seal_from_git "$commit" "$rel_context")"
    if [[ "$c_hash" == "$expected_hash" ]]; then
      echo "🔄 [PLAN] Found matching seal at git commit ${commit:0:9}. Restoring..."
      git checkout "$commit" -- "$CONTEXT_DIR" 2>/dev/null || git checkout "$commit" -- "$rel_context"
      echo "✅ [PLAN] Context specifications cleanly restored from git commit ${commit:0:9}."
      return 0
    fi
  done

  echo "❌ [PLAN] Could not find any commit in git history matching seal ${expected_hash:0:16}..."
  return 1
}

case "${1:-seal}" in
  seal)
    SEAL_HASH="$(compute_seal)"
    echo "$SEAL_HASH" > "$SEAL_FILE"
    CURRENT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
    if [[ -n "$CURRENT_COMMIT" ]]; then
      echo "$CURRENT_COMMIT" > "$SEAL_COMMIT_FILE"
    fi
    echo "🔒 [PLAN] Context specifications sealed with SHA-256: ${SEAL_HASH:0:16}..."
    ;;
  check)
    if [[ ! -f "$SEAL_FILE" ]]; then
      echo "⚠️ [PLAN] No seal file found at $SEAL_FILE (Unsealed Plan)."
      exit 0
    fi
    CURRENT_HASH="$(compute_seal)"
    EXPECTED_HASH="$(head -n 1 "$SEAL_FILE" | tr -d '[:space:]')"
    if [[ "$CURRENT_HASH" == "$EXPECTED_HASH" ]]; then
      echo "✅ [PLAN] Plan Seal Valid: ${CURRENT_HASH:0:16}... (No specification drift detected)"
      exit 0
    else
      echo "❌ [PLAN] SPECIFICATION DRIFT DETECTED!"
      echo "Expected: $EXPECTED_HASH"
      echo "Current:  $CURRENT_HASH"
      echo "Specifications were modified after plan seal. Run 'scripts/plan.sh restore' or 'scripts/plan.sh seal'."
      exit 1
    fi
    ;;
  restore)
    restore_context
    ;;
  refine|interview)
    shift || true
    exec "$ROOT/scripts/plan-refine.sh" "$@"
    ;;
  *)
    echo "Usage: scripts/plan.sh [seal|check|restore|refine]"
    exit 1
    ;;
esac
