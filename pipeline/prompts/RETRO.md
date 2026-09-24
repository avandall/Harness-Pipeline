# 🔄 RETRO — Autonomous Harness Improvement Prompt

You are improving the **Enterprise Agentic Pipeline** by analyzing execution logs from the recent run.

--- TOOL-ERROR & RUNTIME ANALYSIS ---
{{ANALYSIS_REPORT}}

### Directives:
1. Identify systemic, recurring tool errors, permission issues, or instructions where the AI got confused. Ignore one-off transient noise.
2. ⚠️ TIMEOUT / TIME BUDGET SAFEGUARD:
   - If the report indicates timeouts or stalls without underlying tool failures, DO NOT alter `BOUNDARIES.md` or `TECH_CONTEXT.md`.
   - Timeouts mean the scope was too large, not that the architecture rules are broken. Propose breaking down tasks into smaller micro-steps.
3. Improve the authoritative files ONLY when there are genuine, recurring friction points:
   - `pipeline/docs/context/TECH_CONTEXT.md` (missing project commands, tool contracts, path setups)
   - `pipeline/docs/context/BOUNDARIES.md` (clarifying allowed project files & domain constraints)
   - `pipeline/AGENT_GUIDE.md` / `prompts/*` (clarifying task routing & general meta-rules)
   - `pipeline/presets/*` or `pipeline/scripts/verify.py` (optimizing verification checks)
4. ⚠️ STRICT SEPARATION: Project-specific domain logic, class/function names, and framework bugs belong ONLY in `docs/context/` (TECH_CONTEXT, BOUNDARIES) or `LEARNINGS.md`. NEVER pollute the 10 inviolable rules in `AGENT_GUIDE.md` or `prompts/PROMPT.md` with project-specific code details; keep core rules strictly general and universal.
5. Append a structured entry to `pipeline/LEARNINGS.md` with date, topic, root cause, and resolution.
6. Commit the harness improvement with message: `[HARNESS-RETRO] chore: improve agent instructions and configs based on run analysis`.
