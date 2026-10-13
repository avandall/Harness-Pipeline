#!/usr/bin/env bash
# =============================================================================
# setup.sh — Cross-Platform Installer & Infrastructure Sync for Enterprise Pipeline
# Works on Linux, WSL, macOS, and Windows Git Bash (MINGW64 / MSYS2).
#
# Usage:
#   ./pipeline/scripts/setup.sh /path/to/target-proj              # Install or update infrastructure
#   ./pipeline/scripts/setup.sh /path/to/target-proj --override   # Force-overwrite all infrastructure & agents
#   ./pipeline/scripts/setup.sh /path/to/target-proj --override-all # Force-overwrite everything including context
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

# Normalize Windows-style paths (e.g., D:\... -> D:/...)
TARGET_DIR="${TARGET_DIR//\\//}"

# If running inside WSL and user passes a Windows drive path (e.g. D:/...), translate with wslpath
if command -v wslpath >/dev/null 2>&1 && [[ "$TARGET_DIR" =~ ^[A-Za-z]:/ ]]; then
  TARGET_DIR="$(wslpath -u "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")"
fi

mkdir -p "${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

# Normalize TARGET_DIR if user passed a path ending in /pipeline
if [[ "${TARGET_DIR}" == */pipeline ]]; then
  TARGET_DIR="$(dirname "${TARGET_DIR}")"
fi

echo "🚀 [SETUP] Installing / Updating pipeline -> [${TARGET_DIR}]..."

# 1. Copy / Update pipeline directory
if [[ "${PIPELINE_DIR}" != "${TARGET_DIR}/pipeline" ]]; then
  mkdir -p "${TARGET_DIR}/pipeline"

  # Core infrastructure directories
  for dir_name in "engine" "presets" "prompts" "scripts" "tests"; do
    if [[ -d "${PIPELINE_DIR}/${dir_name}" ]]; then
      mkdir -p "${TARGET_DIR}/pipeline/${dir_name}"
      cp -rf "${PIPELINE_DIR}/${dir_name}"/* "${TARGET_DIR}/pipeline/${dir_name}/" 2>/dev/null || true
    fi
  done

  # Documentation: Core protocols (Always synchronized)
  mkdir -p "${TARGET_DIR}/pipeline/docs/core"
  if [[ -d "${PIPELINE_DIR}/docs/core" ]]; then
    cp -rf "${PIPELINE_DIR}/docs/core"/* "${TARGET_DIR}/pipeline/docs/core/" 2>/dev/null || true
  fi

  # Documentation: Root doc files
  for doc_file in "README.md" "validation-status.md"; do
    if [[ -f "${PIPELINE_DIR}/docs/${doc_file}" ]]; then
      cp -f "${PIPELINE_DIR}/docs/${doc_file}" "${TARGET_DIR}/pipeline/docs/${doc_file}" 2>/dev/null || true
    fi
  done

  # Documentation: Project Context (Preserve existing unless --override-all)
  mkdir -p "${TARGET_DIR}/pipeline/docs/context"
  if [[ -d "${PIPELINE_DIR}/docs/context" ]]; then
    if [[ "$OVERRIDE_ALL" == true ]]; then
      echo "⚠️ [SETUP] Overwriting project context with fresh templates (--override-all)"
      cp -rf "${PIPELINE_DIR}/docs/context"/* "${TARGET_DIR}/pipeline/docs/context/" 2>/dev/null || true
    else
      for f in "${PIPELINE_DIR}/docs/context"/*.md; do
        if [[ -f "$f" ]]; then
          base_name="$(basename "$f")"
          existing_path=""
          for candidate in \
            "${TARGET_DIR}/pipeline/docs/context/${base_name}" \
            "${TARGET_DIR}/pipeline/context/docs/${base_name}" \
            "${TARGET_DIR}/context/docs/${base_name}" \
            "${TARGET_DIR}/docs/context/${base_name}"; do
            if [[ -f "$candidate" ]]; then
              existing_path="$candidate"
              break
            fi
          done

          if [[ -n "$existing_path" ]]; then
            if [[ "$existing_path" != "${TARGET_DIR}/pipeline/docs/context/${base_name}" ]]; then
              cp -f "$existing_path" "${TARGET_DIR}/pipeline/docs/context/${base_name}" 2>/dev/null || true
            fi
          else
            cp -f "$f" "${TARGET_DIR}/pipeline/docs/context/${base_name}" 2>/dev/null || true
          fi
        fi
      done
      echo "🛡️ [SETUP] Context preserved (0 user files replaced)"
    fi
  fi

  # Documentation: Runtime directories (Clean skeleton, NEVER copy symlinks or run histories)
  mkdir -p "${TARGET_DIR}/pipeline/docs/runtime/BLOCKERS" \
           "${TARGET_DIR}/pipeline/docs/runtime/ITERATIONS"
  if [[ -d "${PIPELINE_DIR}/docs/runtime" ]]; then
    for f in "${PIPELINE_DIR}/docs/runtime"/*.md; do
      if [[ -f "$f" ]]; then
        base_name="$(basename "$f")"
        if [[ ! -f "${TARGET_DIR}/pipeline/docs/runtime/${base_name}" ]] || [[ "$OVERRIDE_ALL" == true ]]; then
          cp -f "$f" "${TARGET_DIR}/pipeline/docs/runtime/${base_name}" 2>/dev/null || true
        fi
      fi
    done
  fi

  # Root pipeline files
  for root_file in "AGENT_GUIDE.md" "CLAUDE.md" "LEARNINGS.md" "PIPELINE_UPGRADE_SUMMARY.md" "USER_GUIDE.md" "setup.sh"; do
    if [[ -f "${PIPELINE_DIR}/${root_file}" ]]; then
      cp -f "${PIPELINE_DIR}/${root_file}" "${TARGET_DIR}/pipeline/${root_file}" 2>/dev/null || true
    fi
  done

  # Purge any cache or Windows zone residue from target pipeline
  echo "🧹 Ensuring target pipeline is clean (no cache, no temporary logs)..."
  find "${TARGET_DIR}/pipeline" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
  find "${TARGET_DIR}/pipeline" -type f -name "*:Zone.Identifier" -delete 2>/dev/null || true
  rm -rf "${TARGET_DIR}/pipeline/.ralph" \
         "${TARGET_DIR}/pipeline/docs/runtime/CURRENT" \
         "${TARGET_DIR}/pipeline/docs/runtime/PREV" \
         "${TARGET_DIR}/pipeline/docs/runtime/runs" \
         "${TARGET_DIR}/pipeline/docs/runtime/session_*.log" \
         "${TARGET_DIR}/pipeline/docs/runtime/session_*.jsonl" \
         "${TARGET_DIR}/pipeline/docs/runtime/PLAN_SEAL.sha256" \
         "${TARGET_DIR}/pipeline/docs/runtime/PLAN_SEAL_COMMIT" \
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
chmod +x "${ROOT_HARNESS}" 2>/dev/null || true

# 5. Overwrite / Update pipeline/setup.sh wrapper
PIPELINE_SETUP="${TARGET_DIR}/pipeline/setup.sh"
cat << 'EOF' > "${PIPELINE_SETUP}"
#!/usr/bin/env bash
exec "$(dirname "$0")/scripts/setup.sh" "$@"
EOF
chmod +x "${PIPELINE_SETUP}" 2>/dev/null || true

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
  if ! grep -q "\.ralph" "${GITIGNORE}" 2>/dev/null; then
    echo "" >> "${GITIGNORE}"
    echo "# Agent Pipeline Run Logs & State" >> "${GITIGNORE}"
    echo "pipeline/.ralph/" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/session_*.jsonl" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/CURRENT" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/PREV" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/runs/" >> "${GITIGNORE}"
  fi
  if ! grep -q "\.venv" "${GITIGNORE}" 2>/dev/null; then
    echo ".venv/" >> "${GITIGNORE}"
  fi
fi

# 8. Ensure virtual environment & sync dependencies via uv
if command -v uv >/dev/null 2>&1; then
  if [[ ! -d "${TARGET_DIR}/.venv" ]]; then
    uv venv "${TARGET_DIR}/.venv" 2>/dev/null || true
  fi

  # Detect Python executable location (Linux/WSL uses .venv/bin/python, Windows uses .venv/Scripts/python.exe)
  VENV_PYTHON=""
  if [[ -f "${TARGET_DIR}/.venv/bin/python" ]]; then
    VENV_PYTHON="${TARGET_DIR}/.venv/bin/python"
  elif [[ -f "${TARGET_DIR}/.venv/Scripts/python.exe" ]]; then
    VENV_PYTHON="${TARGET_DIR}/.venv/Scripts/python.exe"
  elif [[ -f "${TARGET_DIR}/.venv/Scripts/python" ]]; then
    VENV_PYTHON="${TARGET_DIR}/.venv/Scripts/python"
  fi

  UV_INSTALL_ARGS=()
  if [[ -n "$VENV_PYTHON" ]]; then
    UV_INSTALL_ARGS=("--python" "$VENV_PYTHON")
  fi

  if [[ -f "${TARGET_DIR}/pyproject.toml" ]]; then
    uv pip install "${UV_INSTALL_ARGS[@]}" -e "${TARGET_DIR}" 2>/dev/null || true
  fi
  if [[ -f "${TARGET_DIR}/requirements.txt" ]]; then
    uv pip install "${UV_INSTALL_ARGS[@]}" -r "${TARGET_DIR}/requirements.txt" 2>/dev/null || true
  fi
else
  echo "⚠️ [UV] 'uv' CLI not found. Install uv for dependency management."
fi

echo "✅ [SETUP] Complete -> ${TARGET_DIR} (.venv synced)"
echo "💡 Run harness: ${TARGET_DIR}/pipeline/scripts/harness.sh"
