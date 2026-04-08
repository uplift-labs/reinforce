#!/bin/bash
# session-start.sh — Claude Code SessionStart adapter for Reinforce.
# Translates reinforce-run.sh output to Claude Code SessionStart format.
# Plain text output appears in the startup banner.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
export HOOK_EVENT="session-start"
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/reinforce-run.sh" session-start 2>/dev/null) || true

# SessionStart: plain text goes to banner, BLOCK goes to exit 2
case "$RESULT" in
  BLOCK:*)
    printf '%s' "${RESULT#BLOCK:}" >&2
    exit 2
    ;;
  *)
    # Plain text or WARN — output directly for banner
    [ -n "$RESULT" ] && printf '%s\n' "$RESULT"
    ;;
esac
exit 0
