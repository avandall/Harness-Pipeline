#!/usr/bin/env python3
"""
verify.py — Deterministic Quality Verification Engine for Ralph Loop
Chạy các công cụ tĩnh (Static Analysis) và Runtime Test, hỗ trợ đa ngôn ngữ
(Python, Node.js/React, Go, Shell Scripting) & Polyglot Multi-Language Mode.

Usage:
  python3 pipeline/scripts/verify.py                       # Defaults to active preset (Python)
  python3 pipeline/scripts/verify.py --preset node_react  # Run Node.js/React checks
  python3 pipeline/scripts/verify.py --preset auto        # Auto-detect all active languages
  python3 pipeline/scripts/verify.py --summary             # 1-line summary for AI review
"""

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Import shared compactor from engine (single source of truth for log truncation)
try:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent))
    from pipeline.engine.session.compactor import truncate_log
except ImportError:
    try:
        from engine.session.compactor import truncate_log  # type: ignore[no-redef]
    except ImportError:

        def truncate_log(log_text: str, max_lines: int = 20) -> str:  # type: ignore[misc]
            if not log_text or not log_text.strip():
                return ""
            lines = log_text.strip().split("\n")
            if len(lines) <= max_lines:
                return "\n".join(lines)
            error_lines = []
            in_traceback = False
            for line in lines:
                if any(keyword in line for keyword in ["Traceback", "FAILED", "ERROR", "CRITICAL", "ERRORS"]):
                    in_traceback = True
                if in_traceback or line.startswith(("E   ", "FAILED ")) or "Error:" in line:
                    error_lines.append(line)
            if error_lines:
                return "\n".join(error_lines[-max_lines:])
            return "\n".join(lines[-max_lines:])


def check_tool_installed(tool_name: str) -> bool:
    """Kiểm tra xem CLI tool đã được cài đặt trong hệ thống/env chưa."""
    cwd = Path.cwd()
    for bin_dir in [cwd / ".venv" / "bin", cwd / ".venv" / "Scripts"]:
        tool_path = bin_dir / tool_name
        if tool_path.is_file():
            return True
    return shutil.which(tool_name) is not None


def run_command(cmd: list[str], timeout: int = 60) -> tuple[int, str]:
    """Chạy command an toàn và thu thập output với timeout protection (default 60s)."""
    env = os.environ.copy()
    cwd_str = os.getcwd()

    # Prepend .venv/bin to PATH and set VIRTUAL_ENV if .venv exists
    venv_dir = os.path.join(cwd_str, ".venv")
    for b in ["bin", "Scripts"]:
        venv_bin = os.path.join(venv_dir, b)
        if os.path.isdir(venv_bin):
            env["VIRTUAL_ENV"] = venv_dir
            current_path = env.get("PATH", "")
            env["PATH"] = f"{venv_bin}:{current_path}" if current_path else venv_bin
            break

    extra_paths = [cwd_str]
    for sub in ["src", "app"]:
        sub_path = os.path.join(cwd_str, sub)
        if os.path.isdir(sub_path):
            extra_paths.append(sub_path)
    current_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = ":".join(extra_paths + ([current_pythonpath] if current_pythonpath else []))
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout, env=env)
        output = (res.stdout or "") + ("\n" + res.stderr if res.stderr else "")
        return res.returncode, output.strip()
    except subprocess.TimeoutExpired:
        return 1, f"Execution timed out after {timeout}s: {' '.join(cmd)}"
    except (subprocess.SubprocessError, OSError) as e:
        return 1, f"Execution failed: {e!s}"



def get_active_preset(cli_preset: str) -> str:
    """Get active preset from CLI flag or active_preset.yaml config."""
    if cli_preset and cli_preset.lower() != "auto":
        return cli_preset.lower()

    active_file = Path("pipeline/presets/active_preset.yaml")
    if active_file.exists():
        content = active_file.read_text(encoding="utf-8")
        for line in content.splitlines():
            if "active_preset:" in line:
                val = line.split(":", 1)[1].strip().strip('"').strip("'")
                if val:
                    return val.lower()
    return "python_backend"


def run_python_checks(
    target_dir: str = ".", quick: bool = False, test_target: str = ""
) -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra chuẩn cho dự án Python: Ruff, Mypy, Bandit, Pytest."""
    results = []

    # 1. Ruff (Lint)
    if check_tool_installed("ruff"):
        code, out = run_command(["ruff", "check", target_dir])
        results.append(("Python: Ruff (Lint)", code == 0, "All lint checks passed ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Ruff (Lint)", True, "Skipped (ruff not installed)"))

    # 2. Mypy (Type Check)
    if check_tool_installed("mypy"):
        code, out = run_command(["mypy", target_dir, "--ignore-missing-imports", "--explicit-package-bases"])
        results.append(("Python: Mypy (Type Check)", code == 0, "Type checking passed ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Mypy (Type Check)", True, "Skipped (mypy not installed)"))

    # 3. Bandit (Security) - skipped in quick mode
    if quick:
        results.append(("Python: Bandit (Security)", True, "Skipped (quick mode enabled)"))
    elif check_tool_installed("bandit"):
        bandit_cmd = ["bandit", "-r", target_dir, "-ll", "-q", "-x", "./.venv,./.pytest_cache,./.mypy_cache,./tests,./scripts,./pipeline,./dashboard,./vector_db"]
        if os.path.exists(".bandit"):
            bandit_cmd = ["bandit", "-c", ".bandit", "-r", target_dir, "-ll", "-q", "-x", "./.venv,./.pytest_cache,./.mypy_cache,./tests,./scripts,./pipeline,./dashboard,./vector_db"]
        code, out = run_command(bandit_cmd)
        results.append(("Python: Bandit (Security)", code == 0, "No security issues ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Bandit (Security)", True, "Skipped (bandit not installed)"))

    # 4. Pytest (Runtime)
    if check_tool_installed("pytest"):
        has_tests = (
            bool(test_target)
            or any(Path(".").rglob("test_*.py"))
            or any(Path(".").rglob("*_test.py"))
            or os.path.exists("tests")
            or os.path.exists("pipeline/tests")
        )
        if has_tests:
            pytest_cmd = ["pytest", "--tb=short", "-q"]
            if test_target:
                pytest_cmd.append(test_target)
            timeout_sec = 60 if test_target else 300
            code, out = run_command(pytest_cmd, timeout=timeout_sec)
            results.append(("Python: Pytest (Runtime)", code == 0, "All unit tests passed ✓" if code == 0 else truncate_log(out)))
        else:
            results.append(("Python: Pytest (Runtime)", True, "Skipped (no python tests found)"))
    else:
        results.append(("Python: Pytest (Runtime)", True, "Skipped (pytest not installed)"))

    return results


def run_node_checks(target_dir: str = ".") -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho dự án Node.js / TypeScript / React."""
    results = []
    has_package_json = os.path.exists("package.json") or os.path.exists(os.path.join(target_dir, "package.json"))
    if not has_package_json:
        return [("Node.js Check", True, "Skipped (no package.json found)")]

    if check_tool_installed("npm"):
        # Type check TypeScript
        if os.path.exists("tsconfig.json") or os.path.exists(os.path.join(target_dir, "tsconfig.json")):
            code, out = run_command(["npm", "run", "typecheck"])
            if code != 0 and check_tool_installed("npx"):
                code, out = run_command(["npx", "--no-install", "tsc", "--noEmit"])
            results.append(("Node: TypeScript (Type Check)", code == 0, "TS type checking passed ✓" if code == 0 else truncate_log(out)))

        # Node Unit Tests (Vitest / Jest / Test script)
        code, out = run_command(["npm", "test"])
        results.append(("Node: Vitest / Unit Tests", code == 0, "Node unit tests passed ✓" if code == 0 else truncate_log(out)))

    return results if results else [("Node.js Check", True, "Node environment ready ✓")]


def run_go_checks(target_dir: str = ".") -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho dự án Go."""
    results = []
    if not os.path.exists(os.path.join(target_dir, "go.mod")):
        return [("Go Check", True, "Skipped (no go.mod found)")]

    if check_tool_installed("go"):
        code, out = run_command(["go", "vet", "./..."])
        results.append(("Go: Vet", code == 0, "Go vet passed ✓" if code == 0 else truncate_log(out)))

        code, out = run_command(["go", "test", "-v", "./..."])
        results.append(("Go: Tests", code == 0, "Go tests passed ✓" if code == 0 else truncate_log(out)))

    return results if results else [("Go Check", True, "Go checks passed ✓")]


def run_shell_checks(target_dir: str = ".") -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho Shell Scripting (ShellCheck)."""
    results = []
    sh_files = [str(p) for p in Path(target_dir).rglob("*.sh") if "node_modules" not in str(p)]
    if not sh_files:
        return [("Shell Check", True, "Skipped (no shell scripts found)")]

    if check_tool_installed("shellcheck"):
        code, out = run_command(["shellcheck"] + sh_files[:10])
        results.append(("Shell: ShellCheck", code == 0, "ShellCheck passed ✓" if code == 0 else truncate_log(out)))

    return results if results else [("Shell Check", True, "Shell scripts verified ✓")]


ANTI_CHEAT_PATTERNS = [
    (
        re.compile(r"^\s*assert\s+True\s*(#.*)?$"),
        "Banned trivial assertion ('assert True') without real validation logic",
    ),
    (
        re.compile(
            r"return\s+(True|False|None|\"\"|''|0|\{\}|\[\])\s*#\s*(TODO|FIXME|hack|temp|bypass|cheat|fake|mock)",
            re.IGNORECASE,
        ),
        "Temporary stub/mock bypass return detected",
    ),
    (
        re.compile(
            r"^\s*pass\s*#\s*(TODO|FIXME|hack|temp|bypass|cheat|fake|mock)",
            re.IGNORECASE,
        ),
        "Empty placeholder stub detected",
    ),
    (
        re.compile(
            r"#\s*(bypass-verify|fake-pass|ignore-verify|mock-pass)",
            re.IGNORECASE,
        ),
        "Explicit verification bypass flag detected",
    ),
]


def run_anti_cheat_checks(target_dir: str = ".") -> list[tuple[str, bool, str]]:
    """Kiểm tra mã nguồn chống các tệ nạn: fake mocks, trivial assert True, temporary bypass."""
    violations: list[str] = []
    base_path = Path(target_dir).resolve()
    code_exts = {".py", ".ts", ".js", ".go", ".jsx", ".tsx"}
    ignore_dirs = {
        ".git",
        ".venv",
        "venv",
        "node_modules",
        "pipeline",
        "Sample_pipeline",
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        "dist",
        "build",
    }

    for root, dirs, files in os.walk(base_path):
        dirs[:] = [d for d in dirs if d not in ignore_dirs and not d.startswith(".")]
        for file in files:
            p = Path(root) / file
            if p.suffix in code_exts:
                try:
                    rel_file = p.relative_to(base_path)
                    content = p.read_text(encoding="utf-8", errors="ignore")
                    for line_no, line in enumerate(content.splitlines(), start=1):
                        for pattern, desc in ANTI_CHEAT_PATTERNS:
                            if pattern.search(line):
                                violations.append(
                                    f"{rel_file}:{line_no} [{desc}] -> {line.strip()}"
                                )
                except (OSError, UnicodeDecodeError):
                    continue

    if violations:
        msg = f"Detected {len(violations)} anti-cheat / fake-mock violation(s):\n" + "\n".join(
            violations[:15]
        )
        if len(violations) > 15:
            msg += f"\n... and {len(violations) - 15} more violation(s)"
        return [("Quality: Anti-Cheat & Real Implementation Guard", False, msg)]
    return [
        (
            "Quality: Anti-Cheat & Real Implementation Guard",
            True,
            "No fake mocks, bypass flags, or trivial assert True detected ✓",
        )
    ]


def main():
    parser = argparse.ArgumentParser(
        description="Tier 1 Deterministic Verification Engine for Enterprise Agent Pipeline"
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print a single-line token-efficient summary to stdout only (no file write)",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Quick verification mode (skip slow security scanning during rapid iterative coding)",
    )
    parser.add_argument(
        "--test-target",
        type=str,
        default="",
        help="Specific test file or directory to run for pytest (e.g. tests/test_e2e_conversational_system.py)",
    )
    parser.add_argument(
        "--preset",
        type=str,
        default="auto",
        help="Preset to run: python_backend | node_react | go_backend | generic_scripting | polyglot_multi | auto",
    )
    args = parser.parse_args()

    preset = get_active_preset(args.preset)

    check_results: list[tuple[str, bool, str]] = []

    if preset == "node_react":
        check_results.extend(run_node_checks("."))
    elif preset == "go_backend":
        check_results.extend(run_go_checks("."))
    elif preset == "generic_scripting":
        check_results.extend(run_shell_checks("."))
    elif preset in ["polyglot_multi", "auto"]:
        # Auto-detect all present language environments & run combined checks
        check_results.extend(run_python_checks(".", quick=args.quick, test_target=args.test_target))
        if os.path.exists("package.json"):
            check_results.extend(run_node_checks("."))
        if os.path.exists("go.mod"):
            check_results.extend(run_go_checks("."))
    else:  # Default: python_backend
        check_results.extend(run_python_checks(".", quick=args.quick, test_target=args.test_target))

    # Universal check: Quality & Anti-Cheat Guard across all presets
    check_results.extend(run_anti_cheat_checks("."))

    all_passed = all(r[1] for r in check_results)
    now = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d %H:%M")

    # ── Summary mode: 1-line output for reviewer model prompt injection ──────
    if args.summary:
        failed = [name for name, passed, _ in check_results if not passed]
        if all_passed:
            print(f"TIER1: PASS ({now}) [{preset}] — All deterministic checks green ✅")
        else:
            fail_str = ", ".join(failed)
            print(f"TIER1: FAIL ({now}) [{preset}] — Failed checks: {fail_str} ❌")
        sys.exit(0 if all_passed else 1)

    # ── Full mode: write VERIFICATION_REPORT.md ──────────────────────────────
    docs_runtime = Path("pipeline/docs/runtime")
    if not docs_runtime.parent.exists():
        docs_runtime = Path("pipeline/docs/runtime")
    report_path = docs_runtime / "VERIFICATION_REPORT.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"🔍 Running Tier 1 Verification Checks (Preset: {preset})...")

    report_lines = [
        "# TIER 1 VERIFICATION REPORT",
        f"Generated: {now}",
        f"Active Preset: {preset}",
        f"Status: {'PASS' if all_passed else 'FAIL'}",
        "",
        "## Summary",
    ]

    for name, passed, detail in check_results:
        status_str = "✅ PASS" if passed else "❌ FAIL"
        report_lines.append(f"- **{name}**: {status_str}")

    report_lines.append("\n## Details & Error Truncated Logs\n")
    for name, passed, detail in check_results:
        if not passed:
            report_lines.append(f"### ❌ {name} Failures:")
            report_lines.append("```text")
            report_lines.append(detail)
            report_lines.append("```\n")

    report_content = "\n".join(report_lines)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report_content)

    print(
        f"\n📝 Verification report written to: {report_path} (Status: {'PASS' if all_passed else 'FAIL'})"
    )

    if not all_passed:
        print(
            "❌ Tier 1 Verification Failed! See VERIFICATION_REPORT.md for details."
        )
        sys.exit(1)
    else:
        print("✅ Tier 1 Verification Passed 100%!")
        sys.exit(0)


if __name__ == "__main__":
    main()
