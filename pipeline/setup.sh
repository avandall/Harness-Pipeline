#!/usr/bin/env bash
# Wrapper for pipeline/scripts/setup.sh
exec "$(dirname "$0")/scripts/setup.sh" "$@"
