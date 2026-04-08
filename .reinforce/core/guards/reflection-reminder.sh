#!/bin/bash
# reflection-reminder.sh — Reinforce Guard
# Hook: Stop, SessionStart
# Reminds to run /reinforce when 3+ reflections have accumulated
# Fires once per session

# CI no-op
[ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ] && exit 0

INPUT=$(cat)

# Load shared JSON helper
. "$(dirname "$0")/../lib/json-field.sh"

# Loop prevention: one reminder per session
SESSION_ID=$(json_field "session_id" "$INPUT")
[ -z "$SESSION_ID" ] && exit 0
MARKER="/tmp/reinforce-reminder-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0

# Configurable reflections dir and threshold
REFLECTIONS_DIR="${REINFORCE_REFLECTIONS_DIR:-.reinforce/reflections}"
THRESHOLD="${REINFORCE_REMINDER_THRESHOLD:-3}"

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

if [ "${HOOK_EVENT:-}" = "session-start" ]; then
  # Plain text for startup banner
  printf '%s Tell the user and recommend running /reinforce.\n' "$REASON"
else
  # Stop event — block to ensure message is relayed
  printf 'BLOCK:%s Tell the user and then stop the session.' "$REASON"
fi
exit 0
