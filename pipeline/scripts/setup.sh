#!/usr/bin/env bash
# =============================================================================
# setup.sh — Single-Command Installer & Onboarding for Enterprise Agent Pipeline
# 
# Usage:
#   ./pipeline/setup.sh                       # Setup in current directory
#   ./pipeline/setup.sh /path/to/target-proj   # Install pipeline into target project
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${PIPELINE_DIR}/.." && pwd)"

TARGET_DIR="${1:-.}"
mkdir -p "${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

# Normalize TARGET_DIR if user passed a path ending in /pipeline
if [[ "${TARGET_DIR}" == */pipeline ]]; then
  TARGET_DIR="$(dirname "${TARGET_DIR}")"
fi

echo "🚀 Installing Enterprise Agent Pipeline into: [${TARGET_DIR}]..."


# 1. Copy pipeline directory if target is different from source
if [[ "${PIPELINE_DIR}" != "${TARGET_DIR}/pipeline" ]]; then
  echo "📦 Copying pipeline infrastructure..."
  mkdir -p "${TARGET_DIR}/pipeline"
  cp -r "${PIPELINE_DIR}"/. "${TARGET_DIR}/pipeline/"
fi

# 1b. Copy .agents configuration directory if not existing in target
AGENTS_SRC=""
if [[ -d "${REPO_DIR}/.agents" ]]; then
  AGENTS_SRC="${REPO_DIR}/.agents"
elif [[ -d "${PIPELINE_DIR}/.agents" ]]; then
  AGENTS_SRC="${PIPELINE_DIR}/.agents"
fi

if [[ -n "${AGENTS_SRC}" ]]; then
  if [[ ! -d "${TARGET_DIR}/.agents" ]]; then
    echo "📦 Copying .agents configuration..."
    mkdir -p "${TARGET_DIR}/.agents"
    cp -r "${AGENTS_SRC}"/. "${TARGET_DIR}/.agents/"
  else
    echo "⏩ .agents directory already exists in target, skipping..."
  fi
fi

# 2. Make CLI scripts executable
if [[ -d "${TARGET_DIR}/pipeline/scripts" ]]; then
  chmod +x "${TARGET_DIR}/pipeline/scripts/"* 2>/dev/null || true
fi

# 3. Create root convenience wrapper harness.sh if not existing
ROOT_HARNESS="${TARGET_DIR}/harness.sh"
if [[ ! -f "${ROOT_HARNESS}" ]]; then
  echo "🔗 Creating root convenience wrapper harness.sh..."
  cat << 'EOF' > "${ROOT_HARNESS}"
#!/usr/bin/env bash
exec "$(dirname "$0")/pipeline/scripts/harness.sh" "$@"
EOF
  chmod +x "${ROOT_HARNESS}"
fi

# 4. Create pipeline/setup.sh wrapper if not existing
PIPELINE_SETUP="${TARGET_DIR}/pipeline/setup.sh"
if [[ ! -f "${PIPELINE_SETUP}" ]]; then
  cat << 'EOF' > "${PIPELINE_SETUP}"
#!/usr/bin/env bash
exec "$(dirname "$0")/scripts/setup.sh" "$@"
EOF
  chmod +x "${PIPELINE_SETUP}"
fi

# Also ensure pipeline/setup.sh exists in source if we ran in source
SOURCE_PIPELINE_SETUP="${PIPELINE_DIR}/setup.sh"
if [[ ! -f "${SOURCE_PIPELINE_SETUP}" ]]; then
  cat << 'EOF' > "${SOURCE_PIPELINE_SETUP}"
#!/usr/bin/env bash
exec "$(dirname "$0")/scripts/setup.sh" "$@"
EOF
  chmod +x "${SOURCE_PIPELINE_SETUP}"
fi

# 5. Create root convenience wrapper bin/agent-run if not existing
mkdir -p "${TARGET_DIR}/bin"
ROOT_AGENT_RUN="${TARGET_DIR}/bin/agent-run"
if [[ ! -f "${ROOT_AGENT_RUN}" ]]; then
  echo "🔗 Creating root convenience wrapper bin/agent-run..."
  cat << 'EOF' > "${ROOT_AGENT_RUN}"
#!/usr/bin/env bash
exec python3 "$(dirname "$0")/../pipeline/scripts/agent-run" "$@"
EOF
  chmod +x "${ROOT_AGENT_RUN}"
fi



# 6. Create base pyproject.toml if not existing in target project root
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
    "bandit>=1.7.0",
    "opentelemetry-api>=1.20.0",
    "opentelemetry-sdk>=1.20.0"
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
  if ! grep -q "session_\*\.jsonl" "${GITIGNORE}"; then
    echo "" >> "${GITIGNORE}"
    echo "# Agent Pipeline Logs" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/session_*.jsonl" >> "${GITIGNORE}"
  fi
fi

echo "✅ Pipeline successfully installed!"
echo ""
echo "📋 Next steps:"
echo "  1. Edit pipeline/docs/context/PROJECT_BRIEF.md with your project goal."
echo "  2. Preset Language Selector (default: python_backend):"
echo "     • Python:     active_preset: \"python_backend\""
echo "     • Node/React: active_preset: \"node_react\""
echo "     • Go:         active_preset: \"go_backend\""
echo "     • Polyglot:   active_preset: \"polyglot_multi\" (Auto-detects Python+Node+Go)"
echo "     (Change in pipeline/presets/active_preset.yaml)"
echo "  3. Edit pipeline/docs/context/Tasks_list.md with your task queue."
echo "  4. Run: ./harness.sh"


