#!/bin/bash
# stop.sh — Claude Code Stop adapter for Reinforce.
# Touches heartbeat marker to keep it fresh. No blocking, no guards.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

. "$ROOT/core/lib/json-field.sh"

INPUT=$(cat)
SESSION=$(json_field "session_id" "$INPUT")
[ -z "$SESSION" ] && exit 0

STATE_DIR="/tmp/reinforce-sessions"
MARKER="$STATE_DIR/${SESSION}.marker"
[ -f "$MARKER" ] && touch "$MARKER" 2>/dev/null

exit 0
