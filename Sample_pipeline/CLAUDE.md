# Claude Code entry point

Read and follow [`AGENT_GUIDE.md`](AGENT_GUIDE.md). It is the provider-neutral source of truth for this repository.
Claude-specific path rules under `.claude/rules/` remain additional automatic guidance.

> Harness-engineering note: this adapter is deliberately tiny. Provider files (`CLAUDE.md`, `AGENTS.md`) point at ONE
> shared router so the harness never forks per tool. Keep it that way.
