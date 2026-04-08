#!/bin/bash
# session-reflection.sh — Reinforce Guard
# Hook: Stop, UserPromptSubmit
# Two-tier: nudge for short sessions, block for long sessions
# Mid-session: periodic checkpoint via UserPromptSubmit (300+ line growth)

# CI no-op
[ "${CI:-}" = "true" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GITLAB_CI:-}" ] && exit 0

INPUT=$(cat)

# Load shared JSON helper
. "$(dirname "$0")/../lib/json-field.sh"

# Session tracking
SESSION_ID=$(json_field "session_id" "$INPUT")
[ -z "$SESSION_ID" ] && exit 0
MARKER="/tmp/reinforce-reflection-${SESSION_ID}"

# Configurable thresholds
MIN_TURNS="${REINFORCE_MIN_TURNS:-10}"
MIN_TOOLS="${REINFORCE_MIN_TOOLS:-10}"
MIN_LINES="${REINFORCE_MIN_LINES:-200}"

# Configurable pending dir
PENDING_DIR="${REINFORCE_PENDING_DIR:-.reinforce/reflections/pending}"

# Detect hook event
HOOK_EVENT_NAME=$(json_field "hook_event_name" "$INPUT")

# --- UserPromptSubmit: mid-session checkpoint (lightweight) ---
if [ "$HOOK_EVENT_NAME" = "UserPromptSubmit" ]; then
  TRANSCRIPT=$(json_field "transcript_path" "$INPUT")
  [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0
  TRANSCRIPT_LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' \r\n')
  [ -z "$TRANSCRIPT_LINES" ] && exit 0

  # Only check growth if a prior reflection exists (marker file)
  if [ -f "$MARKER" ]; then
    LAST_LINES=$(cat "$MARKER" 2>/dev/null || echo 0)
    GROWTH=$((TRANSCRIPT_LINES - LAST_LINES))
    if [ "$GROWTH" -ge 300 ]; then
      printf '%s' "$TRANSCRIPT_LINES" > "$MARKER" 2>/dev/null
      printf 'WARN:[session-reflection] Mid-session checkpoint: %d new transcript lines since last reflection. Before starting this task — any NEW lessons, repeated mistakes, or changed approach? If yes, write a brief note to %s/. If nothing new, continue.' "$GROWTH" "$PENDING_DIR"
    fi
  fi
  exit 0
fi

# --- Stop: two-tier reflection ---

# Extract transcript path
TRANSCRIPT=$(json_field "transcript_path" "$INPUT")
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# --- Phase 1: Count concrete session metrics ---
ASSISTANT_TURNS=$(grep -c '"role":"assistant"' "$TRANSCRIPT" 2>/dev/null | tr -d ' \r\n')
[ -z "$ASSISTANT_TURNS" ] && ASSISTANT_TURNS=0
TOOL_USES=$(grep -c '"tool_name"' "$TRANSCRIPT" 2>/dev/null | tr -d ' \r\n')
[ -z "$TOOL_USES" ] && TOOL_USES=0
TRANSCRIPT_LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' \r\n')
[ -z "$TRANSCRIPT_LINES" ] && TRANSCRIPT_LINES=0

# --- Phase 1b: Extract Bash errors from transcript ---
RAW_ERRORS=$(grep -oE '"content":"Exit code [1-9][0-9]*\\n[^"]{0,120}' "$TRANSCRIPT" 2>/dev/null \
  | sed 's/"content":"//; s/\\n/: /' )
BASH_ERROR_COUNT=0
ERROR_SUMMARY=""
if [ -n "$RAW_ERRORS" ]; then
  BASH_ERROR_COUNT=$(printf '%s\n' "$RAW_ERRORS" | grep -c '.' 2>/dev/null || echo 0)
  ERROR_SUMMARY=$(printf '%s\n' "$RAW_ERRORS" \
    | sed 's/^\(.\{0,80\}\).*/\1/' \
    | sort | uniq -c | sort -rn \
    | head -5 \
    | sed 's/^ *//')
fi

# --- Threshold check: two-tier ---
SUBSTANTIVE=false
if [ -f "$MARKER" ]; then
  LAST_LINES=$(cat "$MARKER" 2>/dev/null || echo 0)
  GROWTH=$((TRANSCRIPT_LINES - LAST_LINES))
  [ "$GROWTH" -ge 200 ] && SUBSTANTIVE=true
else
  [ "$ASSISTANT_TURNS" -ge "$MIN_TURNS" ] && SUBSTANTIVE=true
  [ "$TOOL_USES" -ge "$MIN_TOOLS" ] && SUBSTANTIVE=true
  [ "$TRANSCRIPT_LINES" -ge "$MIN_LINES" ] && SUBSTANTIVE=true
fi

if [ "$SUBSTANTIVE" = false ]; then
  # Short session — nudge only
  printf 'WARN:[session-reflection] Short session ending (%s turns, %s tool uses). Any lesson learned worth capturing? If yes, write to %s/. If not, just stop.' "$ASSISTANT_TURNS" "$TOOL_USES" "$PENDING_DIR"
  exit 0
fi

# Store transcript size at this reflection point
printf '%s' "$TRANSCRIPT_LINES" > "$MARKER" 2>/dev/null

# --- Build reflection prompt ---
DATESTAMP=$(date '+%Y-%m-%d-%H%M' 2>/dev/null || echo "undated")

# Build optional error section
ERROR_SECTION=""
if [ "$BASH_ERROR_COUNT" -gt 0 ] 2>/dev/null; then
  ERROR_LIST=$(printf '%s\n' "$ERROR_SUMMARY" | sed 's/^ */- /')
  ERROR_SECTION="## Bash errors observed (${BASH_ERROR_COUNT} total)
${ERROR_LIST}"
fi

# Read template from file, fall back to inline
TEMPLATE_DIR="$(dirname "$0")/../templates"
TEMPLATE=$(cat "$TEMPLATE_DIR/reflection.md" 2>/dev/null || echo "")

if [ -n "$TEMPLATE" ]; then
  FILLED=$(printf '%s' "$TEMPLATE" \
    | sed "s/{{DATESTAMP}}/$DATESTAMP/g" \
    | sed "s/{{ASSISTANT_TURNS}}/$ASSISTANT_TURNS/g" \
    | sed "s/{{TOOL_USES}}/$TOOL_USES/g")
  if [ -n "$ERROR_SECTION" ]; then
    FILLED=$(printf '%s' "$FILLED" | awk -v replacement="$ERROR_SECTION" '{gsub(/\{\{ERROR_SECTION\}\}/, replacement); print}')
  else
    FILLED=$(printf '%s' "$FILLED" | sed '/{{ERROR_SECTION}}/d')
  fi
else
  # Fallback inline template
  FILLED="# Session Reflection
**Date:** ${DATESTAMP}
**Turns:** ${ASSISTANT_TURNS}
**Tool uses:** ${TOOL_USES}
${ERROR_SECTION}
## Goal
## Outcome
## What worked
## Mistakes and corrections
## What was left undone
## Key decision
## Lesson learned
## Action items"
fi

REASON="[session-reflection] Session: ${ASSISTANT_TURNS} turns, ${TOOL_USES} tool uses, ${TRANSCRIPT_LINES} transcript lines. Before stopping: write a reflection report to ${PENDING_DIR}/${DATESTAMP}.md using this template:
${FILLED}
Then stop."

printf 'BLOCK:%s' "$REASON"
exit 0
