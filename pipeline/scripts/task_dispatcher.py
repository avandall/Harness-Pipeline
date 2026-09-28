#!/usr/bin/env python3
"""
task_dispatcher.py — 0-Token Wave & Concurrency Scheduler for Ralph Loop (v2.0)
Phân tích phụ thuộc Task, tập file can thiệp (Target Files) và đồ thị import AST
để gom các task thành các Waves chạy song song an toàn, không xung đột file/logic.

Usage:
  python3 pipeline/scripts/task_dispatcher.py [MAX_WORKERS]
  python3 pipeline/scripts/task_dispatcher.py 3 --tasks-file pipeline/docs/context/Tasks_list.md
"""

import ast
import json
import os
import re
import sys
from pathlib import Path


class TaskMeta:
    def __init__(self, task_id: str, scope: str, files: list[str], test_target: str, status: str):
        self.task_id = task_id
        self.scope = scope
        self.files = files
        self.test_target = test_target
        self.status = status

    def to_dict(self):
        return {
            "task_id": self.task_id,
            "scope": self.scope,
            "files": self.files,
            "test_target": self.test_target,
            "status": self.status,
        }


def parse_tasks_file(file_path: str) -> list[TaskMeta]:
    """Đọc và parse danh sách task đang TODO từ Tasks_list.md."""
    path = Path(file_path)
    if not path.is_file():
        return []

    tasks = []
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()

    for line in lines:
        line_clean = line.strip()
        if not line_clean.startswith("|") or "TASK-" not in line_clean:
            continue

        # Bỏ qua dòng header hoặc separator
        if "---" in line_clean or "Task ID" in line_clean:
            continue

        # Chỉ quan tâm task [ ] TODO hoặc [/] IN_PROGRESS (kể cả có hoặc không có backticks)
        if not re.search(r"(`?\[[ /]\]\s*(TODO|IN_PROGRESS)`?)", line_clean):
            continue

        parts = [p.strip() for p in line_clean.split("|")[1:-1]]
        if len(parts) < 3:
            continue

        # Trích xuất task_id
        task_id_match = re.search(r"TASK-[A-Za-z0-9_-]+", parts[0])
        if not task_id_match:
            continue
        task_id = task_id_match.group(0)

        scope = parts[1] if len(parts) > 1 else ""
        files_raw = parts[2] if len(parts) > 2 else ""
        test_target = parts[3] if len(parts) > 3 else ""
        # Tìm cột chứa trạng thái
        status = "TODO"
        for p in parts[3:]:
            if "TODO" in p or "IN_PROGRESS" in p:
                status = p.strip("` ")
                break

        # Tách danh sách file/dirs
        target_files = []
        for token in re.split(r"[,; \n]+", files_raw):
            token = token.strip("`'\" ")
            if token and token != "-":
                target_files.append(token)

        tasks.append(TaskMeta(task_id, scope, target_files, test_target, status))

    return tasks


def module_to_file_path(module_name: str, repo_root: Path) -> Path | None:
    """Chuyển đổi module import (vd: services.auth) thành file path (.py)."""
    rel_path_py = Path(*module_name.split(".")) .with_suffix(".py")
    search_dirs = [repo_root, repo_root / "src", repo_root / "app", repo_root / "pipeline"]

    for d in search_dirs:
        candidate = d / rel_path_py
        if candidate.is_file():
            return candidate
        # Package init
        candidate_init = d / Path(*module_name.split(".")) / "__init__.py"
        if candidate_init.is_file():
            return candidate_init

    return None


def extract_ast_imports_transitive(target_files: list[str], repo_root: Path, depth: int = 3) -> set[str]:
    """BFS traversal qua tối đa `depth` tầng import để bắt transitive coupling."""
    visited_files = set()
    frontier_files = set()

    for f_str in target_files:
        # Nếu là wildcard/thư mục, quét các file .py bên trong
        f_path = repo_root / f_str.rstrip("*").rstrip("/")
        if f_path.is_file() and f_path.suffix == ".py":
            frontier_files.add(f_path.resolve())
        elif f_path.is_dir():
            for py_file in f_path.rglob("*.py"):
                frontier_files.add(py_file.resolve())

    for _ in range(depth):
        next_frontier = set()
        for f_path in frontier_files:
            if f_path in visited_files or not f_path.is_file():
                continue
            visited_files.add(f_path)

            try:
                content = f_path.read_text(encoding="utf-8", errors="ignore")
                tree = ast.parse(content)
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for a in node.names:
                            resolved = module_to_file_path(a.name, repo_root)
                            if resolved:
                                next_frontier.add(resolved.resolve())
                    elif isinstance(node, ast.ImportFrom):
                        if node.level and node.level > 0:
                            # Handle relative import (e.g. from . import x, from ..pkg import y)
                            target_dir = f_path.parent
                            for _ in range(node.level - 1):
                                target_dir = target_dir.parent
                            if node.module:
                                rel_path = target_dir / (node.module.replace(".", "/") + ".py")
                                if rel_path.is_file():
                                    next_frontier.add(rel_path.resolve())
                            else:
                                for n in node.names:
                                    rel_path = target_dir / f"{n.name}.py"
                                    if rel_path.is_file():
                                        next_frontier.add(rel_path.resolve())
                        elif node.module:
                            resolved = module_to_file_path(node.module, repo_root)
                            if resolved:
                                next_frontier.add(resolved.resolve())
            except Exception:
                continue

        frontier_files = next_frontier

    return {str(p.relative_to(repo_root)) if p.is_relative_to(repo_root) else str(p) for p in visited_files}


def normalize_file_set(files: list[str], repo_root: Path) -> set[str]:
    """Mở rộng danh sách target files/directories thành tập file cụ thể."""
    norm_set = set()
    for f_str in files:
        f_clean = f_str.strip("`'\" ")
        if not f_clean or f_clean == "-":
            continue
        p = repo_root / f_clean.rstrip("*").rstrip("/")
        if p.is_file():
            norm_set.add(str(p.relative_to(repo_root)))
        elif p.is_dir():
            for child in p.rglob("*"):
                if child.is_file():
                    norm_set.add(str(child.relative_to(repo_root)))
        else:
            norm_set.add(f_clean)
    return norm_set


def build_waves(tasks: list[TaskMeta], repo_root: Path, max_workers: int = 3) -> list[list[TaskMeta]]:
    """Gom các task thành các Waves độc lập theo Pack First-Fit Decreasing (FFD) và AST graph."""
    if not tasks:
        return []

    # Pack First-Fit Decreasing (FFD): Task nhiều file phức tạp xếp lên trước chống starvation
    tasks_sorted = sorted(tasks, key=lambda t: len(t.files), reverse=True)

    # Cache normalized files & transitive AST imports to avoid O(N^2) duplicate AST walks
    task_cache: dict[str, tuple[set[str], set[str]]] = {}
    for task in tasks_sorted:
        t_files = normalize_file_set(task.files, repo_root)
        t_imports = extract_ast_imports_transitive(task.files, repo_root, depth=3)
        task_cache[task.task_id] = (t_files, t_imports)

    waves: list[list[TaskMeta]] = []
    remaining = list(tasks_sorted)

    while remaining:
        current_wave: list[TaskMeta] = []
        wave_files: set[str] = set()
        wave_transitive_imports: set[str] = set()
        unassigned: list[TaskMeta] = []

        for task in remaining:
            task_files, task_imports = task_cache[task.task_id]

            # 1. Kiểm tra File Disjoint
            has_file_conflict = bool(task_files & wave_files)

            # 2. Kiểm tra AST Transitive Logic Coupling
            has_logic_coupling = bool(task_imports & wave_files) or bool(wave_transitive_imports & task_files)

            if not has_file_conflict and not has_logic_coupling and len(current_wave) < max_workers:
                current_wave.append(task)
                wave_files.update(task_files)
                wave_transitive_imports.update(task_imports)
            else:
                unassigned.append(task)

        # Nếu current_wave rỗng (ví dụ do task đụng chính nó hoặc không xếp được), đẩy 1 task vào wave đơn
        if not current_wave and unassigned:
            current_wave.append(unassigned.pop(0))

        waves.append(current_wave)
        remaining = unassigned

    if len(waves) == len(tasks) and len(tasks) > 1:
        sys.stderr.write(f"[DISPATCHER NOTICE] All {len(tasks)} tasks have overlapping files or import dependencies; scheduled sequentially in {len(waves)} waves of 1 task each.\n")

    return waves


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Deterministic 0-Token Task Dispatcher")
    parser.add_argument("tasks_file_pos", nargs="?", default="", help="Path to Tasks_list.md (positional)")
    parser.add_argument("--tasks-file", default="", help="Path to Tasks_list.md (optional flag)")
    parser.add_argument("--max-workers", "-w", type=int, default=3, help="Max workers per wave")

    args = parser.parse_args()

    tasks_file = args.tasks_file or args.tasks_file_pos or "pipeline/docs/context/Tasks_list.md"
    max_workers = max(1, args.max_workers)

    repo_root = Path.cwd()
    tasks = parse_tasks_file(tasks_file)
    waves = build_waves(tasks, repo_root, max_workers)

    # Chuyển đổi thành cấu trúc JSON cho Bash đọc
    output = []
    for w_idx, wave in enumerate(waves, start=1):
        output.append({
            "wave": w_idx,
            "worker_count": len(wave),
            "tasks": [t.to_dict() for t in wave],
        })

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
