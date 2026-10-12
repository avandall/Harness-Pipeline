"""Regression tests for task_dispatcher dependency handling (found via the 20261003-140547 parallel run)."""

import importlib.util
import sys
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "task_dispatcher.py"
_spec = importlib.util.spec_from_file_location("task_dispatcher", _SCRIPT)
assert _spec and _spec.loader
td = importlib.util.module_from_spec(_spec)
sys.modules["task_dispatcher"] = td
_spec.loader.exec_module(td)

TASKS_MD = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-001` | A | `a/*` | - | P0 | `[x] DONE` | |
| `TASK-002` | B | `b/*` | - | P0 | `[ ] TODO` | |
| `TASK-003` | C | `c/*` | - | P0 | `[ ] TODO` | |
| `TASK-004` | D | `d/*` | - | P0 | `[!] BLOCKED` | |
| `TASK-005` | E | `e/*` | - | P0 | `[ ] TODO` | |
| `TASK-006` | F | `f/*` | - | P0 | `[ ] TODO` | |

### 📌 TASK-001: A
#### Dependencies: None
### 📌 TASK-002: B
#### Dependencies: TASK-001
### 📌 TASK-003: C
#### Dependencies: TASK-002
### 📌 TASK-004: D
#### Dependencies: TASK-001
### 📌 TASK-005: E
#### Dependencies: TASK-004
### 📌 TASK-006: F
#### Dependencies: TASK-001 đến TASK-004
"""


def _load(tmp_path):
    f = tmp_path / "Tasks_list.md"
    f.write_text(TASKS_MD, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))
    return tasks, deps, status


def test_parse_dependencies_and_range(tmp_path):
    _, deps, status = _load(tmp_path)
    assert deps["TASK-003"] == {"TASK-002"}
    assert deps["TASK-006"] == {"TASK-001", "TASK-002", "TASK-003", "TASK-004"}
    assert status["TASK-004"] == "BLOCKED" and status["TASK-001"] == "DONE"


def test_next_available_respects_dependencies(tmp_path):
    tasks, deps, status = _load(tmp_path)
    # TASK-003 depends on TASK-002 (TODO) -> must NOT be dispatched while 002 is not DONE.
    assert td.get_next_available_task(tasks, set(), tmp_path, deps, status) == "TASK-002"
    assert td.get_next_available_task(tasks, {"TASK-002"}, tmp_path, deps, status) == ""


def test_blocked_dependency_starves_dependents(tmp_path):
    tasks, deps, status = _load(tmp_path)
    assert td.unmet_dependencies("TASK-005", deps, status) == ["TASK-004"]
    lines = td.explain(tasks, deps, status)
    assert any(line.startswith("TASK-005") and "BLOCKED" in line for line in lines)


def test_waves_never_put_dependent_with_its_dependency(tmp_path):
    tasks, deps, status = _load(tmp_path)
    waves = td.build_waves(tasks, tmp_path, 3, deps, status)
    flat = [[t.task_id for t in w] for w in waves]
    for w in flat:
        assert not ({"TASK-002", "TASK-003"} <= set(w))
    scheduled = {tid for w in flat for tid in w}
    assert "TASK-005" not in scheduled  # blocked by BLOCKED TASK-004


def test_backwards_compatible_without_graph(tmp_path):
    tasks, _, _ = _load(tmp_path)
    assert td.get_next_available_task(tasks, set(), tmp_path) == "TASK-002"
