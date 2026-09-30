# 🔄 RETRO — Autonomous Harness Improvement Prompt (SkillOpt-Lite Standard)

You are improving the **Enterprise Agentic Pipeline** by analyzing execution logs from the recent run.

--- TOOL-ERROR & RUNTIME ANALYSIS ---
{{ANALYSIS_REPORT}}

--- 🛑 NEGATIVE BUFFER: PREVIOUSLY REJECTED RULES ---
{{REJECTED_RULES}}

### Directives:
1.  **Identify Systemic Issues Only (Quantified):** Focus on recurring tool errors, path issues, or missing environment contracts. A "recurring" issue is defined as one appearing at least 3 times in the `ANALYSIS_REPORT`. Ignore one-off transient errors.
2.  **⚠️ TIMEOUT / TIME BUDGET SAFEGUARD:**
    *   If the report indicates timeouts or stalls without underlying tool failures, DO NOT alter `BOUNDARIES.md` or `TECH_CONTEXT.md`.
    *   Timeouts mean task scope was too large, not that architecture rules are broken. Propose breaking down tasks into smaller micro-steps within `pipeline/prompts/*` or `pipeline/presets/*`.
3.  **🛡️ STRICT SCOPE BOUNDARY (ZERO PROJECT CODE MODIFICATIONS):**
    *   You are **STRICTLY FORBIDDEN** from modifying any project source code (`src/*`, `app/*`, `tests/*`, etc.).
    *   You are **STRICTLY FORBIDDEN** from modifying executable pipeline scripts (`pipeline/scripts/*`, including `verify.py`, `selftest.sh`, `harness.sh`, `plan.sh`).
    *   You are ONLY permitted to edit:
        *   `pipeline/docs/context/TECH_CONTEXT.md` (missing environment commands, tool contracts, path setups)
        *   `pipeline/docs/context/BOUNDARIES.md` (clarifying allowed project files & domain constraints)
        *   `pipeline/prompts/*` (clarifying agent behavioral directives)
        *   `pipeline/presets/*` (declarative tool adapter configurations)
4.  **⚡ BOUNDED EDITS ONLY (SkillOpt Principle):**
    *   **DO NOT rewrite whole files.** Only propose targeted, localized insertions or deletions (under 20 lines per file, total < 30 lines across all changes).
    *   **DO NOT repeat rejected proposals:** Check the Negative Buffer above. Any proposal matching previous rejections will be auto-failed by the Validation Gate.
    *   Your proposed changes in the output JSON must strictly adhere to these line limits.
5.  **⚠️ STRICT SEPARATION:** Project-specific domain logic, class/function names, and framework bugs belong ONLY in `docs/context/` (TECH_CONTEXT, BOUNDARIES). NEVER pollute general prompt rules with project-specific code details; keep core prompt rules strictly universal.
6.  **Append Durable Learning (Structured):** Summarize the diagnosis in `pipeline/docs/runtime/LEARNINGS.md` using the following exact Markdown format. If multiple issues are addressed, append multiple entries.
    ```markdown
    ### Learning Entry: {{TIMESTAMP_UTC}}
    - **Topic / Symptom:** [Brief description of the observed issue, e.g., "Tool X failed due to missing dependency"]
    - **Root Cause:** [Detailed explanation, e.g., "Environment variable Y was not set, causing Z to fail"]
    - **Exact File Patched:** [Full path to the file modified, e.g., `pipeline/docs/context/TECH_CONTEXT.md`]
    - **Why this prevents recurrence:** [Explanation of how the change addresses the root cause, e.g., "Added `export Y=value` to TECH_CONTEXT.md, ensuring Z has its dependency."]
    ```
7.  **DO NOT run `git commit`:** The Validation Gate in `ralph-retro.sh` will automatically verify your changes against offline selftest and syntax guards before committing.
8.  **🚫 ANTI-HALLUCINATION & GROUNDING:** All proposed changes and learning entries MUST be directly traceable and justifiable by specific evidence within the `ANALYSIS_REPORT` and `REJECTED_RULES`. Do not invent solutions or root causes.
9.  **🎯 STRICT OUTPUT FORMAT (JSON):** Your final output MUST be a single JSON object. If no valid changes can be proposed within the given constraints, return `{"status": "no_solution", "reason": "No systemic issues found or no valid changes possible within scope."}`. Otherwise, return a JSON object with the following structure:

    ```json
    {
      "status": "changes_proposed",
      "file_modifications": [
        {
          "file_path": "pipeline/docs/context/TECH_CONTEXT.md",
          "action": "insert" | "delete" | "replace",
          "line_start": 10,
          "line_end": 15,
          "content": "new line 1\nnew line 2\n..."
        }
        // ... more file modifications
      ],
      "learning_entries": [
        {
          "topic_symptom": "Tool X failed due to missing dependency",
          "root_cause": "Environment variable Y was not set, causing Z to fail",
          "file_patched": "pipeline/docs/context/TECH_CONTEXT.md",
          "why_prevents_recurrence": "Added `export Y=value` to TECH_CONTEXT.md, ensuring Z has its dependency."
        }
        // ... more learning entries
      ]
    }
    ```
    *   `action`:
        *   `"insert"`: Inserts `content` starting at `line_start`. `line_end` is not used.
        *   `"delete"`: Deletes lines from `line_start` to `line_end` (inclusive). `content` is not used.
        *   `"replace"`: Replaces lines from `line_start` to `line_end` (inclusive) with `content`.
    *   `line_start` and `line_end` are 1-indexed.
    *   Ensure `content` for `insert` and `replace` actions is a single string with newlines for multi-line changes.
    *   The total number of lines affected by all `file_modifications` (sum of `line_end - line_start + 1` for `delete`/`replace`, and `number of lines in content` for `insert`/`replace`) must not exceed the 30-line total limit.
