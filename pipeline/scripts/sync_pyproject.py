#!/usr/bin/env python3
"""
sync_pyproject.py — Ensure pipeline tools and configurations are present in pyproject.toml
"""
import re
import sys
from pathlib import Path

REQUIRED_DEPS = [
    ("ruff", "ruff>=0.1.0"),
    ("mypy", "mypy>=1.0.0"),
    ("pytest", "pytest>=7.0.0"),
    ("bandit", "bandit>=1.7.0"),
]

BASE_PYPROJECT_TEMPLATE = """[build-system]
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
"""

def sync_pyproject(target_file: Path) -> None:
    if not target_file.exists():
        print(f"📝 Initializing new base pyproject.toml at: {target_file}")
        target_file.write_text(BASE_PYPROJECT_TEMPLATE, encoding="utf-8")
        return

    content = target_file.read_text(encoding="utf-8")
    modified = False

    # 1. Check & append missing tool packages
    # Pattern to detect PEP 621 dependencies = [ ... ]
    dep_pattern = re.compile(r"(dependencies\s*=\s*\[)(.*?)(\])", re.DOTALL)
    m = dep_pattern.search(content)

    if m:
        prefix = m.group(1)
        inner = m.group(2)
        suffix = m.group(3)

        missing = []
        for name, spec in REQUIRED_DEPS:
            # Check if name is present inside the dependencies array
            if not re.search(rf'["\']{re.escape(name)}(\s*[><=~^!].*?)?["\']', inner):
                missing.append(spec)

        if missing:
            lines = [line.rstrip() for line in inner.splitlines() if line.strip()]
            for spec in missing:
                lines.append(f'    "{spec}",')
            new_inner = "\n" + "\n".join(lines) + "\n"
            content = content[:m.start()] + prefix + new_inner + suffix + content[m.end():]
            modified = True
            print(f"📦 Added missing dependencies to pyproject.toml: {', '.join(missing)}")
    else:
        # Check if packages exist anywhere in pyproject.toml
        missing = [spec for name, spec in REQUIRED_DEPS if name not in content]
        if missing and "[project.optional-dependencies]" not in content:
            items = "\n".join(f'    "{spec}",' for spec in missing)
            content += f"\n[project.optional-dependencies]\npipeline = [\n{items}\n]\n"
            modified = True
            print(f"📦 Appended [project.optional-dependencies] with: {', '.join(missing)}")

    # 2. Check & append tool configuration tables
    if "[tool.ruff]" not in content:
        content += '\n[tool.ruff]\nline-length = 100\ntarget-version = "py310"\n'
        modified = True
        print("⚙️ Appended missing [tool.ruff] configuration")

    if "[tool.mypy]" not in content:
        content += (
            '\n[tool.mypy]\npython_version = "3.10"\n'
            'warn_return_any = true\nwarn_unused_configs = true\nignore_missing_imports = true\n'
        )
        modified = True
        print("⚙️ Appended missing [tool.mypy] configuration")

    if "[tool.pytest.ini_options]" not in content and "[tool.pytest]" not in content:
        content += (
            '\n[tool.pytest.ini_options]\n'
            'testpaths = ["pipeline/tests", "tests"]\n'
            'python_files = "test_*.py"\n'
        )
        modified = True
        print("⚙️ Appended missing [tool.pytest.ini_options] configuration")

    if modified:
        target_file.write_text(content, encoding="utf-8")
        print(f"✅ Successfully synced pipeline tools into: {target_file}")
    else:
        print(f"ℹ️ All pipeline tools and configurations already present in: {target_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: sync_pyproject.py <path-to-pyproject.toml>")
        sys.exit(1)
    sync_pyproject(Path(sys.argv[1]))
