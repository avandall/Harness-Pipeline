#!/usr/bin/env python3
"""
task_dispatcher.py — Phase-Aware 0-Token Wave & Dynamic Pool Scheduler for Ralph Loop (v2.1)
Phân tích phụ thuộc Task, tập file can thiệp (Target Files), Phase và đồ thị import AST.
Bảo đảm:
1. Tuân thủ tuyệt đối thứ tự Phase & Queue: Phase 1 (Foundation) -> Phase 2 (Services) -> Phase 3 (Delivery/UI) -> Phase 4 (E2E).
2. Hỗ trợ Dynamic Worker Pool: Cung cấp API (--next-available) để cấp phát task ngay khi có slot trống.
3. Chống xung đột file & AST Coupling: Chỉ gom các task hoàn toàn độc lập chạy song song.

Usage:
  # Lập lịch toàn bộ waves dạng JSON:
  python3 pipeline/scripts/task_dispatcher.py [TASKS_FILE] [--max-workers N]

  # Dynamic Worker Pool: Lấy task tiếp theo hợp lệ để cấp phát cho worker trống:
  python3 pipeline/scripts/task_dispatcher.py [TASKS_FILE] --next-available [--running "TASK-001,TASK-002"]
"""

import ast
import json
import re
import sys
from pathlib import Path


class TaskMeta:
    def __init__(
        self,
        task_id: str,
        scope: str,
        files: list[str],
        test_target: str,
        status: str,
        phase_num: int = 1,
        phase_name: str = "Phase 1",
        priority: str = "P1",
        order: int = 0,
    ):
        self.task_id = task_id
        self.scope = scope
        self.files = files
        self.test_target = test_target
        self.status = status
        self.phase_num = phase_num
        self.phase_name = phase_name
        self.priority = priority
        self.order = order

    def to_dict(self):
        return {
            "task_id": self.task_id,
            "scope": self.scope,
            "files": self.files,
            "test_target": self.test_target,
            "status": self.status,
            "phase": self.phase_name,
            "phase_num": self.phase_num,
            "priority": self.priority,
            "order": self.order,
        }


def extract_task_phases(content: str) -> dict[str, tuple[int, str]]:
    """Trích xuất mapping {task_id: (phase_num, phase_name)} từ Tasks_list.md."""
    phases = {}
    current_phase_num = 1
    current_phase_name = "Phase 1: Foundation"

    lines = content.splitlines()
    for line in lines:
        # Nhận diện header Phase trong document
        phase_header_match = re.search(r"^##+\s*(?:Phase|Giai đoạn)\s*(\d+)[:\s]*(.*)", line, re.IGNORECASE)
        if phase_header_match:
            try:
                current_phase_num = int(phase_header_match.group(1))
            except ValueError:
                current_phase_num = 1
            raw_title = phase_header_match.group(2).strip()
            current_phase_name = f"Phase {current_phase_num}: {raw_title}" if raw_title else f"Phase {current_phase_num}"

        # Nhận diện task heading
        task_match = re.search(r"###\s*📌\s*(TASK-[A-Za-z0-9_-]+)", line)
        if task_match:
            tid = task_match.group(1)
            phases[tid] = (current_phase_num, current_phase_name)

    # Quét khối metadata spec chi tiết (ví dụ: Phase: Phase 1: Foundation)
    spec_matches = re.finditer(
        r"Task ID:\s*(TASK-[A-Za-z0-9_-]+)[\s\S]*?Phase:\s*(?:Phase\s*)?(\d+)?[:\s-]*([^\n\r]*)",
        content,
    )
    for m in spec_matches:
        tid = m.group(1)
        pnum_str = m.group(2)
        pname_str = m.group(3).strip() if m.group(3) else ""
        pnum = int(pnum_str) if pnum_str and pnum_str.isdigit() else 1
        phases[tid] = (pnum, f"Phase {pnum}: {pname_str}" if pname_str else f"Phase {pnum}")

    return phases


def parse_tasks_file(file_path: str) -> list[TaskMeta]:
    """Đọc và parse danh sách task đang TODO hoặc IN_PROGRESS từ Tasks_list.md."""
    path = Path(file_path)
    if not path.is_file():
        return []

    content = path.read_text(encoding="utf-8", errors="ignore")
    phase_map = extract_task_phases(content)

    tasks = []
    seen_ids = set()
    order_idx = 0

    for line in content.splitlines():
        line_clean = line.strip()
        if not line_clean.startswith("|") or "TASK-" not in line_clean:
            continue

        if "---" in line_clean or "Task ID" in line_clean:
            continue

        # Chỉ quan tâm task [ ] TODO hoặc [/] IN_PROGRESS
        if not re.search(r"(`?\[[ /]\]\s*(TODO|IN_PROGRESS)`?)", line_clean):
            continue

        parts = [p.strip() for p in line_clean.split("|")[1:-1]]
        if len(parts) < 3:
            continue

        task_id_match = re.search(r"TASK-[A-Za-z0-9_-]+", parts[0])
        if not task_id_match:
            continue
        task_id = task_id_match.group(0)

        if task_id in seen_ids:
            sys.stderr.write(f"[DISPATCHER WARN] Duplicate task ID '{task_id}' detected. Skipping duplicate.\n")
            continue
        seen_ids.add(task_id)

        scope = parts[1] if len(parts) > 1 else ""
        files_raw = parts[2] if len(parts) > 2 else ""
        test_target = parts[3] if len(parts) > 3 else ""

        priority = "P1"
        if len(parts) > 4:
            p_val = parts[4].strip("` ")
            if p_val in ("P0", "P1", "P2", "P3"):
                priority = p_val

        status = "TODO"
        for p in parts[3:]:
            if "TODO" in p or "IN_PROGRESS" in p:
                status = p.strip("` ")
                break

        target_files = []
        for token in re.split(r"[,; \n]+", files_raw):
            token = token.strip("`'\" ")
            if token and token != "-":
                target_files.append(token)

        p_info = phase_map.get(task_id, (1, "Phase 1: Foundation"))
        phase_num, phase_name = p_info

        tasks.append(
            TaskMeta(
                task_id=task_id,
                scope=scope,
                files=target_files,
                test_target=test_target,
                status=status,
                phase_num=phase_num,
                phase_name=phase_name,
                priority=priority,
                order=order_idx,
            )
        )
        order_idx += 1

    return tasks


def module_to_file_path(module_name: str, repo_root: Path) -> Path | None:
    """Chuyển đổi module import (vd: services.auth) thành file path (.py)."""
    rel_path_py = Path(*module_name.split(".")).with_suffix(".py")
    search_dirs = [repo_root, repo_root / "src", repo_root / "app", repo_root / "pipeline"]

    for d in search_dirs:
        candidate = d / rel_path_py
        if candidate.is_file():
            return candidate
        candidate_init = d / Path(*module_name.split(".")) / "__init__.py"
        if candidate_init.is_file():
            return candidate_init

    return None


def extract_ast_imports_transitive(target_files: list[str], repo_root: Path, depth: int = 3) -> set[str]:
    """BFS traversal qua tối đa `depth` tầng import để bắt transitive coupling."""
    visited_files = set()
    frontier_files = set()

    for f_str in target_files:
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
            except (OSError, SyntaxError, UnicodeDecodeError):
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
    """
    Gom các task thành các Waves độc lập.
    ĐẢM BẢO:
    - Ưu tiên tuyệt đối theo Phase & Thứ tự tự nhiên (Natural Queue Order).
    - Không bao giờ nhảy cóc Phase (Phase 3 Delivery/UI không được xếp trước Phase 2 Services).
    """
    if not tasks:
        return []

    # Sắp xếp bảo toàn Phase và Natural Order từ Tasks_list.md
    tasks_sorted = sorted(tasks, key=lambda t: (t.phase_num, t.order))

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

        # Phase của task đầu tiên trong wave làm mốc — không gom task khác Phase vào cùng wave
        target_phase = remaining[0].phase_num

        for task in remaining:
            # Ngăn cách Phase: Nếu task thuộc Phase sau, bắt buộc sang Wave kế tiếp
            if task.phase_num != target_phase:
                unassigned.append(task)
                continue

            task_files, task_imports = task_cache[task.task_id]

            # 1. Kiểm tra File Disjoint
            has_file_conflict = bool(task_files & wave_files)

            # 2. Kiểm tra AST Coupling
            has_logic_coupling = bool(task_imports & wave_files) or bool(wave_transitive_imports & task_files)

            if not has_file_conflict and not has_logic_coupling and len(current_wave) < max_workers:
                current_wave.append(task)
                wave_files.update(task_files)
                wave_transitive_imports.update(task_imports)
            else:
                unassigned.append(task)

        if not current_wave and unassigned:
            current_wave.append(unassigned.pop(0))

        waves.append(current_wave)
        remaining = unassigned

    return waves


def get_next_available_task(
    tasks: list[TaskMeta],
    running_task_ids: set[str],
    repo_root: Path,
) -> str:
    """
    Dynamic Worker Pool Helper:
    Tìm task tiếp theo trong queue đủ điều kiện để cấp phát cho một worker slot vừa được giải phóng.
    Điều kiện:
    1. Task chưa được chạy (không nằm trong running_task_ids).
    2. Thuộc Phase sớm nhất đang hoạt động (không nhảy cóc Phase).
    3. Không xung đột file với bất kỳ task nào đang chạy.
    4. Không có AST coupling với bất kỳ task nào đang chạy.
    """
    if not tasks:
        return ""

    tasks_sorted = sorted(tasks, key=lambda t: (t.phase_num, t.order))

    # Tìm các task đang chạy để lấy tập files và imports
    running_files: set[str] = set()
    running_imports: set[str] = set()
    task_map = {t.task_id: t for t in tasks_sorted}

    for rid in running_task_ids:
        if rid in task_map:
            t = task_map[rid]
            t_files = normalize_file_set(t.files, repo_root)
            t_imports = extract_ast_imports_transitive(t.files, repo_root, depth=3)
            running_files.update(t_files)
            running_imports.update(t_imports)

    # Xác định Phase đang hoạt động (Phase nhỏ nhất trong tất cả các task chưa hoàn tất)
    active_phase = min(t.phase_num for t in tasks_sorted)
    pending_tasks = [t for t in tasks_sorted if t.task_id not in running_task_ids]
    if not pending_tasks:
        return ""

    for candidate in pending_tasks:
        # Không nhảy Phase nếu Phase hiện tại vẫn còn task chưa xong
        if candidate.phase_num > active_phase:
            break

        cand_files = normalize_file_set(candidate.files, repo_root)
        cand_imports = extract_ast_imports_transitive(candidate.files, repo_root, depth=3)

        # Kiểm tra xung đột với các worker đang chạy
        has_file_conflict = bool(cand_files & running_files)
        has_logic_coupling = bool(cand_imports & running_files) or bool(running_imports & cand_files)

        if not has_file_conflict and not has_logic_coupling:
            return candidate.task_id

    return ""


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Deterministic Phase-Aware Task Dispatcher for Ralph Loop (v2.1)",
        usage="%(prog)s [TASKS_FILE] [--max-workers N] [--next-available] [--running TIDS]",
    )
    parser.add_argument("arg1", nargs="?", default="", metavar="TASKS_FILE", help="Path to Tasks_list.md or max workers")
    parser.add_argument("arg2", nargs="?", default="", metavar="MAX_WORKERS", help="Optional second argument")
    parser.add_argument("--tasks-file", "-f", default="", help="Explicit path to Tasks_list.md")
    parser.add_argument("--max-workers", "-w", type=int, default=0, help="Max workers per wave (default: 3)")
    parser.add_argument("--next-available", "--next", action="store_true", help="Query next ready task for dynamic worker pool")
    parser.add_argument("--running", default="", help="Comma-separated list of currently running task IDs")

    args = parser.parse_args()

    tasks_file = args.tasks_file
    max_workers = args.max_workers

    for p in (args.arg1, args.arg2):
        if not p:
            continue
        if p.isdigit():
            if max_workers <= 0:
                max_workers = int(p)
        else:
            if not tasks_file:
                tasks_file = p

    if not tasks_file:
        tasks_file = "pipeline/docs/context/Tasks_list.md"
    if max_workers <= 0:
        max_workers = 3

    repo_root = Path.cwd()
    tasks = parse_tasks_file(tasks_file)

    if args.next_available:
        running_set = {tid.strip() for tid in args.running.split(",") if tid.strip()}
        next_tid = get_next_available_task(tasks, running_set, repo_root)
        print(next_tid)
        return

    waves = build_waves(tasks, repo_root, max_workers)

    output = []
    for w_idx, wave in enumerate(waves, start=1):
        output.append({
            "wave": w_idx,
            "worker_count": len(wave),
            "phase": wave[0].phase_name if wave else "Phase 1",
            "tasks": [t.to_dict() for t in wave],
        })

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
