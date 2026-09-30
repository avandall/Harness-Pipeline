# 🛠️ FOLLOW_UP — Post-Completion Operator Request

> **Mode:** Follow-up change request through the standard Harness gates.
> **Operator Request ID:** {{REQUEST_ID}}
> **Original Request Context:** {{ORIGINAL_REQUEST_CONTEXT_SUMMARY}}
> **Operator Change Request:**
> "{{OPERATOR_REQUEST}}"

### Directives & Constraints:

1.  **Strict Adherence & Scope:**
    *   All modifications MUST strictly adhere to the constraints defined in `BOUNDARIES.md` and leverage information from `TECH_CONTEXT.md`.
    *   Only modify files directly relevant to fulfilling `{{OPERATOR_REQUEST}}` and within the allowed boundaries.
    *   DO NOT introduce new files or modify files outside the established scope unless explicitly permitted by `BOUNDARIES.md`.
    *   DO NOT engage in any background processes, external API calls, or actions beyond the immediate file system modifications and script executions specified herein.

2.  **Implementation Rigor:**
    *   Implement the requested modification with the highest standard of code quality: idiomatic, maintainable, minimal diff, and robust.
    *   If `{{OPERATOR_REQUEST}}` is ambiguous, contradictory, or impossible given the current context and boundaries, record it as a blocker and provide a detailed explanation in `pipeline/docs/runtime/PROGRESS_LOG.md` instead of attempting a flawed implementation.

3.  **Deterministic Verification:**
    *   After implementing changes, execute `python3 pipeline/scripts/verify.py`.
    *   **Anti-Cheat:** DO NOT fake the execution or output of `verify.py`. The script MUST be run, and its actual exit code and output MUST be considered.
    *   **Zero Regressions:** The `verify.py` script MUST pass with a zero exit code.
    *   **Failure Recovery:**
        *   If `verify.py` fails (non-zero exit code), immediately record the failure, its output, and a detailed analysis of the root cause in `pipeline/docs/runtime/PROGRESS_LOG.md`.
        *   Attempt to fix the identified regressions. If a fix is applied, re-run `verify.py`.
        *   If regressions persist after a reasonable attempt to fix, or if the issue is deemed unresolvable within the current scope, record it as a critical blocker in `pipeline/docs/runtime/PROGRESS_LOG.md` and halt further action on this request.

4.  **State Persistence & Reporting:**
    *   Ensure ALL modifications are fully written to disk and the file system state is consistent before proceeding.
    *   Create a Git commit: `[FOLLOW-UP] <type>(<scope>): <title>`
        *   The commit body MUST be detailed, including:
            *   **Summary:** A concise overview of the changes.
            *   **Key Changes:** Bullet points detailing specific files modified and the nature of changes.
            *   **Verification:** Explicitly state the outcome of `verify.py` (e.g., "Verification script `verify.py` passed with zero regressions.").
    *   Append a comprehensive summary of ALL actions taken, including the outcome of `verify.py` and any blockers encountered, to `pipeline/docs/runtime/PROGRESS_LOG.md`. This summary MUST reflect the final state of the task.
