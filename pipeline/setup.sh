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
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

echo "🚀 Installing Enterprise Agent Pipeline into: [${TARGET_DIR}]..."

# 1. Copy pipeline directory if target is different from source
if [[ "${SCRIPT_DIR}" != "${TARGET_DIR}/pipeline" ]]; then
  echo "📦 Copying pipeline infrastructure..."
  mkdir -p "${TARGET_DIR}/pipeline"
  cp -r "${SCRIPT_DIR}"/* "${TARGET_DIR}/pipeline/"
fi

# 2. Make CLI scripts executable
chmod +x "${TARGET_DIR}/pipeline/bin/agent-run" 2>/dev/null || true
chmod +x "${TARGET_DIR}/pipeline/docs/harness.sh" 2>/dev/null || true
chmod +x "${TARGET_DIR}/pipeline/docs/scripts/verify.py" 2>/dev/null || true

# 3. Create root convenience wrapper harness.sh if not existing
ROOT_HARNESS="${TARGET_DIR}/harness.sh"
if [[ ! -f "${ROOT_HARNESS}" ]]; then
  echo "🔗 Creating root convenience wrapper harness.sh..."
  cat << 'EOF' > "${ROOT_HARNESS}"
#!/usr/bin/env bash
exec "$(dirname "$0")/pipeline/docs/harness.sh" "$@"
EOF
  chmod +x "${ROOT_HARNESS}"
fi

# 4. Create root convenience wrapper bin/agent-run if not existing
mkdir -p "${TARGET_DIR}/bin"
ROOT_AGENT_RUN="${TARGET_DIR}/bin/agent-run"
if [[ ! -f "${ROOT_AGENT_RUN}" ]]; then
  echo "🔗 Creating root convenience wrapper bin/agent-run..."
  cat << 'EOF' > "${ROOT_AGENT_RUN}"
#!/usr/bin/env bash
exec python3 "$(dirname "$0")/../pipeline/bin/agent-run" "$@"
EOF
  chmod +x "${ROOT_AGENT_RUN}"
fi

# 5. Create base pyproject.toml if not existing in target project root
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

# 6. Create .gitignore entries if needed
GITIGNORE="${TARGET_DIR}/.gitignore"
if [[ -f "${GITIGNORE}" ]]; then
  if ! grep -q "session_\*\.jsonl" "${GITIGNORE}"; then
    echo "" >> "${GITIGNORE}"
    echo "# Agent Pipeline Logs" >> "${GITIGNORE}"
    echo "pipeline/docs/runtime/session_*.jsonl" >> "${GITIGNORE}"
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

