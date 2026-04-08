#!/bin/bash
# user-prompt.sh — Claude Code UserPromptSubmit adapter for Reinforce.
# Translates reinforce-run.sh output to Claude Code UserPromptSubmit JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
export HOOK_EVENT="user-prompt"
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/reinforce-run.sh" user-prompt 2>/dev/null) || true

# Shared JSON escape
. "$ROOT/core/lib/escape.sh"

case "$RESULT" in
  BLOCK:*)
    reason=$(rf_escape "${RESULT#BLOCK:}")
    # UserPromptSubmit block = exit 2 with stderr message
    printf '%s' "$reason" >&2
    exit 2
    ;;
  WARN:*)
    ctx=$(rf_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$ctx"
    ;;
esac
exit 0
