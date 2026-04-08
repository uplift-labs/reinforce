#!/bin/bash
# session-quality-audit.sh — Reinforce Guard
# Hook: Stop
# LLM audit: sycophancy, scope dodging, test quality, missed findings
# Uses claude -p via Max subscription (no API key needed)
# Optional: set REINFORCE_DISABLE_SESSION_QUALITY_AUDIT=1 to skip

# CI no-op
[ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ] && exit 0

# Check claude CLI availability
command -v claude >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# Load shared JSON helper
. "$(dirname "$0")/../lib/json-field.sh"

# Extract transcript path
TRANSCRIPT=$(json_field "transcript_path" "$INPUT")

# Degrade gracefully when no transcript
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Hard context cap: last 20 lines, each capped at 200 chars, total capped at 2000 chars.
CONTEXT=$(tail -20 "$TRANSCRIPT" 2>/dev/null | cut -c1-200 | head -c 2000)

# Skip short sessions
LINE_COUNT=$(printf '%s' "$CONTEXT" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -lt 8 ]; then
  exit 0
fi

VERDICT=$(printf '%s' "$CONTEXT" | claude -p "Review this session tail for quality problems: scope dodging, empty/trivial tests, dismissed findings, dismissed test failures, sycophancy, missing tests for business logic, duplicated utilities (no codebase search). Reply PASS if clean; FAIL: <one-sentence reason> for the single worst issue." --model haiku 2>&1)

LLM_EXIT=$?
if [ "$LLM_EXIT" -ne 0 ]; then
  echo "[session-quality-audit] LLM call failed (exit $LLM_EXIT): $VERDICT" >&2
  exit 0
fi

case "$VERDICT" in
  PASS*) exit 0 ;;
  FAIL*)
    REASON=$(printf '%s' "$VERDICT" | sed 's/^FAIL: *//')
    printf 'WARN:[session-quality] %s' "$REASON"
    exit 0
    ;;
  *)
    echo "[session-quality-audit] Unexpected LLM response: $VERDICT" >&2
    exit 0
    ;;
esac
