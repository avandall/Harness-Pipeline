#!/usr/bin/env bash
# Pretends to be an interactive login shell for agent-runner resolution tests.
# The real command passed with -c is deliberately ignored.
printf '%s\n' "${LOGIN_SHELL_BIN:?LOGIN_SHELL_BIN is required}"
