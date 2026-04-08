#!/bin/bash
# reinforce-run.sh — Reinforce multiplexer.
# Runs a group of guards, returns the highest-priority result.
#
# Usage: reinforce-run.sh <group>
# Groups: stop | user-prompt | session-start
#
# Input:  JSON on stdin (raw hook payload)
# Output: BLOCK:<reason> | WARN:<context> | empty (allow)
# Exit:   always 0 (fail-open)

set -u

GROUP="${1:-}"
[ -z "$GROUP" ] && { printf 'usage: reinforce-run.sh <group>\n' >&2; exit 0; }

# Global kill switches
[ "${CI:-}" = "true" ] && exit 0
[ "${GITHUB_ACTIONS:-}" = "true" ] && exit 0
[ "${GITLAB_CI:-}" = "true" ] && exit 0
[ "${REINFORCE_DISABLED:-}" = "1" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_DIR="$SCRIPT_DIR/../guards"

# Export hook event for guards that need it
export HOOK_EVENT="$GROUP"

# Map group to guard list
case "$GROUP" in
  stop)          GUARDS="session-reflection reflection-reminder session-quality-audit" ;;
  user-prompt)   GUARDS="session-reflection" ;;
  session-start) GUARDS="reflection-reminder" ;;
  *) exit 0 ;;
esac

# Read stdin once
INPUT=$(cat)

# Priority tracking: BLOCK > WARN > plain text > pass
BEST_WARN=""
BEST_OTHER=""

for guard in $GUARDS; do
  # Per-guard disable: REINFORCE_DISABLE_SESSION_REFLECTION=1, etc.
  env_name="REINFORCE_DISABLE_$(printf '%s' "$guard" | tr 'a-z-' 'A-Z_')"
  eval "[ \"\${${env_name}:-}\" = \"1\" ]" 2>/dev/null && continue

  RESULT=$(printf '%s' "$INPUT" | bash "$GUARD_DIR/$guard.sh" 2>/dev/null) || true

  case "$RESULT" in
    BLOCK:*)
      # Highest priority — short-circuit immediately
      printf '%s' "$RESULT"
      exit 0
      ;;
    WARN:*)
      if [ -z "$BEST_WARN" ]; then
        BEST_WARN="$RESULT"
      else
        BEST_WARN="$BEST_WARN | ${RESULT#WARN:}"
      fi
      ;;
    ?*)
      # Plain text output (e.g. session-start banner)
      [ -z "$BEST_OTHER" ] && BEST_OTHER="$RESULT"
      ;;
  esac
done

# Output highest-priority non-block result
if [ -n "$BEST_WARN" ]; then
  printf '%s' "$BEST_WARN"
elif [ -n "$BEST_OTHER" ]; then
  printf '%s' "$BEST_OTHER"
fi

exit 0
