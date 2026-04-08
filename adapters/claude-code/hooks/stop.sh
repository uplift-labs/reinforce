#!/bin/bash
# stop.sh — Claude Code Stop adapter for Reinforce.
# Translates reinforce-run.sh output to Claude Code Stop JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
export HOOK_EVENT="stop"
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/reinforce-run.sh" stop 2>/dev/null) || true

# Pure-bash JSON escape
_rf_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

case "$RESULT" in
  BLOCK:*)
    reason=$(_rf_escape "${RESULT#BLOCK:}")
    printf '{"decision":"block","reason":"%s"}' "$reason"
    ;;
  WARN:*)
    ctx=$(_rf_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}' "$ctx"
    ;;
esac
exit 0
