# 🚀 IMPLEMENT_ALL — One-Go Batch Execution Overlay

> **Mode:** One-Go (`--one-go`) Execution.
> You are tasked with executing the entire remaining queue in `pipeline/docs/context/Tasks_list.md` sequentially in this single execution invocation.

### Directives:
1. Loop through all `[ ] TODO` and `[/] IN_PROGRESS` tasks in order of priority.
2. For each task:
   - Synchronize `CURRENT_TASK.md` and create `PLAN.md`.
   - Implement code changes within `BOUNDARIES.md`.
   - Run `python3 pipeline/scripts/verify.py` until PASS 100%.
   - Mark task `[x] DONE` in `Tasks_list.md`.
   - Create a clean git commit: `[TASK-ID] <type>(<scope>): <description>`.
3. If any individual task hits a blocker (2 failed attempts):
   - Write `BLOCKERS/<TASK_ID>.md`.
   - Mark `[!] BLOCKED` in `Tasks_list.md`.
   - Proceed immediately to the next task in queue.
4. Stop when all tasks in the active scope are `[x] DONE` or `[!] BLOCKED`.
