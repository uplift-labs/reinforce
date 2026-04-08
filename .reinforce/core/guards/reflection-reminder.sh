#!/bin/bash
# reflection-reminder.sh — Reinforce Guard
# Hook: SessionStart
# Reminds to run /reinforce when 3+ reflections have accumulated
# Fires once per session (startup banner only)

# CI no-op
[ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ] && exit 0

INPUT=$(cat)

# Load config and shared JSON helper
. "$(dirname "$0")/../lib/load-config.sh"
. "$(dirname "$0")/../lib/json-field.sh"

# Loop prevention: one reminder per session
SESSION_ID=$(json_field "session_id" "$INPUT")
[ -z "$SESSION_ID" ] && exit 0
MARKER="/tmp/reinforce-reminder-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0

# Reflections dir and threshold (from config / env / defaults via load-config.sh)
REFLECTIONS_DIR=".reinforce/reflections"
THRESHOLD="$REINFORCE_REMINDER_THRESHOLD"

[ ! -d "$REFLECTIONS_DIR" ] && exit 0

PENDING_COUNT=0
for f in "$REFLECTIONS_DIR"/*.md; do
  [ -f "$f" ] && PENDING_COUNT=$((PENDING_COUNT + 1))
done

# Threshold check
[ "$PENDING_COUNT" -lt "$THRESHOLD" ] && exit 0

# Mark as reminded
touch "$MARKER"

REASON="[reinforce] ${PENDING_COUNT} reflections accumulated in ${REFLECTIONS_DIR}/. Recommend running /reinforce to process them."

# Plain text for startup banner (shown directly via decision:block JSON in adapter)
printf '%s\n' "$REASON"
exit 0
