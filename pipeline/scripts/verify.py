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



def get_changed_files(base_ref: str | None = None) -> list[str]:
    """Retrieve list of modified/added files relative to base_ref and uncommitted changes.
    Returns relative paths from current working directory.
    """
    changed: set[str] = set()
    cwd = Path.cwd()

    try:
        # 1. Uncommitted / staged changes in working tree
        status_res = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            check=False,
            cwd=str(cwd),
        )
        if status_res.returncode == 0:
            for line in status_res.stdout.splitlines():
                if len(line) >= 3:
                    status_code = line[:2]
                    file_path = line[3:].strip()
                    if "->" in file_path:
                        file_path = file_path.split("->")[-1].strip()
                    if status_code not in (" D", "D "):
                        changed.add(file_path)

        # 2. Base reference comparison (branch/commit diff)
        target_ref = base_ref
        if target_ref == "auto" or not target_ref:
            for candidate in ["master", "main", "origin/master", "origin/main", "HEAD"]:
                check = subprocess.run(
                    ["git", "rev-parse", "--verify", candidate],
                    capture_output=True,
                    text=True,
                    check=False,
                    cwd=str(cwd),
                )
                if check.returncode == 0:
                    target_ref = candidate
                    break

        if target_ref and target_ref != "HEAD":
            diff_cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{target_ref}...HEAD"]
            diff_res = subprocess.run(
                diff_cmd,
                capture_output=True,
                text=True,
                check=False,
                cwd=str(cwd),
            )
            if diff_res.returncode != 0:
                diff_cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", target_ref]
                diff_res = subprocess.run(
                    diff_cmd,
                    capture_output=True,
                    text=True,
                    check=False,
                    cwd=str(cwd),
                )
            if diff_res.returncode == 0:
                for line in diff_res.stdout.splitlines():
                    if line.strip():
                        changed.add(line.strip())
    except Exception:
        pass

    valid_files: list[str] = []
    ignore_prefixes = (
        "pipeline/",
        ".pipeline/",
        "Sample_pipeline/",
        ".git/",
        ".venv/",
        "venv/",
        "node_modules/",
        "BLOCKERS/",
    )
    for f in changed:
        p = cwd / f
        if not any(f.startswith(pfx) for pfx in ignore_prefixes) and p.is_file():
            valid_files.append(f)

    return sorted(valid_files)


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
    target_dir: str = ".",
    quick: bool = False,
    test_target: str = "",
    tier: int = 2,
    changed_files: list[str] | None = None,
) -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra chuẩn cho dự án Python theo Tier (0, 1, 2) có hỗ trợ Diff-Aware."""
    results = []
    py_files = None
    if changed_files is not None:
        py_files = [f for f in changed_files if f.endswith(".py")]

    # 1. Ruff (Lint) - Luôn chạy cho Tier 0, 1, 2
    if check_tool_installed("ruff"):
        if py_files is not None and len(py_files) == 0:
            results.append(("Python: Ruff (Lint)", True, "Skipped (no modified python files in diff) ✓"))
        else:
            ruff_cmd = ["ruff", "check"] + (py_files if py_files is not None else [target_dir])
            code, out = run_command(ruff_cmd)
            results.append(("Python: Ruff (Lint)", code == 0, "All lint checks passed ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Ruff (Lint)", True, "Skipped (ruff not installed)"))

    # 2. Mypy (Type Check) - Luôn chạy cho Tier 0, 1, 2
    if check_tool_installed("mypy"):
        if py_files is not None and len(py_files) == 0:
            results.append(("Python: Mypy (Type Check)", True, "Skipped (no modified python files in diff) ✓"))
        else:
            mypy_cmd = ["mypy", "--ignore-missing-imports", "--explicit-package-bases"] + (py_files if py_files is not None else [target_dir])
            code, out = run_command(mypy_cmd)
            results.append(("Python: Mypy (Type Check)", code == 0, "Type checking passed ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Mypy (Type Check)", True, "Skipped (mypy not installed)"))

    # Tier 0 dừng ở Lint & Type Check (tức thì < 2s)
    if tier == 0:
        return results

    # 3. Pytest (Runtime) - Chạy ở Tier 1 và Tier 2
    if check_tool_installed("pytest"):
        has_tests = (
            bool(test_target)
            or any(Path(".").rglob("test_*.py"))
            or any(Path(".").rglob("*_test.py"))
            or os.path.exists("tests")
            or os.path.exists("pipeline/tests")
        )
        if has_tests:
            # Ở Tier 1: ưu tiên chạy nhanh (--tb=short -q -x --lf nếu có)
            pytest_cmd = ["pytest", "--tb=short", "-q"]
            if tier == 1:
                pytest_cmd.append("-x")  # Dừng ngay ở lỗi đầu tiên để feedback lặp nhanh
            if test_target:
                pytest_cmd.append(test_target)
            timeout_sec = 60 if test_target or tier == 1 else 300
            code, out = run_command(pytest_cmd, timeout=timeout_sec)
            results.append(("Python: Pytest (Runtime)", code == 0, "All unit tests passed ✓" if code == 0 else truncate_log(out)))
        else:
            results.append(("Python: Pytest (Runtime)", True, "Skipped (no python tests found)"))
    else:
        results.append(("Python: Pytest (Runtime)", True, "Skipped (pytest not installed)"))

    # Tier 1 dừng ở Unit Test, bỏ qua Security Scan nặng
    if tier == 1 or quick:
        results.append(("Python: Bandit (Security)", True, "Skipped (quick/tier-1 mode enabled)"))
        return results

    # 4. Bandit (Security) - Chỉ chạy ở Tier 2 (Full regression & security)
    if check_tool_installed("bandit"):
        if py_files is not None and len(py_files) == 0:
            results.append(("Python: Bandit (Security)", True, "Skipped (no modified python files in diff) ✓"))
        else:
            if py_files is not None:
                bandit_cmd = ["bandit", "-ll", "-q"] + py_files
                if os.path.exists(".bandit"):
                    bandit_cmd = ["bandit", "-c", ".bandit", "-ll", "-q"] + py_files
            else:
                bandit_cmd = ["bandit", "-r", target_dir, "-ll", "-q", "-x", "./.venv,./.pytest_cache,./.mypy_cache,./tests,./scripts,./pipeline,./dashboard,./vector_db"]
                if os.path.exists(".bandit"):
                    bandit_cmd = ["bandit", "-c", ".bandit", "-r", target_dir, "-ll", "-q", "-x", "./.venv,./.pytest_cache,./.mypy_cache,./tests,./scripts,./pipeline,./dashboard,./vector_db"]
            code, out = run_command(bandit_cmd)
            results.append(("Python: Bandit (Security)", code == 0, "No security issues ✓" if code == 0 else truncate_log(out)))
    else:
        results.append(("Python: Bandit (Security)", True, "Skipped (bandit not installed)"))

    return results


def run_node_checks(target_dir: str = ".", tier: int = 2) -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho dự án Node.js / TypeScript / React theo Tier."""
    results = []
    has_package_json = os.path.exists("package.json") or os.path.exists(os.path.join(target_dir, "package.json"))
    if not has_package_json:
        return [("Node.js Check", True, "Skipped (no package.json found)")]

    if check_tool_installed("npm"):
        # Type check TypeScript (Tier 0, 1, 2)
        if os.path.exists("tsconfig.json") or os.path.exists(os.path.join(target_dir, "tsconfig.json")):
            code, out = run_command(["npm", "run", "typecheck"])
            if code != 0 and check_tool_installed("npx"):
                code, out = run_command(["npx", "--no-install", "tsc", "--noEmit"])
            results.append(("Node: TypeScript (Type Check)", code == 0, "TS type checking passed ✓" if code == 0 else truncate_log(out)))

        if tier > 0:
            # Node Unit Tests (Tier 1 & Tier 2)
            code, out = run_command(["npm", "test"])
            results.append(("Node: Vitest / Unit Tests", code == 0, "Node unit tests passed ✓" if code == 0 else truncate_log(out)))

    return results if results else [("Node.js Check", True, "Node environment ready ✓")]


def run_go_checks(target_dir: str = ".", tier: int = 2) -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho dự án Go theo Tier."""
    results = []
    if not os.path.exists(os.path.join(target_dir, "go.mod")):
        return [("Go Check", True, "Skipped (no go.mod found)")]

    if check_tool_installed("go"):
        code, out = run_command(["go", "vet", "./..."])
        results.append(("Go: Vet", code == 0, "Go vet passed ✓" if code == 0 else truncate_log(out)))

        if tier > 0:
            code, out = run_command(["go", "test", "-v", "./..."])
            results.append(("Go: Tests", code == 0, "Go tests passed ✓" if code == 0 else truncate_log(out)))

    return results if results else [("Go Check", True, "Go checks passed ✓")]


def run_shell_checks(target_dir: str = ".", changed_files: list[str] | None = None) -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra cho Shell Scripting (ShellCheck) có hỗ trợ Diff-Aware."""
    results = []
    if changed_files is not None:
        sh_files = [f for f in changed_files if f.endswith(".sh") and "node_modules" not in f]
    else:
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


def run_anti_cheat_checks(
    target_dir: str = ".", changed_files: list[str] | None = None
) -> list[tuple[str, bool, str]]:
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

    if changed_files is not None:
        target_paths = [
            Path(f) for f in changed_files if Path(f).suffix in code_exts and Path(f).is_file()
        ]
        if not target_paths:
            return [
                (
                    "Quality: Anti-Cheat & Real Implementation Guard",
                    True,
                    "No modified code files to check in diff ✓",
                )
            ]
    else:
        target_paths = []
        for root, dirs, files in os.walk(base_path):
            dirs[:] = [d for d in dirs if d not in ignore_dirs and not d.startswith(".")]
            for file in files:
                p = Path(root) / file
                if p.suffix in code_exts:
                    target_paths.append(p)

    for p in target_paths:
        try:
            rel_file = p.relative_to(base_path) if p.is_absolute() else p
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
        help="Quick verification mode (alias for --tier 1: skips slow security scan)",
    )
    parser.add_argument(
        "--tier",
        type=int,
        choices=[0, 1, 2],
        default=None,
        help="Verification tier: 0 (Lint/Type only <2s), 1 (Unit tests & fast check <10s), 2 (Full regression & security 1-3m)",
    )
    parser.add_argument(
        "--test-target",
        type=str,
        default="",
        help="Specific test file or directory to run for pytest (e.g. tests/test_auth.py)",
    )
    parser.add_argument(
        "--diff",
        nargs="?",
        const="auto",
        default=None,
        help="Diff-aware verification: only verify files modified relative to BASE_REF (e.g. master, main, HEAD, or auto-detect)",
    )
    parser.add_argument(
        "--preset",
        type=str,
        default="auto",
        help="Preset to run: python_backend | node_react | go_backend | generic_scripting | polyglot_multi | auto",
    )
    args = parser.parse_args()

    # Determine effective test target (CLI flag first, fallback to RALPH_TEST_TARGET env)
    effective_test_target = args.test_target.strip() if args.test_target else os.environ.get("RALPH_TEST_TARGET", "").strip()
    if effective_test_target and effective_test_target.lower() in ["-", "none", "static_check"]:
        effective_test_target = ""

    # Determine diff-aware changed files if requested
    diff_base = args.diff or os.environ.get("RALPH_DIFF_BASE")
    changed_files: list[str] | None = None
    if diff_base is not None:
        changed_files = get_changed_files(diff_base)

    # Determine effective tier (backward compatible with --quick)
    if args.tier is not None:
        effective_tier = args.tier
    elif args.quick:
        effective_tier = 1
    else:
        effective_tier = 2

    preset = get_active_preset(args.preset)

    check_results: list[tuple[str, bool, str]] = []

    if preset == "node_react":
        check_results.extend(run_node_checks(".", tier=effective_tier))
    elif preset == "go_backend":
        check_results.extend(run_go_checks(".", tier=effective_tier))
    elif preset == "generic_scripting":
        check_results.extend(run_shell_checks(".", changed_files=changed_files))
    elif preset in ["polyglot_multi", "auto"]:
        # Auto-detect all present language environments & run combined checks
        check_results.extend(run_python_checks(".", quick=(effective_tier == 1), test_target=effective_test_target, tier=effective_tier, changed_files=changed_files))
        if os.path.exists("package.json"):
            check_results.extend(run_node_checks(".", tier=effective_tier))
        if os.path.exists("go.mod"):
            check_results.extend(run_go_checks(".", tier=effective_tier))
    else:  # Default: python_backend
        check_results.extend(run_python_checks(".", quick=(effective_tier == 1), test_target=effective_test_target, tier=effective_tier, changed_files=changed_files))

    # Universal check: Quality & Anti-Cheat Guard across all presets (chạy từ Tier 1 trở lên)
    if effective_tier > 0:
        check_results.extend(run_anti_cheat_checks(".", changed_files=changed_files))

    all_passed = all(r[1] for r in check_results)
    now = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d %H:%M")

    # ── Summary mode: 1-line output for reviewer model prompt injection ──────
    if args.summary:
        failed = [name for name, passed, _ in check_results if not passed]
        if all_passed:
            print(f"TIER{effective_tier}: PASS ({now}) [{preset}] — Deterministic checks green ✅")
        else:
            fail_str = ", ".join(failed)
            print(f"TIER{effective_tier}: FAIL ({now}) [{preset}] — Failed checks: {fail_str} ❌")
        sys.exit(0 if all_passed else 1)

    # ── Full mode: write VERIFICATION_REPORT.md ──────────────────────────────
    docs_runtime = Path("pipeline/docs/runtime")
    if not docs_runtime.parent.exists():
        docs_runtime = Path("pipeline/docs/runtime")
    report_path = docs_runtime / "VERIFICATION_REPORT.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    report_lines = [
        f"# TIER {effective_tier} VERIFICATION REPORT",
        f"Generated: {now}",
        f"Active Preset: {preset}",
        f"Verification Tier: Tier {effective_tier}",
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

    if not all_passed:
        failed_names = [name for name, passed, _ in check_results if not passed]
        print(f"[VERIFY] Tier {effective_tier} FAIL [{preset}]: {', '.join(failed_names)}")
        print(f"  Report: {report_path}")
        sys.exit(1)
    else:
        print(f"[VERIFY] Tier {effective_tier} PASS [{preset}]")
        sys.exit(0)


if __name__ == "__main__":
    main()
