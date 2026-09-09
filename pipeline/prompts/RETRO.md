# 🔄 RETRO — Autonomous Harness Improvement Prompt

You are improving the **Enterprise Agentic Pipeline** by analyzing execution logs from the recent run.

--- TOOL-ERROR & RUNTIME ANALYSIS ---
{{ANALYSIS_REPORT}}

### Directives:
1. Identify systemic, recurring tool errors, permission issues, or instructions where the AI got confused. Ignore one-off transient noise.
2. Improve the authoritative files to eliminate recurrence:
   - `pipeline/docs/context/TECH_CONTEXT.md` (missing commands, path setups)
   - `pipeline/docs/context/BOUNDARIES.md` (clarifying allowed files)
   - `pipeline/AGENT_GUIDE.md` / `prompts/*` (clarifying task routing & rules)
   - `pipeline/presets/*` or `pipeline/scripts/verify.py` (optimizing verification checks)
3. Append a structured entry to `pipeline/LEARNINGS.md` with date, topic, root cause, and resolution.
4. Commit the harness improvement with message: `[HARNESS-RETRO] chore: improve agent instructions and configs based on run analysis`.
