"""Regression and mutation-hardened tests for task_dispatcher."""

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


def test_next_available_prevents_file_conflict(tmp_path):
    tasks_md = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-101` | A | `services/user.py` | - | P0 | `[ ] TODO` | |
| `TASK-102` | B | `services/user.py` | - | P0 | `[ ] TODO` | |
| `TASK-103` | C | `services/item.py` | - | P0 | `[ ] TODO` | |
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    # When TASK-101 is running, TASK-102 shares 'services/user.py' and must NOT be dispatched.
    # TASK-103 has a different file and should be returned.
    next_task = td.get_next_available_task(tasks, {"TASK-101"}, tmp_path, deps, status)
    assert next_task == "TASK-103"


def test_next_available_prevents_ast_coupling(tmp_path):
    services_dir = tmp_path / "services"
    services_dir.mkdir(parents=True)
    auth_file = services_dir / "auth.py"
    auth_file.write_text("def authenticate(): pass\n", encoding="utf-8")
    login_file = services_dir / "login.py"
    login_file.write_text("import services.auth\ndef login(): services.auth.authenticate()\n", encoding="utf-8")
    other_file = services_dir / "other.py"
    other_file.write_text("def ping(): pass\n", encoding="utf-8")

    tasks_md = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-201` | Auth | `services/auth.py` | - | P0 | `[ ] TODO` | |
| `TASK-202` | Login | `services/login.py` | - | P0 | `[ ] TODO` | |
| `TASK-203` | Other | `services/other.py` | - | P0 | `[ ] TODO` | |
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    # When TASK-201 (services/auth.py) is running, TASK-202 imports services.auth (AST coupling),
    # so TASK-202 cannot run in parallel. TASK-203 is independent and must be selected.
    next_task = td.get_next_available_task(tasks, {"TASK-201"}, tmp_path, deps, status)
    assert next_task == "TASK-203"


def test_next_available_respects_phase_boundaries(tmp_path):
    tasks_md = """\
## Phase 1: Foundation
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-301` | Core | `core.py` | - | P0 | `[ ] TODO` | |
| `TASK-302` | Util | `util.py` | - | P0 | `[ ] TODO` | |

## Phase 2: Features
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-303` | Feat | `feat.py` | - | P0 | `[ ] TODO` | |
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    # While Phase 1 has pending tasks (TASK-302), Phase 2 cannot be jumped to.
    assert td.get_next_available_task(tasks, {"TASK-301"}, tmp_path, deps, status) == "TASK-302"
    # When both TASK-301 and TASK-302 are running, Phase 1 is not complete yet, so TASK-303 cannot be dispatched.
    assert td.get_next_available_task(tasks, {"TASK-301", "TASK-302"}, tmp_path, deps, status) == ""


def test_is_permanently_blocked_and_phase_advancement(tmp_path):
    deps = {
        "TASK-401": set(),
        "TASK-402": {"TASK-401"},
        "TASK-403": {"TASK-402"},
        "TASK-404": set(),
    }
    status = {
        "TASK-401": "BLOCKED",
        "TASK-402": "TODO",
        "TASK-403": "TODO",
        "TASK-404": "TODO",
    }
    assert td.is_permanently_blocked("TASK-401", deps, status) is True
    assert td.is_permanently_blocked("TASK-402", deps, status) is True
    assert td.is_permanently_blocked("TASK-403", deps, status) is True
    assert td.is_permanently_blocked("TASK-404", deps, status) is False

    tasks_md = """\
## Phase 1: Foundation
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-401` | Core | `core.py` | - | P0 | `[!] BLOCKED` | |

## Phase 2: Services
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-404` | Svc | `svc.py` | - | P0 | `[ ] TODO` | |
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    # Phase 1 only contains permanently blocked task.
    # get_next_available_task must advance to Phase 2 to schedule TASK-404.
    assert td.get_next_available_task(tasks, set(), tmp_path, deps, status) == "TASK-404"


def test_build_waves_enforces_file_disjointness_and_ast_coupling(tmp_path):
    pkg_dir = tmp_path / "pkg"
    pkg_dir.mkdir(parents=True)
    (pkg_dir / "a.py").write_text("def a(): pass\n", encoding="utf-8")
    (pkg_dir / "b.py").write_text("import pkg.a\ndef b(): pass\n", encoding="utf-8")
    (pkg_dir / "c.py").write_text("def c(): pass\n", encoding="utf-8")

    # Non-Python files to test pure file disjointness without AST coupling
    data_dir = tmp_path / "data"
    data_dir.mkdir(parents=True)
    (data_dir / "schema.json").write_text("{}", encoding="utf-8")

    tasks_md = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-501` | Data1 | `data/schema.json` | - | P0 | `[ ] TODO` | |
| `TASK-502` | Data2 | `data/schema.json` | - | P0 | `[ ] TODO` | |
| `TASK-503` | CodeA | `pkg/a.py` | - | P0 | `[ ] TODO` | |
| `TASK-504` | CodeB | `pkg/b.py` | - | P0 | `[ ] TODO` | |
| `TASK-505` | CodeC | `pkg/c.py` | - | P0 | `[ ] TODO` | |
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    waves = td.build_waves(tasks, tmp_path, max_workers=5, deps=deps, status=status)
    flat = [[t.task_id for t in w] for w in waves]

    # TASK-501 and TASK-502 share data/schema.json (non-python, zero AST coupling).
    # File conflict alone MUST prevent them from ever sharing the same wave.
    for w in flat:
        assert not ({"TASK-501", "TASK-502"} <= set(w))

    # TASK-503 (pkg/a.py) and TASK-504 (pkg/b.py) have AST coupling (b imports a).
    # Logic coupling MUST prevent them from ever sharing the same wave.
    for w in flat:
        assert not ({"TASK-503", "TASK-504"} <= set(w))


def test_next_available_unmet_dependencies_gate(tmp_path):
    tasks_md = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-601` | A | `a.py` | - | P0 | `[ ] TODO` | |
| `TASK-602` | B | `b.py` | - | P0 | `[ ] TODO` | |

### 📌 TASK-601: A
#### Dependencies: TASK-602
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))

    # TASK-601 depends on TASK-602 (which is TODO, not DONE).
    # TASK-601 must not be dispatched ahead of TASK-602.
    next_task = td.get_next_available_task(tasks, set(), tmp_path, deps, status)
    assert next_task == "TASK-602"


def test_task_states_json_override(tmp_path):
    tasks_md = """\
| Task ID | Scope | Files | Test | Pri | Status | Note |
|---|---|---|---|---|---|---|
| `TASK-701` | A | `a.py` | - | P0 | `[ ] TODO` | |
| `TASK-702` | B | `b.py` | - | P0 | `[ ] TODO` | |
### 📌 TASK-702: B
#### Dependencies: TASK-701
"""
    f = tmp_path / "Tasks_list.md"
    f.write_text(tasks_md, encoding="utf-8")

    # In Tasks_list.md, TASK-701 is TODO.
    tasks = td.parse_tasks_file(str(f))
    deps, status = td.load_graph(str(f))
    assert status["TASK-701"] == "TODO"
    assert td.get_next_available_task(tasks, set(), tmp_path, deps, status) == "TASK-701"

    # Now create task_states.json overriding TASK-701 to DONE
    state_file = tmp_path / "task_states.json"
    state_file.write_text('{"TASK-701": {"status": "[x] DONE"}}', encoding="utf-8")

    status_overridden = td.parse_status_map(tasks_md, state_file)
    assert status_overridden["TASK-701"] == "DONE"
    # With TASK-701 marked DONE in state store, TASK-702 should now be dispatched!
    next_task = td.get_next_available_task(tasks, set(), tmp_path, deps, status_overridden)
    assert next_task == "TASK-702"
