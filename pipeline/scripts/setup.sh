#!/usr/bin/env bash
# =============================================================================
# setup.sh — Next-Gen Installer & Infrastructure Sync for Enterprise Pipeline
# 
# Usage:
#   ./pipeline/setup.sh /path/to/target-proj              # Install or update infrastructure
#   ./pipeline/setup.sh /path/to/target-proj --override   # Force-overwrite all infrastructure & agents
#   ./pipeline/setup.sh /path/to/target-proj --override-all # Force-overwrite everything including context
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_DIR="${1:-.}"
OVERRIDE_ALL=false

for arg in "$@"; do
  case "$arg" in
    --override-all) OVERRIDE_ALL=true ;;
    --override|--force|-f) ;; # Handled by default overwrite of infra
  esac
done

# Shift target if first arg is not an option
if [[ "$TARGET_DIR" == --* ]]; then
  TARGET_DIR="."
fi

mkdir -p "${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

# Normalize TARGET_DIR if user passed a path ending in /pipeline
if [[ "${TARGET_DIR}" == */pipeline ]]; then
  TARGET_DIR="$(dirname "${TARGET_DIR}")"
fi

echo "🚀 Installing / Updating Enterprise Agent Pipeline into: [${TARGET_DIR}]..."

# 1. Copy / Update pipeline directory
if [[ "${PIPELINE_DIR}" != "${TARGET_DIR}/pipeline" ]]; then
  echo "📦 Updating pipeline infrastructure (scripts, core protocols, presets, engine, prompts)..."
  mkdir -p "${TARGET_DIR}/pipeline"

  if [[ -d "${TARGET_DIR}/pipeline/docs/context" ]] && [[ "$OVERRIDE_ALL" == false ]]; then
    # Preserve existing context while updating infrastructure
    echo "🛡️ Preserving existing project context (PROJECT_BRIEF.md, Tasks_list.md)..."
    TMP_CONTEXT="$(mktemp -d)"
    cp -r "${TARGET_DIR}/pipeline/docs/context"/* "$TMP_CONTEXT/" 2>/dev/null || true
    
    cp -r "${PIPELINE_DIR}"/. "${TARGET_DIR}/pipeline/"
    
    mkdir -p "${TARGET_DIR}/pipeline/docs/context"
    cp -r "$TMP_CONTEXT"/* "${TARGET_DIR}/pipeline/docs/context/" 2>/dev/null || true
    rm -rf "$TMP_CONTEXT"
    echo "✅ Infrastructure updated, project context preserved."
  else
    if [[ "$OVERRIDE_ALL" == true ]]; then
      echo "⚠️ --override-all specified: Overwriting entire pipeline including context files."
    fi
    cp -r "${PIPELINE_DIR}"/. "${TARGET_DIR}/pipeline/"
  fi

  # Purge any cache or runtime residue from target pipeline template
  echo "🧹 Ensuring target pipeline is clean (no cache, no temporary logs)..."
  find "${TARGET_DIR}/pipeline" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
  rm -rf "${TARGET_DIR}/pipeline/.ralph" \
         "${TARGET_DIR}/pipeline/docs/runtime/session_*.log" \
         "${TARGET_DIR}/pipeline/docs/runtime/PLAN_SEAL.sha256" \
         "${TARGET_DIR}/pipeline/docs/runtime/ITERATIONS"/iter_*.md 2>/dev/null || true
fi

# 2. Update .agents configuration directory in target (ALWAYS OVERRIDE TO ENSURE FRESH ROUTER)
echo "📦 Updating .agents router adapter and CLAUDE.md..."
mkdir -p "${TARGET_DIR}/.agents"
if [[ -f "${PIPELINE_DIR}/.agents/AGENTS.md" ]]; then
  cp -f "${PIPELINE_DIR}/.agents/AGENTS.md" "${TARGET_DIR}/.agents/AGENTS.md"
fi
if [[ -f "${PIPELINE_DIR}/CLAUDE.md" ]]; then
  cp -f "${PIPELINE_DIR}/CLAUDE.md" "${TARGET_DIR}/CLAUDE.md"
fi

# 3. Make CLI scripts executable
if [[ -d "${TARGET_DIR}/pipeline/scripts" ]]; then
  chmod +x "${TARGET_DIR}/pipeline/scripts/"*.sh "${TARGET_DIR}/pipeline/scripts/"*.py "${TARGET_DIR}/pipeline/scripts/"*.mjs 2>/dev/null || true
fi

# 4. Overwrite / Update root convenience wrapper harness.sh
ROOT_HARNESS="${TARGET_DIR}/harness.sh"
echo "🔗 Updating root convenience wrapper harness.sh..."
cat << 'EOF' > "${ROOT_HARNESS}"
#!/usr/bin/env bash
exec "$(dirname "$0")/pipeline/scripts/harness.sh" "$@"
EOF
chmod +x "${ROOT_HARNESS}"

# 5. Overwrite / Update pipeline/setup.sh wrapper
PIPELINE_SETUP="${TARGET_DIR}/pipeline/setup.sh"
cat << 'EOF' > "${PIPELINE_SETUP}"
#!/usr/bin/env bash
exec "$(dirname "$0")/scripts/setup.sh" "$@"
EOF
chmod +x "${PIPELINE_SETUP}"

# 6. Initialize pyproject.toml if missing
PYPROJECT="${TARGET_DIR}/pyproject.toml"
if [[ ! -f "${PYPROJECT}" ]]; then
  echo "📝 Initializing base pyproject.toml for pipeline dependencies..."
  cat << 'EOF' > "${PYPROJECT}"
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "enterprise-agent-pipeline-project"
version = "0.1.0"
description = "Project configured with Enterprise Agent Pipeline"
readme = "README.md"
requires-python = ">=3.10"
dependencies = [
    "pydantic>=2.0.0",
    "httpx>=0.24.0",
    "ruff>=0.1.0",
    "mypy>=1.0.0",
    "pytest>=7.0.0",
    "bandit>=1.7.0"
]

[tool.ruff]
line-length = 100
target-version = "py310"

[tool.mypy]
python_version = "3.10"
warn_return_any = true
warn_unused_configs = true
ignore_missing_imports = true

[tool.pytest.ini_options]
testpaths = ["pipeline/tests", "tests"]
python_files = "test_*.py"
EOF
fi

# 7. Create .gitignore entries if needed
GITIGNORE="${TARGET_DIR}/.gitignore"
if [[ -f "${GITIGNORE}" ]]; then
  if ! grep -q "\.ralph" "${GITIGNORE}"; then
    echo "" >> "${GITIGNORE}"
    echo "# Agent Pipeline Run Logs & State" >> "${GITIGNORE}"
    echo "pipeline/.ralph/" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/session_*.jsonl" >> "${GITIGNORE}"
  fi
fi

echo ""
echo "✅ Pipeline successfully installed / updated!"
echo "💡 To test harness offline (0 token): ${TARGET_DIR}/pipeline/scripts/selftest.sh"
echo "💡 To run autonomous loop: ${TARGET_DIR}/harness.sh"
