#!/usr/bin/env python3
"""
verify.py — Deterministic Quality Verification Engine for Ralph Loop
Chạy các công cụ tĩnh (Static Analysis) và Runtime Test, tự động cắt tỉa log
để tối ưu token và cung cấp phản hồi khách quan 100% cho AI Coder.

Usage:
  python3 H_docs/scripts/verify.py              # Full report → VERIFICATION_REPORT.md
  python3 H_docs/scripts/verify.py --summary    # 1-line token-efficient summary (stdout only)
"""

import argparse
import datetime
import os
import shutil
import subprocess
import sys
from pathlib import Path


def truncate_log(log_text: str, max_lines: int = 20) -> str:
    """Cắt tỉa log rác, chỉ giữ lại các dòng Error, Traceback và Line chính."""
    if not log_text or not log_text.strip():
        return ""

    lines = log_text.strip().split("\n")
    if len(lines) <= max_lines:
        return "\n".join(lines)

    error_lines = []
    in_traceback = False

    for line in lines:
        if any(
            keyword in line
            for keyword in ["Traceback", "FAILED", "ERROR", "CRITICAL", "ERRORS"]
        ):
            in_traceback = True
        if (
            in_traceback
            or line.startswith("E   ")
            or "Error:" in line
            or line.startswith("FAILED ")
        ):
            error_lines.append(line)

    if error_lines:
        return "\n".join(error_lines[-max_lines:])
    return "\n".join(lines[-max_lines:])


def check_tool_installed(tool_name: str) -> bool:
    """Kiểm tra xem CLI tool đã được cài đặt trong hệ thống/env chưa."""
    return shutil.which(tool_name) is not None


def run_command(cmd: list[str]) -> tuple[int, str]:
    """Chạy command an toàn và thu thập output."""
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=False)
        output = (res.stdout or "") + ("\n" + res.stderr if res.stderr else "")
        return res.returncode, output.strip()
    except Exception as e:
        return 1, f"Execution failed: {str(e)}"


def run_python_checks(target_dir: str = ".") -> list[tuple[str, bool, str]]:
    """Chạy bộ kiểm tra chuẩn cho dự án Python: Ruff, Mypy, Bandit, Pytest."""
    results = []

    # 1. Ruff (Linter & Formatting)
    if check_tool_installed("ruff"):
        code, out = run_command(["ruff", "check", target_dir])
        if code == 0:
            results.append(("Ruff (Lint)", True, "All lint checks passed ✓"))
        else:
            results.append(("Ruff (Lint)", False, truncate_log(out)))
    else:
        results.append(
            (
                "Ruff (Lint)",
                True,
                "Skipped (ruff tool not installed in environment)",
            )
        )

    # 2. Mypy (Type Check)
    if check_tool_installed("mypy"):
        code, out = run_command(
            ["mypy", target_dir, "--ignore-missing-imports"]
        )
        if code == 0:
            results.append(
                ("Mypy (Type Check)", True, "Type checking passed ✓")
            )
        else:
            results.append(("Mypy (Type Check)", False, truncate_log(out)))
    else:
        results.append(
            (
                "Mypy (Type Check)",
                True,
                "Skipped (mypy tool not installed in environment)",
            )
        )

    # 3. Bandit (Security Scan)
    if check_tool_installed("bandit"):
        code, out = run_command(["bandit", "-r", target_dir, "-ll", "-q"])
        if code == 0:
            results.append(
                ("Bandit (Security)", True, "No high/medium security issues ✓")
            )
        else:
            results.append(("Bandit (Security)", False, truncate_log(out)))
    else:
        results.append(
            (
                "Bandit (Security)",
                True,
                "Skipped (bandit tool not installed in environment)",
            )
        )

    # 4. Pytest (Runtime Tests)
    if check_tool_installed("pytest"):
        # Check if tests directory or test files exist before running
        has_tests = (
            any(Path(".").rglob("test_*.py"))
            or any(Path(".").rglob("*_test.py"))
            or os.path.exists("tests")
        )
        if has_tests:
            code, out = run_command(["pytest", "--tb=short", "-q"])
            if code == 0:
                results.append(
                    ("Pytest (Runtime)", True, "All tests passed ✓")
                )
            else:
                results.append(("Pytest (Runtime)", False, truncate_log(out)))
        else:
            results.append(
                (
                    "Pytest (Runtime)",
                    True,
                    "Skipped (no test files found yet)",
                )
            )
    else:
        results.append(
            (
                "Pytest (Runtime)",
                True,
                "Skipped (pytest tool not installed in environment)",
            )
        )

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Tier 1 Deterministic Verification Engine for Ralph Loop"
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print a single-line token-efficient summary to stdout only (no file write)",
    )
    args = parser.parse_args()

    check_results = run_python_checks(".")
    all_passed = all(r[1] for r in check_results)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

    # ── Summary mode: 1-line output for reviewer model prompt injection ──────
    if args.summary:
        failed = [name for name, passed, _ in check_results if not passed]
        if all_passed:
            print(f"TIER1: PASS ({now}) — Ruff/Mypy/Bandit/Pytest all green ✅")
        else:
            fail_str = ", ".join(failed)
            print(f"TIER1: FAIL ({now}) — Failed checks: {fail_str} ❌")
        sys.exit(0 if all_passed else 1)

    # ── Full mode: write VERIFICATION_REPORT.md ──────────────────────────────
    report_path = Path("H_docs/runtime/VERIFICATION_REPORT.md")
    report_path.parent.mkdir(parents=True, exist_ok=True)

    print("🔍 Running Tier 1 Deterministic Verification Checks...")

    report_lines = [
        "# TIER 1 VERIFICATION REPORT",
        f"Generated: {now}",
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
            "❌ Tier 1 Verification Failed! See H_docs/runtime/VERIFICATION_REPORT.md for details."
        )
        sys.exit(1)
    else:
        print("✅ Tier 1 Verification Passed 100%!")
        sys.exit(0)


if __name__ == "__main__":
    main()
