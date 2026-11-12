# Technical Specification: Enterprise Overnight AI Harness & Parallel Engine (v3.0)

## 1. Executive Summary
The current Ralph Loop harness template is functional but exhibits three major bottlenecks that prevent robust unattended overnight autonomous code generation:
1. **Inconsistent Code Quality**: Occasional shallow implementations, missing edge-case handling, and lack of strict TDD contract enforcement.
2. **Slow Cycle Times**: High end-to-end iteration latency caused by redundant full-suite verification runs, unoptimized agent prompts, and suboptimal timeouts.
3. **Fragile Parallel Execution (`--parallel`)**: Frequent worker blocking due to rigid rebase conflict resolution, merge collisions in git worktrees, and conservative failure handling that immediately marks tasks as `[!] BLOCKED`.

This specification defines the architecture for **Harness Engine v3.0**, designed to run completely unattended overnight with 100% autonomous code generation, deterministic tiered verification, intelligent non-blocking parallel worktree dispatching, and self-healing merge queues.

---

## 2. Requirements

### 2.1 Functional Requirements
- **FR-1: Automated TDD Contract Enforcement (Red-Green-Refactor)**
  - For every task, the executor must first generate/verify a failing contract test (Tier 1 Red), write production code until the test passes (Tier 1 Green), and run linting/typing (Clean).
- **FR-2: Dynamic Non-Conflicting Parallel Wave Dispatcher**
  - Upgrade `task_dispatcher.py` to calculate file footprints and AST dependency graphs, guaranteeing that no two tasks touching the same files or dependent modules are scheduled concurrently.
  - Implement dynamic worker slot replenishment (`wait -n`) so the worker pool stays fully saturated without stalling the entire wave.
- **FR-3: Resilient Bors Virtual Merge Queue & Self-Healing Rebase**
  - Replace rigid rebase failure blocking with a 3-tier conflict resolver:
    1. Automatic resolution for standard boilerplate (`__init__.py`, exports, configs, dependencies).
    2. Intelligent 3-way line-level non-overlapping diff merge.
    3. AI-guided 1-shot conflict resolution before declaring a task blocked.
- **FR-4: Tiered Fast-Path Verification**
  - **Tier 0 (Pre-Flight, < 5s)**: Syntax and formatting check on modified files only (`ruff check --select E9,F` / AST compile).
  - **Tier 1 (Local Worktree Scope, < 30s)**: Targeted unit tests and type checks on diff against base branch.
  - **Tier 2 (Integration Gate, < 90s)**: Run full integration suite before merging into the main branch.
  - **Tier 3 (Final Regression Gate)**: Full workspace verification after all wave tasks integrate.
- **FR-5: Anti-Stall Watchdog & Dynamic Budgeting**
  - Prevent frozen worker processes by monitoring filesystem mtime deltas, output streams, and process trees.
  - Auto-extend budget only when positive progress (git diff delta, passing tests) is detected; terminate stuck processes cleanly.

### 2.2 Non-Functional Requirements
- **NFR-1: 100% Autonomy & Zero Human Intervention**: Capable of 8+ hours unattended overnight execution without interactive prompts.
- **NFR-2: High Code Reliability**: Zero regression policy; any integration failure is rolled back atomically without dirtying the working directory.
- **NFR-3: Speed & Resource Optimization**: 60-70% reduction in cycle wall-clock time compared to naive serial loops via intelligent caching, targeted pytest selectors, and parallel git worktrees.
- **NFR-4: Generic Template Portability**: Zero hardcoded application domain logic inside `pipeline/`; all configuration must remain stack-agnostic and template-driven.

---

## 3. Architecture & Tech Stack

```mermaid
flowchart TD
    subgraph Planning & Task Scheduling
        TL["Tasks_list.md"] --> TD["task_dispatcher.py\n(AST & File Footprint Isolation)"]
        TD --> WP["Worker Pool (1..N Workers)"]
    end

    subgraph Worker Lifecycle (Git Worktree Isolation)
        WP --> WT["Worktree Branch: worker-TASK-ID"]
        WT --> TDD["TDD Phase:\n1. Failing Test (Red)\n2. Implementation (Green)\n3. Tier 1 Verification (Diff)"]
        TDD --> MQ["Queue for Integration"]
    end

    subgraph Bors Virtual Merge Queue
        MQ --> MLock["Acquire Merge Lock (flock)"]
        MLock --> Rebase["Rebase on Base Branch\n(Auto + 3-Way + 1-Shot Healing)"]
        Rebase --> T2Gate["Tier 2 Verification Gate"]
        T2Gate -->|Pass| Squash["Atomic Squash Commit -> Main"]
        T2Gate -->|Fail| Rollback["Safe Worktree Reset & Retry/Quarantine"]
        Squash --> ReleaseLock["Release Lock & Cleanup Worktree"]
    end

    ReleaseLock --> Done["Task Marked [x] DONE"]
```

### 3.1 Components & Architecture Details

1. **Scheduling Engine (`task_dispatcher.py`)**:
   - Computes explicit `target_files` and transitive import graphs for pending tasks.
   - Bipartite graph coloring algorithm partitions independent tasks into disjoint parallel execution batches.
   - Supports continuous sliding-window slot allocation (`--next-available`).

2. **Parallel Worktree Harness (`pipeline/scripts/harness.sh`)**:
   - Spawns workers into isolated Git worktrees (`.ralph/worktrees/wt-<task>`).
   - Ensures each worktree maintains its own isolated runtime environment and local logs (`RUN_DIR`), preventing shared-file race conditions.
   - Clean trap-based signal handlers guarantee zero orphaned worktrees or dangling lock files upon exit or interrupt.

3. **Bors Integration Queue & Conflict Healer**:
   - Serialized merge queue via atomic file descriptor locking (`flock`).
   - Clean base-branch validation before staging.
   - Multi-tier rebase healing prevents premature task blocking on non-semantic conflicts.

4. **Deterministic Verification Engine (`pipeline/scripts/verify.py`)**:
   - Multi-tier verification pipeline with git diff scoping.
   - Fast-exit on earliest tier failure to avoid wasting compute.
   - Auto-detects polyglot environments (Python, Node/TS, Go, Shell).

---

## 4. State Management & Concurrency Controls

- **Disk-First Persistence**: All state changes (`PLAN.md`, `PROGRESS_LOG.md`, `DECISIONS_LOG.md`, `STATUS.md`) are persisted directly to disk.
- **Atomic Lock Protocol**:
  - `merge_queue.lock`: Exclusively locks merge staging during squash and Tier 2 gate verification.
  - `status_update.lock`: Protects `Tasks_list.md` and `STATUS.md` from concurrent write corruption.
- **Task Quarantine vs. Immediate Blocking**:
  - Tasks that fail after max retries are safely quarantined in `BLOCKERS/<task>.md` with a detailed diagnostic report, allowing independent tasks in the queue to continue processing unimpeded overnight.

---

## 5. Implementation Roadmap in `pipeline/`

1. **Phase 1**: Optimize `pipeline/scripts/harness.sh` parallel loop, process isolation, and dynamic worker pool management.
2. **Phase 2**: Enhance `pipeline/scripts/task_dispatcher.py` for conflict-free AST file dependency scheduling.
3. **Phase 3**: Refine Bors merge queue with intelligent multi-stage conflict healing.
4. **Phase 4**: Upgrade `pipeline/prompts/PROMPT.md` and verification hooks to enforce TDD and high-caliber software engineering practices.
