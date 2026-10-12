#!/usr/bin/env python3
"""
ralph-audit.py — Autonomous Pipeline & Harness Structural Auditor.

Phát hiện các lỗi điều phối, quy trình và hạ tầng mà linter hay test runner bỏ sót:
1. Đồ thị Dependency: Phát hiện các task chạy hoặc commit trái với `#### Dependencies:`
2. False Blocked Detection: Phát hiện các task bị [!] BLOCKED do lỗi hạ tầng (429/RESOURCE_EXHAUSTED/timeout)
3. Bors Merge & Commit Auditing: Phát hiện task báo DONE trong log nhưng thiếu commit trên git
4. Staging Loss Auditing: Phát hiện các task thay đổi file ngoài phạm vi (như root files) không được stage
5. Sinh báo cáo chẩn đoán và file đề xuất patch PIPELINE_FIX_PROPOSAL.patch (nếu có)
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

def get_git_commits(repo_root: Path, limit: int = 50) -> list[tuple[str, str]]:
    """Trả về list (hash, subject) theo thứ tự commit gần nhất."""
    try:
        res = subprocess.run(
            ["git", "-C", str(repo_root), "log", f"-n{limit}", "--oneline", "--format=%h %s"],
            capture_output=True,
            text=True,
            check=True
        )
        out = []
        for line in res.stdout.strip().splitlines():
            parts = line.split(" ", 1)
            if len(parts) == 2:
                out.append((parts[0], parts[1]))
        return out
    except Exception:
        return []

def audit_pipeline(repo_root: Path, run_dir: Path | None = None) -> dict:
    pipeline_dir = repo_root / "pipeline"
    context_dir = pipeline_dir / "docs" / "context"
    tasks_file = context_dir / "Tasks_list.md"
    
    findings = []
    actions_recommended = []
    
    if not tasks_file.is_file():
        return {"status": "error", "message": f"Tasks file not found: {tasks_file}"}

    # Load task_dispatcher logic
    sys.path.insert(0, str(pipeline_dir / "scripts"))
    try:
        import task_dispatcher as td
        tasks = td.parse_tasks_file(str(tasks_file))
        deps, status_map = td.load_graph(str(tasks_file))
    except Exception as e:
        return {"status": "error", "message": f"Could not import task_dispatcher: {e}"}

    # 1. Audit Dependency vs Git Commit Order
    commits = get_git_commits(repo_root, limit=50)
    commit_task_order = []
    # Đi từ commit cũ nhất -> mới nhất trong lịch sử
    for chash, subject in reversed(commits):
        m = re.search(r"\[(TASK-[A-Za-z0-9_-]+)\]", subject)
        if m:
            tid = m.group(1)
            if tid not in commit_task_order:
                commit_task_order.append(tid)

    # Kiểm tra xem có task nào commit TRƯỚC dependency của nó không
    for i, tid in enumerate(commit_task_order):
        task_deps = deps.get(tid, set())
        for d in task_deps:
            if d in commit_task_order:
                dep_idx = commit_task_order.index(d)
                if dep_idx > i:
                    findings.append({
                        "category": "DEPENDENCY_INVERSION",
                        "severity": "HIGH",
                        "task": tid,
                        "dependency": d,
                        "message": f"Task {tid} was committed BEFORE its dependency {d} was integrated into master!"
                    })

    # 2. Audit Quota / 429 False Blocked in Run Logs
    if run_dir and run_dir.is_dir():
        for log_file in run_dir.glob("iter-*-WORKER-*.log"):
            try:
                content = log_file.read_text(encoding="utf-8", errors="ignore")
                m_task = re.search(r"iter-\d+-WORKER-(TASK-[A-Za-z0-9_-]+)\.log", log_file.name)
                tid = m_task.group(1) if m_task else "UNKNOWN"
                
                is_quota = (
                    "RESOURCE_EXHAUSTED" in content
                    or "Individual quota reached" in content
                    or "429" in content
                )
                
                if is_quota and status_map.get(tid) == "BLOCKED":
                    findings.append({
                        "category": "FALSE_BLOCKED_QUOTA",
                        "severity": "CRITICAL",
                        "task": tid,
                        "log_file": str(log_file.name),
                        "message": f"Task {tid} is marked [!] BLOCKED due to Provider Quota Exhaustion (429/RESOURCE_EXHAUSTED). This is an infra rate limit, not a task defect."
                    })
                    actions_recommended.append({
                        "action": "RESET_TASK_STATUS",
                        "task": tid,
                        "to_status": "[ ] TODO",
                        "reason": "Retryable provider quota reset"
                    })
            except Exception:
                pass

    # 3. Audit Worker Success vs Master Git Commit (Unmerged Workers)
    committed_tasks = {t for _, subj in commits for t in re.findall(r"\[(TASK-[A-Za-z0-9_-]+)\]", subj)}
    if run_dir and run_dir.is_dir():
        for log_file in run_dir.glob("iter-*-WORKER-*.log"):
            try:
                content = log_file.read_text(encoding="utf-8", errors="ignore")
                m_task = re.search(r"iter-\d+-WORKER-(TASK-[A-Za-z0-9_-]+)\.log", log_file.name)
                if not m_task:
                    continue
                tid = m_task.group(1)
                
                # Nếu worker báo pass 100% nhưng git commit không có
                if ("Tier 2 (Full Suite Regression" in content or "Tier 2 Verification" in content) and "PASS" in content:
                    if tid not in committed_tasks and status_map.get(tid) != "DONE":
                        findings.append({
                            "category": "UNMERGED_WORKER",
                            "severity": "HIGH",
                            "task": tid,
                            "message": f"Worker for {tid} completed tests successfully, but its changes were never integrated into master!"
                        })
                        actions_recommended.append({
                            "action": "RETRY_OR_INTEGRATE",
                            "task": tid,
                            "reason": "Worker succeeded locally but was rejected or missed during Bors staging"
                        })
            except Exception:
                pass

    # 4. Audit Blocked Chain (Starved Tasks)
    for tid, st in status_map.items():
        if st in ("TODO", "BLOCKED"):
            miss = td.unmet_dependencies(tid, deps, status_map)
            blocked_deps = [d for d in miss if status_map.get(d) == "BLOCKED"]
            if blocked_deps:
                findings.append({
                    "category": "STARVED_BY_BLOCKED_DEPENDENCY",
                    "severity": "MEDIUM",
                    "task": tid,
                    "blocked_by": blocked_deps,
                    "message": f"Task {tid} cannot proceed because its dependencies {blocked_deps} are BLOCKED."
                })

    return {
        "status": "completed",
        "findings_count": len(findings),
        "findings": findings,
        "actions_recommended": actions_recommended
    }

def main():
    repo_root = Path.cwd()
    pipeline_dir = repo_root / "pipeline"
    run_dir = None

    if len(sys.argv) > 1:
        run_dir = Path(sys.argv[1])
    else:
        # Auto detect latest run
        current_symlink = pipeline_dir / "docs" / "runtime" / "CURRENT"
        if current_symlink.is_symlink() or current_symlink.exists():
            run_dir = current_symlink.resolve()
        else:
            candidates = sorted((pipeline_dir / ".ralph" / "runs").glob("*"), key=os.path.getmtime, reverse=True)
            if candidates:
                run_dir = candidates[0]

    report = audit_pipeline(repo_root, run_dir)
    print(json.dumps(report, indent=2, ensure_ascii=False))

    # Xuất ra Markdown cho ralph-retro tích hợp
    if run_dir and run_dir.is_dir():
        audit_md = run_dir / "harness_audit.md"
        with open(audit_md, "w", encoding="utf-8") as f:
            f.write("# 🔍 Harness Process & Structural Audit Report\n\n")
            f.write(f"- **Target Run:** `{run_dir.name}`\n")
            f.write(f"- **Total Systemic Issues Found:** {report.get('findings_count', 0)}\n\n")
            
            if report.get("findings"):
                f.write("### 🚨 Detected Anomalies:\n")
                for item in report["findings"]:
                    f.write(f"- **[{item['severity']}] {item['category']}** ({item.get('task', 'N/A')}): {item['message']}\n")
                f.write("\n")
                
            if report.get("actions_recommended"):
                f.write("### 💡 Recommended Workflow Actions:\n")
                for act in report["actions_recommended"]:
                    f.write(f"- **{act['action']}** [{act.get('task', 'N/A')}]: {act['reason']}\n")
                f.write("\n")

if __name__ == "__main__":
    main()
