#!/usr/bin/env python3
"""
dashboard.py — Real-Time Visual Telemetry & Multi-Worker Web Dashboard for Ralph Loop.
Runs a lightweight, zero-dependency server on localhost:8888.
Visualizes active workers, live tasks, current actions, logs, and progress.
"""

import argparse
import datetime
import html
import json
import os
import re
import socketserver
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def find_pipeline_dir() -> Path:
    """Finds the absolute path to the pipeline directory."""
    script_path = Path(__file__).resolve()
    return script_path.parent.parent


PIPELINE_DIR = find_pipeline_dir()
REPO_ROOT = PIPELINE_DIR.parent
CONTEXT_DIR = PIPELINE_DIR / "docs" / "context"
RUNTIME_DIR = PIPELINE_DIR / "docs" / "runtime"
RALPH_DIR = PIPELINE_DIR / ".ralph"
TELEMETRY_FILE = RALPH_DIR / "worker_telemetry.json"
STATES_FILE = RALPH_DIR / "task_states.json"
TASKS_FILE = CONTEXT_DIR / "Tasks_list.md"


def get_worker_colors(index: int) -> dict:
    """Returns a unique color scheme for each worker index."""
    colors = [
        {"name": "Emerald", "primary": "#10b981", "bg": "rgba(16, 185, 129, 0.12)", "border": "#059669", "glow": "rgba(16, 185, 129, 0.3)"},
        {"name": "Cyan", "primary": "#06b6d4", "bg": "rgba(6, 182, 212, 0.12)", "border": "#0891b2", "glow": "rgba(6, 182, 212, 0.3)"},
        {"name": "Purple", "primary": "#a855f7", "bg": "rgba(168, 85, 247, 0.12)", "border": "#9333ea", "glow": "rgba(168, 85, 247, 0.3)"},
        {"name": "Amber", "primary": "#f59e0b", "bg": "rgba(245, 158, 11, 0.12)", "border": "#d97706", "glow": "rgba(245, 158, 11, 0.3)"},
        {"name": "Rose", "primary": "#f43f5e", "bg": "rgba(244, 63, 94, 0.12)", "border": "#e11d48", "glow": "rgba(244, 63, 94, 0.3)"},
        {"name": "Indigo", "primary": "#6366f1", "bg": "rgba(99, 102, 241, 0.12)", "border": "#4f46e5", "glow": "rgba(99, 102, 241, 0.3)"},
    ]
    return colors[index % len(colors)]


def load_json_safe(path: Path) -> dict:
    """Reads a JSON file safely with fallback to empty dict."""
    if not path.is_file():
        return {}
    try:
        content = path.read_text(encoding="utf-8", errors="ignore").strip()
        if not content:
            return {}
        return json.loads(content)
    except Exception:
        return {}


def parse_tasks_metadata() -> list[dict]:
    """Parses task definitions and phase groupings from Tasks_list.md."""
    if not TASKS_FILE.is_file():
        return []

    try:
        content = TASKS_FILE.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return []

    tasks = []
    current_phase = "Phase 1: Foundation"

    for line in content.splitlines():
        line_clean = line.strip()
        phase_m = re.search(r"^##+\s*(?:Phase|Giai đoạn)\s*(\d+)[:\s]*(.*)", line_clean, re.IGNORECASE)
        if phase_m:
            num = phase_m.group(1)
            title = phase_m.group(2).strip()
            current_phase = f"Phase {num}: {title}" if title else f"Phase {num}"
            continue

        if not line_clean.startswith("|") or "TASK-" not in line_clean or "---" in line_clean or "Task ID" in line_clean:
            continue

        parts = [p.strip() for p in line_clean.split("|")[1:-1]]
        if not parts:
            continue

        tid_match = re.search(r"TASK-[A-Za-z0-9_-]+", parts[0])
        if not tid_match:
            continue
        tid = tid_match.group(0)

        scope = parts[1] if len(parts) > 1 else ""
        files_raw = parts[2] if len(parts) > 2 else ""
        priority = "P1"
        status = "TODO"

        for p in parts[3:]:
            p_clean = p.strip("` ")
            if p_clean in ("P0", "P1", "P2", "P3"):
                priority = p_clean
            if "[x]" in p or "DONE" in p:
                status = "DONE"
            elif "[!]" in p or "BLOCKED" in p:
                status = "BLOCKED"
            elif "[/]" in p or "IN_PROGRESS" in p:
                status = "IN_PROGRESS"
            elif "[ ]" in p or "TODO" in p:
                status = "TODO"

        tasks.append({
            "task_id": tid,
            "scope": scope,
            "files": files_raw,
            "priority": priority,
            "status": status,
            "phase": current_phase,
        })

    return tasks


def collect_telemetry() -> dict:
    """Gathers comprehensive telemetry across workers, tasks, logs, and system metrics."""
    telemetry_raw = load_json_safe(TELEMETRY_FILE)
    states_json = load_json_safe(STATES_FILE)
    tasks_meta = parse_tasks_metadata()

    # Merge task states from state store
    for t in tasks_meta:
        tid = t["task_id"]
        if tid in states_json and isinstance(states_json[tid], dict):
            st = str(states_json[tid].get("status", "")).upper()
            if "DONE" in st:
                t["status"] = "DONE"
            elif "BLOCK" in st:
                t["status"] = "BLOCKED"
            elif "PROGRESS" in st:
                t["status"] = "IN_PROGRESS"
            elif "TODO" in st:
                t["status"] = "TODO"

    # Compute task summary metrics
    total_tasks = len(tasks_meta)
    done_count = sum(1 for t in tasks_meta if t["status"] == "DONE")
    in_prog_count = sum(1 for t in tasks_meta if t["status"] == "IN_PROGRESS")
    blocked_count = sum(1 for t in tasks_meta if t["status"] == "BLOCKED")
    todo_count = sum(1 for t in tasks_meta if t["status"] == "TODO")
    completion_pct = round((done_count / total_tasks * 100), 1) if total_tasks > 0 else 0

    # Format workers
    workers_list = []
    worker_items = telemetry_raw.get("workers", {})
    if isinstance(worker_items, dict):
        idx = 0
        for wid, wdata in worker_items.items():
            color = get_worker_colors(idx)
            start_ts = wdata.get("start_time", time.time())
            now_ts = time.time()
            elapsed_s = max(0, int(now_ts - start_ts))

            # Fetch recent log snippet from worker worktree or log file
            log_snippet = wdata.get("recent_log", "")
            log_file = wdata.get("log_file", "")
            if not log_snippet and log_file and os.path.isfile(log_file):
                try:
                    with open(log_file, "r", encoding="utf-8", errors="ignore") as lf:
                        lines = lf.readlines()
                        log_snippet = "".join(lines[-15:])
                except Exception:
                    pass

            workers_list.append({
                "worker_id": wid,
                "task_id": wdata.get("task_id", ""),
                "task_title": wdata.get("task_title", wdata.get("task_id", "")),
                "status": wdata.get("status", "RUNNING"),
                "action": wdata.get("action", "Executing tasks..."),
                "elapsed_s": elapsed_s,
                "elapsed_human": f"{elapsed_s // 60:02d}:{elapsed_s % 60:02d}",
                "worktree": wdata.get("worktree", ""),
                "branch": wdata.get("branch", ""),
                "color": color,
                "log_snippet": log_snippet,
                "updated_at": wdata.get("updated_at", ""),
            })
            idx += 1

    # Recent milestones / events
    events = telemetry_raw.get("events", [])
    if not isinstance(events, list):
        events = []
    # Reverse to show newest first
    events_reversed = list(reversed(events[-30:]))

    return {
        "timestamp": datetime.datetime.now().strftime("%H:%M:%S"),
        "stats": {
            "total_tasks": total_tasks,
            "done_tasks": done_count,
            "in_progress": in_prog_count,
            "blocked_tasks": blocked_count,
            "todo_tasks": todo_count,
            "completion_pct": completion_pct,
            "active_workers": len([w for w in workers_list if w["status"] not in ("DONE", "BLOCKED")]),
        },
        "workers": workers_list,
        "tasks": tasks_meta,
        "events": events_reversed,
    }


DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Ralph Loop • Real-Time Autonomous Dashboard</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #0b0f17;
      --card-bg: #111827;
      --card-border: #1f2937;
      --text-main: #f3f4f6;
      --text-muted: #9ca3af;
      --accent: #3b82f6;
      --success: #10b981;
      --warning: #f59e0b;
      --danger: #ef4444;
      --font-sans: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif;
      --font-mono: 'JetBrains Mono', monospace;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text-main);
      font-family: var(--font-sans);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    /* Top Bar */
    header {
      background: rgba(17, 24, 39, 0.85);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--card-border);
      position: sticky;
      top: 0;
      z-index: 100;
      padding: 16px 28px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 14px;
    }
    .brand-icon {
      width: 36px;
      height: 36px;
      border-radius: 10px;
      background: linear-gradient(135deg, #2563eb, #7c3aed);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 16px rgba(59, 130, 246, 0.4);
    }
    .brand h1 {
      font-size: 1.15rem;
      font-weight: 800;
      letter-spacing: -0.02em;
      background: linear-gradient(90deg, #60a5fa, #c084fc);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .brand-tag {
      font-size: 0.75rem;
      color: var(--text-muted);
      font-family: var(--font-mono);
      padding: 2px 8px;
      border-radius: 6px;
      background: #1f2937;
    }

    .live-indicator {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.8rem;
      font-weight: 600;
      color: var(--success);
      background: rgba(16, 185, 129, 0.1);
      border: 1px solid rgba(16, 185, 129, 0.25);
      padding: 6px 14px;
      border-radius: 999px;
    }
    .pulse-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--success);
      box-shadow: 0 0 10px var(--success);
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0% { transform: scale(0.95); opacity: 0.8; }
      50% { transform: scale(1.3); opacity: 1; }
      100% { transform: scale(0.95); opacity: 0.8; }
    }

    /* Container */
    main {
      padding: 24px 28px;
      max-width: 1600px;
      width: 100%;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 24px;
      flex: 1;
    }

    /* Metrics Bar */
    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 16px;
    }
    .metric-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 16px 20px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      position: relative;
      overflow: hidden;
    }
    .metric-label {
      font-size: 0.8rem;
      font-weight: 600;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .metric-val {
      font-size: 1.85rem;
      font-weight: 800;
      font-family: var(--font-mono);
      letter-spacing: -0.02em;
    }

    /* Progress Track */
    .progress-wrapper {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 18px 22px;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .progress-info {
      display: flex;
      justify-content: space-between;
      font-size: 0.85rem;
      font-weight: 600;
    }
    .progress-bar-bg {
      height: 10px;
      background: #1f2937;
      border-radius: 999px;
      overflow: hidden;
      position: relative;
    }
    .progress-bar-fill {
      height: 100%;
      background: linear-gradient(90deg, #3b82f6, #10b981);
      border-radius: 999px;
      transition: width 0.4s ease;
      box-shadow: 0 0 12px rgba(16, 185, 129, 0.5);
    }

    /* Section Headings */
    .section-title {
      font-size: 1.05rem;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 4px;
    }

    /* Workers Arena */
    .workers-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
      gap: 18px;
    }
    .worker-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 20px;
      display: flex;
      flex-direction: column;
      gap: 14px;
      position: relative;
      transition: all 0.25s ease;
    }
    .worker-card:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }
    .worker-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .worker-badge {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .worker-avatar {
      width: 32px;
      height: 32px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 800;
      font-size: 0.85rem;
      font-family: var(--font-mono);
    }
    .worker-name {
      font-size: 0.95rem;
      font-weight: 700;
    }
    .worker-timer {
      font-family: var(--font-mono);
      font-size: 0.8rem;
      color: var(--text-muted);
      background: #1f2937;
      padding: 4px 10px;
      border-radius: 8px;
    }

    .task-focus {
      background: #0f172a;
      border: 1px solid #1e293b;
      border-radius: 10px;
      padding: 12px 14px;
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .task-id-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .task-pill {
      font-family: var(--font-mono);
      font-size: 0.8rem;
      font-weight: 700;
      padding: 2px 8px;
      border-radius: 6px;
      background: rgba(59, 130, 246, 0.2);
      color: #60a5fa;
      border: 1px solid rgba(59, 130, 246, 0.4);
    }
    .status-badge {
      font-size: 0.75rem;
      font-weight: 700;
      text-transform: uppercase;
      padding: 3px 10px;
      border-radius: 999px;
      letter-spacing: 0.04em;
    }
    .status-badge.RUNNING, .status-badge.EXECUTING { background: rgba(59, 130, 246, 0.2); color: #60a5fa; border: 1px solid #2563eb; }
    .status-badge.TIER_1, .status-badge.TIER_2 { background: rgba(168, 85, 247, 0.2); color: #c084fc; border: 1px solid #9333ea; }
    .status-badge.REPAIRING { background: rgba(245, 158, 11, 0.2); color: #fbbf24; border: 1px solid #d97706; }
    .status-badge.MERGING { background: rgba(6, 182, 212, 0.2); color: #22d3ee; border: 1px solid #0891b2; }
    .status-badge.DONE { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid #059669; }
    .status-badge.BLOCKED { background: rgba(239, 68, 68, 0.2); color: #f87171; border: 1px solid #dc2626; }

    .action-row {
      font-size: 0.85rem;
      color: #e2e8f0;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .action-icon {
      font-size: 1rem;
    }

    .terminal-drawer {
      background: #030712;
      border: 1px solid #1f2937;
      border-radius: 8px;
      padding: 10px 12px;
      font-family: var(--font-mono);
      font-size: 0.72rem;
      color: #94a3b8;
      max-height: 120px;
      overflow-y: auto;
      white-space: pre-wrap;
      line-height: 1.45;
    }

    /* Tasks Queue & Log Split */
    .dashboard-split {
      display: grid;
      grid-template-columns: 2fr 1.2fr;
      gap: 20px;
    }
    @media (max-width: 1024px) {
      .dashboard-split { grid-template-columns: 1fr; }
    }

    .table-container {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      overflow: hidden;
    }
    .table-header {
      padding: 16px 20px;
      border-bottom: 1px solid var(--card-border);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.85rem;
    }
    th {
      text-align: left;
      padding: 12px 18px;
      color: var(--text-muted);
      font-weight: 600;
      background: #0f172a;
      border-bottom: 1px solid var(--card-border);
    }
    td {
      padding: 12px 18px;
      border-bottom: 1px solid #1e293b;
    }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: rgba(255, 255, 255, 0.02); }

    .events-panel {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      max-height: 540px;
    }
    .events-header {
      padding: 16px 20px;
      border-bottom: 1px solid var(--card-border);
      font-weight: 700;
    }
    .events-list {
      padding: 12px 16px;
      overflow-y: auto;
      display: flex;
      flex-direction: column;
      gap: 10px;
      flex: 1;
    }
    .event-item {
      padding: 8px 12px;
      border-radius: 8px;
      background: #0f172a;
      border-left: 3px solid var(--accent);
      font-size: 0.8rem;
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .event-time {
      font-family: var(--font-mono);
      font-size: 0.7rem;
      color: var(--text-muted);
    }
    .event-text {
      color: #e2e8f0;
    }

    .empty-state {
      padding: 36px;
      text-align: center;
      color: var(--text-muted);
      font-size: 0.9rem;
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <div class="brand-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
      </div>
      <div>
        <h1>Ralph Loop Orchestrator</h1>
      </div>
      <span class="brand-tag">v3.1 Real-Time</span>
    </div>
    <div class="live-indicator">
      <div class="pulse-dot"></div>
      <span id="liveStatusText">LIVE ON 8888</span>
    </div>
  </header>

  <main>
    <!-- Key Metrics Cards -->
    <div class="metrics-grid">
      <div class="metric-card">
        <span class="metric-label">Active Workers</span>
        <span class="metric-val" id="metricWorkers" style="color: #60a5fa;">0</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">Completed Tasks</span>
        <span class="metric-val" id="metricDone" style="color: #34d399;">0</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">In Progress</span>
        <span class="metric-val" id="metricInProgress" style="color: #38bdf8;">0</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">Quarantined / Blocked</span>
        <span class="metric-val" id="metricBlocked" style="color: #f87171;">0</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">Remaining In Queue</span>
        <span class="metric-val" id="metricTodo" style="color: #94a3b8;">0</span>
      </div>
    </div>

    <!-- Progress Track -->
    <div class="progress-wrapper">
      <div class="progress-info">
        <span>Overall Pipeline Completion</span>
        <span id="progressPctText">0%</span>
      </div>
      <div class="progress-bar-bg">
        <div class="progress-bar-fill" id="progressBarFill" style="width: 0%;"></div>
      </div>
    </div>

    <!-- Active Workers Section -->
    <div>
      <div class="section-title">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#60a5fa" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
        Parallel Worker Pool (Real-Time Subprocesses)
      </div>
      <div class="workers-grid" id="workersGrid">
        <div class="empty-state">No workers currently executing. Waiting for next wave...</div>
      </div>
    </div>

    <!-- Split Queue & Events -->
    <div class="dashboard-split">
      <!-- Task Pipeline Table -->
      <div class="table-container">
        <div class="table-header">
          <div class="section-title" style="margin-bottom:0;">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#a78bfa" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
            Task Queue &amp; Phase Milestones
          </div>
        </div>
        <table>
          <thead>
            <tr>
              <th>Task ID</th>
              <th>Phase</th>
              <th>Scope</th>
              <th>Files</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="tasksTableBody">
            <tr><td colspan="5" class="empty-state">Loading tasks from Tasks_list.md...</td></tr>
          </tbody>
        </table>
      </div>

      <!-- Live Event Feed -->
      <div class="events-panel">
        <div class="events-header">⚡ Live Milestone Feed</div>
        <div class="events-list" id="eventsList">
          <div class="empty-state">No milestone events yet.</div>
        </div>
      </div>
    </div>
  </main>

  <script>
    async function updateDashboard() {
      try {
        const res = await fetch('/api/telemetry?t=' + Date.now());
        if (!res.ok) return;
        const data = await res.json();

        // 1. Update Metrics
        document.getElementById('metricWorkers').innerText = data.stats.active_workers;
        document.getElementById('metricDone').innerText = data.stats.done_tasks;
        document.getElementById('metricInProgress').innerText = data.stats.in_progress;
        document.getElementById('metricBlocked').innerText = data.stats.blocked_tasks;
        document.getElementById('metricTodo').innerText = data.stats.todo_tasks;

        const pct = data.stats.completion_pct + '%';
        document.getElementById('progressPctText').innerText = pct + ' (' + data.stats.done_tasks + '/' + data.stats.total_tasks + ')';
        document.getElementById('progressBarFill').style.width = pct;

        // 2. Render Workers Arena
        const workersGrid = document.getElementById('workersGrid');
        if (!data.workers || data.workers.length === 0) {
          workersGrid.innerHTML = '<div class="empty-state">No workers actively executing. Waiting for next wave...</div>';
        } else {
          workersGrid.innerHTML = data.workers.map(w => {
            const clr = w.color || { primary: '#3b82f6', bg: 'rgba(59,130,246,0.1)', border: '#2563eb' };
            const logBox = w.log_snippet ?
              `<div class="terminal-drawer">${escapeHtml(w.log_snippet)}</div>` : '';

            return `
              <div class="worker-card" style="border-color: ${clr.border}; box-shadow: 0 4px 20px ${clr.glow || 'rgba(0,0,0,0.3)'};">
                <div class="worker-header">
                  <div class="worker-badge">
                    <div class="worker-avatar" style="background: ${clr.bg}; color: ${clr.primary}; border: 1px solid ${clr.border};">
                      W${escapeHtml(w.worker_id.replace(/[^0-9]/g, '').slice(-1) || '1')}
                    </div>
                    <div>
                      <div class="worker-name">${escapeHtml(w.worker_id)}</div>
                    </div>
                  </div>
                  <div class="worker-timer">⏱️ ${w.elapsed_human}</div>
                </div>

                <div class="task-focus">
                  <div class="task-id-row">
                    <span class="task-pill">${escapeHtml(w.task_id || 'IDLE')}</span>
                    <span class="status-badge ${w.status}">${w.status}</span>
                  </div>
                  <div class="action-row">
                    <span class="action-icon">⚡</span>
                    <span>${escapeHtml(w.action)}</span>
                  </div>
                </div>

                ${logBox}
              </div>
            `;
          }).join('');
        }

        // 3. Render Tasks Table
        const tasksBody = document.getElementById('tasksTableBody');
        if (data.tasks && data.tasks.length > 0) {
          tasksBody.innerHTML = data.tasks.map(t => `
            <tr>
              <td><span class="task-pill">${escapeHtml(t.task_id)}</span></td>
              <td style="color: var(--text-muted); font-size: 0.78rem;">${escapeHtml(t.phase)}</td>
              <td><strong>${escapeHtml(t.scope)}</strong></td>
              <td style="font-family: var(--font-mono); font-size: 0.75rem; color: #94a3b8;">${escapeHtml(t.files)}</td>
              <td><span class="status-badge ${t.status}">${t.status}</span></td>
            </tr>
          `).join('');
        }

        // 4. Render Event Stream
        const eventsList = document.getElementById('eventsList');
        if (data.events && data.events.length > 0) {
          eventsList.innerHTML = data.events.map(ev => `
            <div class="event-item">
              <span class="event-time">${escapeHtml(ev.time || '')}</span>
              <span class="event-text">${escapeHtml(ev.message || ev.text || '')}</span>
            </div>
          `).join('');
        }
      } catch (err) {
        console.warn('Dashboard fetch error:', err);
      }
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    // Auto-update every 1 second
    setInterval(updateDashboard, 1000);
    updateDashboard();
  </script>
</body>
</html>
"""


class DashboardRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            self.wfile.write(DASHBOARD_HTML.encode("utf-8"))
        elif self.path.startswith("/api/telemetry"):
            data = collect_telemetry()
            payload = json.dumps(data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Mute normal HTTP server access logs to keep terminal quiet
        pass


def run_server(port: int = 8888, host: str = "0.0.0.0"):
    address = (host, port)
    socketserver.TCPServer.allow_reuse_address = True
    with ThreadingHTTPServer(address, DashboardRequestHandler) as httpd:
        print(f"[UI] 🌐 Ralph Loop Live Dashboard active at http://localhost:{port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[UI] Dashboard server stopped.")


def main():
    parser = argparse.ArgumentParser(description="Real-Time Visual Telemetry & Multi-Worker Dashboard for Ralph Loop")
    parser.add_argument("--port", "-p", type=int, default=8888, help="Port to listen on (default: 8888)")
    parser.add_argument("--host", default="0.0.0.0", help="Host address to bind (default: 0.0.0.0)")
    args = parser.parse_args()

    run_server(port=args.port, host=args.host)


if __name__ == "__main__":
    main()

