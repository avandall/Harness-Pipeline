# 🚀 IMPLEMENT_ALL — One-Go Batch Execution Overlay

> **Mode:** One-Go (`--one-go`) Execution.
> You are tasked with executing the entire remaining queue in `pipeline/docs/context/Tasks_list.md` sequentially in this single execution invocation.

### Directives:
1.  **Task Identification & Prioritization:**
    *   Identify all tasks marked `[ ] TODO` or `[/] IN_PROGRESS` within `pipeline/docs/context/Tasks_list.md`.
    *   Process these tasks strictly in their order of appearance within the file, from top to bottom.
    *   **Anti-Cheat:** Do not reorder tasks based on perceived difficulty or any other heuristic.

2.  **Per-Task Execution Cycle:**
    For each identified task:
    a.  **Context & Planning:**
        *   Synchronize the current task details into `CURRENT_TASK.md`.
        *   Generate a detailed execution plan in `PLAN.md` based on `CURRENT_TASK.md` and `BOUNDARIES.md`.
    b.  **Implementation:**
        *   Implement all required code changes.
        *   **Strict Boundary Adherence:** All modifications MUST strictly adhere to the file paths and content constraints specified in `BOUNDARIES.md`. Do not modify any files not explicitly permitted or create new files outside the defined scope.
    c.  **Verification Loop:**
        *   Execute `python3 pipeline/scripts/verify.py`.
        *   **Deterministic Rigor:** A "failed attempt" is defined as `verify.py` returning a non-zero exit code or reporting anything less than "PASS 100%".
        *   Repeat execution until "PASS 100%" is achieved or 2 consecutive failed attempts occur.
        *   **Anti-Cheat:** You are strictly forbidden from modifying `pipeline/scripts/verify.py` or its output to bypass actual verification. Do not use trivial assertions (e.g., `assert True`) or mock results.
    d.  **Task Completion & Commit:**
        *   If "PASS 100%" is achieved:
            *   Mark the task `[x] DONE` in `pipeline/docs/context/Tasks_list.md`.
            *   Create a clean, professional git commit.
            *   **Commit Format:** `[TASK-ID] <type>(<scope>): <title>`
            *   **Commit Body:** MUST include a detailed body with sections: `Summary`, `Key Changes`, and `Verification Steps/Results`. Never commit generic one-liners.
    e.  **State Reset:**
        *   After completing a task (or blocking it), ensure the working directory is clean and any internal agent state related to the previous task is flushed/reset before proceeding to the next task.

3.  **Robust Failure Recovery:**
    If any individual task hits a blocker (2 consecutive failed verification attempts):
    a.  **Blocker Documentation:** Write a detailed `BLOCKERS/<TASK_ID>.md` explaining the issue, root cause analysis, and suggested next steps.
    b.  **Task Status Update:** Mark the task `[!] BLOCKED` in `pipeline/docs/context/Tasks_list.md`.
    c.  **Immediate Progression:** Immediately proceed to the next task in the queue. Do not attempt further retries on the blocked task within this execution.

4.  **Execution Termination:**
    *   Stop execution when all tasks in `pipeline/docs/context/Tasks_list.md` are either `[x] DONE` or `[!] BLOCKED`.

### Operational Constraints & Guardrails:
*   **Resource Protection:** You are strictly prohibited from spawning background processes, making unauthorized network calls, or interacting with any system resources outside the explicit scope of file modifications defined by `BOUNDARIES.md` and script executions (`verify.py`).
*   **Memory & State:** All persistent state changes MUST be reflected on disk (e.g., `Tasks_list.md`, `BLOCKERS/<TASK_ID>.md`, git commits). Do not rely on ephemeral in-memory state across task executions.
