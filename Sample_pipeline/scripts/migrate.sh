#!/usr/bin/env bash
# One-command full migration: Plan, then Execute. --one-go changes Execute only;
# Plan always keeps its canonical queue-authoritative per-page flow.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

ONE_GO=0
RESUME=0
PROVIDER=""
PLAN_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --one-go) ONE_GO=1; shift ;;
    --provider)
      [ "$#" -ge 2 ] || { echo "usage: scripts/migrate.sh [--provider NAME] [--one-go] <source|--resume>" >&2; exit 2; }
      PROVIDER="$2"; shift 2
      ;;
    --resume) RESUME=1; shift ;;
    -h|--help)
      echo "usage: scripts/migrate.sh [--provider NAME] [--one-go] <source>"
      echo "       scripts/migrate.sh [--provider NAME] [--one-go] --resume"
      exit 0
      ;;
    *) PLAN_ARGS+=("$1"); shift ;;
  esac
done

[ -z "$PROVIDER" ] || export AGENT_PROVIDER="$PROVIDER"
set +u
plan_arg_count="${#PLAN_ARGS[@]}"
set -u
[ "$RESUME" = "0" ] || [ "$plan_arg_count" -eq 0 ] || { echo "--resume cannot be combined with a new source" >&2; exit 2; }

# Explicit branches avoid empty-array expansion failures under macOS Bash 3.2.
if [ "$RESUME" = "1" ]; then
  scripts/plan.sh || exit $?
else
  set +u
  scripts/plan.sh "${PLAN_ARGS[@]}" || exit $?
  set -u
fi

if [ "$ONE_GO" = "1" ]; then exec scripts/ralph.sh --one-go; else exec scripts/ralph.sh; fi
