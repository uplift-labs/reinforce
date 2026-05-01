#!/bin/bash
# stop.sh - Codex Stop adapter for Reinforce.
# Touches heartbeat marker. Stop fires per turn in Codex, so this hook must not
# emit continuation JSON unless reinforce explicitly needs another turn.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

. "$ROOT/core/lib/json-field.sh"

INPUT=$(cat)
SESSION=$(json_field "session_id" "$INPUT")
[ -z "$SESSION" ] && exit 0

SESSION_SAFE=$(printf '%s' "$SESSION" | tr '/\\:' '___')
PROJECT_ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$ROOT")")"
PROJECT_HASH=$(printf '%s' "$PROJECT_ROOT" | tr '/\\:' '___')
STATE_DIR="/tmp/reinforce-sessions/codex/$PROJECT_HASH"
MARKER="$STATE_DIR/${SESSION_SAFE}.marker"
[ -f "$MARKER" ] && touch "$MARKER" 2>/dev/null

exit 0
