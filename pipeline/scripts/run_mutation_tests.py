#!/usr/bin/env python3
"""
run_mutation_tests.py — Automated Mutation Testing for Pipeline Scripts & Engine.
Applies semantic mutations to source files and checks if existing pytest test suites kill the mutants.
"""

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DISPATCHER_PATH = REPO_ROOT / "pipeline" / "scripts" / "task_dispatcher.py"
DISPATCHER_TEST = REPO_ROOT / "pipeline" / "tests" / "test_dispatcher.py"
ENGINE_TEST = REPO_ROOT / "pipeline" / "tests" / "test_engine.py"
PYTEST_BIN = REPO_ROOT / ".venv" / "bin" / "pytest"


def run_mutation_round(
    target_file: Path,
    test_file: Path,
    mutations: list[tuple[str, str, str]],
) -> tuple[int, int, list[tuple[str, str]]]:
    original_code = target_file.read_text(encoding="utf-8")
    results = []

    print(f"\n=======================================================")
    print(f"MUTATION TESTING TARGET: {target_file.name}")
    print(f"TEST SUITE: {test_file.name}")
    print(f"TOTAL MUTANTS: {len(mutations)}")
    print(f"=======================================================\n")

    for name, orig, mut in mutations:
        if orig not in original_code:
            print(f"[SKIP] Target pattern not found for: {name}")
            continue

        mutated_code = original_code.replace(orig, mut, 1)
        target_file.write_text(mutated_code, encoding="utf-8")

        proc = subprocess.run([str(PYTEST_BIN), str(test_file), "-q"], capture_output=True, text=True)

        if proc.returncode != 0:
            status = "KILLED"
            icon = "💥"
        else:
            status = "SURVIVED"
            icon = "⚠️ "

        results.append((name, status))
        print(f"{icon} [{status}] {name}")
        if status == "SURVIVED":
            print(f"   [SURVIVED STDOUT] {proc.stdout.strip()[:200]}")

    # Always restore original file
    target_file.write_text(original_code, encoding="utf-8")

    killed = sum(1 for _, s in results if s == "KILLED")
    total = len(results)
    return killed, total, results


def main():
    mutations_dispatcher = [
        (
            "MUT_01: Disable file conflict check in get_next_available_task",
            "has_file_conflict = bool(cand_files & running_files)",
            "has_file_conflict = False",
        ),
        (
            "MUT_02: Disable AST coupling check in get_next_available_task",
            "has_logic_coupling = bool(cand_imports & running_files) or bool(running_imports & cand_files)",
            "has_logic_coupling = False",
        ),
        (
            "MUT_03: Invert phase gate in get_next_available_task",
            "if candidate.phase_num > active_phase:",
            "if False and candidate.phase_num > active_phase:",
        ),
        (
            "MUT_04: Invert is_permanently_blocked status check",
            'if any(k in s for k in ("BLOCK", "QUARANTINE")):',
            'if False and any(k in s for k in ("BLOCK", "QUARANTINE")):',
        ),
        (
            "MUT_05: Invert is_permanently_blocked dependency check",
            'if any(k in ds for k in ("BLOCK", "QUARANTINE")):',
            'if False and any(k in ds for k in ("BLOCK", "QUARANTINE")):',
        ),
        (
            "MUT_06: Ignore unmet dependencies in get_next_available_task",
            "if unmet_dependencies(candidate.task_id, deps, status):",
            "if False and unmet_dependencies(candidate.task_id, deps, status):",
        ),
        (
            "MUT_07: Invert condition in unmet_dependencies (return DONE instead of non-DONE)",
            'if d in status and status[d] != "DONE"',
            'if d in status and status[d] == "DONE"',
        ),
        (
            "MUT_08: Break build_waves file disjoint check",
            "has_file_conflict = bool(task_files & wave_files)",
            "has_file_conflict = False",
        ),
        (
            "MUT_09: Break build_waves AST coupling check",
            "has_logic_coupling = bool(task_imports & wave_files) or bool(wave_transitive_imports & task_files)",
            "has_logic_coupling = False",
        ),
        (
            "MUT_10: Break dependency range parser in parse_dependencies",
            "lo_n, hi_n = int(lo), int(hi)",
            "lo_n, hi_n = int(lo), int(lo)",
        ),
        (
            "MUT_11: Return empty list from unmet_dependencies unconditionally",
            '"""Danh sách dependency chưa DONE.',
            '"""Danh sách dependency chưa DONE."""\n    return []\n    """',
        ),
    ]

    killed, total, results = run_mutation_round(DISPATCHER_PATH, DISPATCHER_TEST, mutations_dispatcher)

    score = (killed / total) * 100 if total else 0
    print(f"\n-------------------------------------------------------")
    print(f"FINAL MUTATION SCORE FOR task_dispatcher: {killed}/{total} ({score:.1f}%)")
    print(f"-------------------------------------------------------\n")

    if score < 80.0:
        print(f"❌ TEST SUITE INSUFFICIENT: Mutation score {score:.1f}% is below 80% threshold.")
        print(f"The following mutants survived and expose missing tests:")
        for name, status in results:
            if status == "SURVIVED":
                print(f"  - {name}")
        sys.exit(1)
    else:
        print(f"✅ TEST SUITE VALIDATED: Mutation score {score:.1f}% meets quality standards.")
        sys.exit(0)


if __name__ == "__main__":
    main()
