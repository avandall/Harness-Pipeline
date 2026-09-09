# 🛠️ FOLLOW_UP — Post-Completion Operator Request

> **Mode:** Follow-up change request through the standard Harness gates.
> Operator change request:
> "{{OPERATOR_REQUEST}}"

### Directives:
1. Treat this request with the same rigor as an initial task.
2. Check `BOUNDARIES.md` and `TECH_CONTEXT.md`.
3. Implement the requested modification cleanly.
4. Run `python3 pipeline/scripts/verify.py` to ensure zero regressions across the codebase.
5. Create Git commit: `[FOLLOW-UP] <type>(<scope>): <description>`.
6. Append a summary of changes to `pipeline/docs/runtime/PROGRESS_LOG.md`.
