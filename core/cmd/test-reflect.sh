#!/bin/bash
# test-reflect.sh — Debug tool: test that claude -p can write a file.
#
# Simulates the session-reflect pipeline with a trivial prompt that
# ALWAYS writes a file (no "skip if trivial" logic). Use this to verify
# that claude -p + --dangerously-skip-permissions can create files from
# a background process context.
#
# Usage:
#   bash core/cmd/test-reflect.sh [--session-id <id>]
#
# If --session-id is omitted, uses the most recent session from state dir.
# Writes result to .reinforce/reflections/test-<timestamp>.md

set -u

SESSION_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session-id) SESSION_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load config
. "$ROOT/core/lib/load-config.sh"

REFLECTIONS_DIR=".reinforce/reflections"
DATESTAMP=$(date '+%Y-%m-%d-%H%M' 2>/dev/null || echo "undated")
TARGET_FILE="$REFLECTIONS_DIR/test-${DATESTAMP}.md"

# Auto-detect session ID from state file
if [ -z "$SESSION_ID" ]; then
  STATE_DIR="/tmp/reinforce-sessions"
  _project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _project_hash=$(printf '%s' "$_project" | tr '/\\:' '___')
  PREV_FILE="$STATE_DIR/current-session-${_project_hash}"
  if [ -f "$PREV_FILE" ]; then
    SESSION_ID=$(cat "$PREV_FILE" 2>/dev/null)
  fi
fi

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: no session ID found. Pass --session-id <id> or run from a project with active sessions." >&2
  exit 1
fi

mkdir -p "$REFLECTIONS_DIR" 2>/dev/null

PROMPT="This is a test of the reflection pipeline. Write a file to \`${TARGET_FILE}\` with this exact content:

\`\`\`markdown
# Test Reflection

**Date:** ${DATESTAMP}
**Session:** ${SESSION_ID}
**Status:** Pipeline test successful

This file was created by test-reflect.sh to verify that claude -p can write files.
\`\`\`

Write ONLY this file. Do not output anything else."

echo "=== test-reflect ==="
echo "Session:  $SESSION_ID"
echo "Target:   $TARGET_FILE"
echo "Running claude -p --resume ..."
echo ""

MODEL="$REINFORCE_REFLECT_MODEL"

claude --resume "$SESSION_ID" -p "$PROMPT" \
  --dangerously-skip-permissions \
  --model "$MODEL" \
  2>&1

EXIT_CODE=$?
echo ""
echo "claude exit code: $EXIT_CODE"

if [ -f "$TARGET_FILE" ]; then
  echo "SUCCESS: $TARGET_FILE created"
  echo "--- content ---"
  cat "$TARGET_FILE"
else
  echo "FAILED: $TARGET_FILE was NOT created"
  echo ""
  echo "Checking if any new files appeared in $REFLECTIONS_DIR:"
  ls -lt "$REFLECTIONS_DIR" 2>/dev/null | head -5
fi
