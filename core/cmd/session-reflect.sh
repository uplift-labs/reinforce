#!/bin/bash
# session-reflect.sh — Background reflection orchestrator.
# Invoked by heartbeat.sh (on parent death) or session-start.sh (on /clear).
# Calls `claude --resume <session-id> -p <prompt>` to generate a reflection.
# The LLM decides whether the session is worth reflecting on.
#
# Usage:
#   bash session-reflect.sh --session-id <id> [--reinforce-root <path>]
#
# Always exits 0 (fail-open). Never blocks anything.

set -u

SESSION_ID=""
REINFORCE_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session-id)     SESSION_ID="$2";     shift 2 ;;
    --reinforce-root) REINFORCE_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$SESSION_ID" ] && exit 0

# Auto-detect reinforce root from script location
if [ -z "$REINFORCE_ROOT" ]; then
  REINFORCE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

# Load config
. "$REINFORCE_ROOT/core/lib/load-config.sh"

# --- Global kill switches ---
[ "${REINFORCE_DISABLED}" = "1" ] && exit 0
[ "${CI:-}" = "true" ] && exit 0
[ -n "${GITHUB_ACTIONS:-}" ] && exit 0

# --- Paths (absolute — must not depend on CWD, which may be a worktree) ---
REPO_ROOT="$(dirname "$REINFORCE_ROOT")"
REFLECTIONS_DIR="$REPO_ROOT/.reinforce/reflections"
STATE_DIR="/tmp/reinforce-sessions"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# --- Deduplication: atomic mkdir ensures exactly one caller wins ---
DEDUP_FILE="$STATE_DIR/${SESSION_ID}.reflect"
[ -f "$DEDUP_FILE" ] && exit 0

if ! mkdir "$STATE_DIR/${SESSION_ID}.lock" 2>/dev/null; then
  exit 0  # another process already claimed this session
fi
printf 'claimed' > "$DEDUP_FILE" 2>/dev/null
rmdir "$STATE_DIR/${SESSION_ID}.lock" 2>/dev/null

# --- Check claude CLI ---
command -v claude >/dev/null 2>&1 || { rm -f "$DEDUP_FILE" 2>/dev/null; exit 0; }

# --- Build prompt ---
DATESTAMP=$(date '+%Y-%m-%d-%H%M' 2>/dev/null || echo "undated")
TEMPLATE_FILE="$REINFORCE_ROOT/core/templates/reflection-prompt.md"

if [ -f "$TEMPLATE_FILE" ]; then
  PROMPT=$(cat "$TEMPLATE_FILE" 2>/dev/null)
else
  # Inline fallback — minimal prompt
  PROMPT="Analyze the session above. If it contained substantive work, write a reflection to ${REFLECTIONS_DIR}/${DATESTAMP}.md with sections: Goal, Outcome, What worked, Mistakes, What was left undone, Key decision, Quality check, Lesson learned, Action items. If trivial, output nothing."
fi

# Substitute placeholders
PROMPT=$(printf '%s' "$PROMPT" \
  | sed "s|{{REFLECTIONS_DIR}}|$REFLECTIONS_DIR|g" \
  | sed "s|{{DATESTAMP}}|$DATESTAMP|g")

# --- Log file for diagnostics ---
LOG_DIR="$STATE_DIR"
LOG_FILE="$LOG_DIR/session-reflect-${SESSION_ID}.log"

_log() { printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null; }

_log "session-reflect started for $SESSION_ID"
_log "cwd(initial): $(pwd 2>/dev/null || echo '<unresolvable>')"
_log "REINFORCE_ROOT: $REINFORCE_ROOT"

# --- Cwd: always use main repo root ---
# Heartbeat inherits cwd from its launcher (often a sandbox worktree).
# Even if the worktree CWD is valid, `claude --resume` should run from
# the main repo root so conversation lookup works correctly.
# REPO_ROOT is already set above from REINFORCE_ROOT.
if [ -d "$REPO_ROOT" ] && cd "$REPO_ROOT" 2>/dev/null; then
  _log "cwd-set: $REPO_ROOT"
else
  _log "cwd-recovery-failed: $REPO_ROOT missing or cd failed — aborting"
  printf 'failed' > "$DEDUP_FILE" 2>/dev/null
  exit 0
fi
_log "cwd(effective): $(pwd)"
_log "REFLECTIONS_DIR: $REFLECTIONS_DIR"

# --- Ensure reflections dir exists (after cwd recovery so it lands in the right place) ---
mkdir -p "$REFLECTIONS_DIR" 2>/dev/null || true

# --- Run reflection via claude -p with timeout ---
MODEL="$REINFORCE_REFLECT_MODEL"

# Snapshot reflections dir before
_before=$(ls "$REFLECTIONS_DIR" 2>/dev/null | wc -l)

# Timeout wrapper: configurable via REINFORCE_CLAUDE_WATCHDOG_SEC (default 240s).
# Raised from 120s → 240s because larger models on long sessions with the full
# retro prompt were consistently hitting SIGTERM (exit 143) at 120s.
WATCHDOG_SEC="${REINFORCE_CLAUDE_WATCHDOG_SEC:-240}"
_run_with_timeout() {
  local _pid _exit_code
  claude --resume "$SESSION_ID" -p "$PROMPT" \
    --dangerously-skip-permissions \
    --model "$MODEL" \
    >> "$LOG_FILE" 2>&1 &
  _pid=$!
  _log "claude pid=$_pid model=$MODEL watchdog=${WATCHDOG_SEC}s"

  # Background watchdog
  ( sleep "$WATCHDOG_SEC" && kill "$_pid" 2>/dev/null ) &
  local _watchdog=$!

  wait "$_pid" 2>/dev/null
  _exit_code=$?
  kill "$_watchdog" 2>/dev/null || true
  wait "$_watchdog" 2>/dev/null || true

  return "$_exit_code"
}

if _run_with_timeout; then
  _after=$(ls "$REFLECTIONS_DIR" 2>/dev/null | wc -l)
  if [ "$_after" -gt "$_before" ]; then
    _log "SUCCESS: reflection file created ($_before -> $_after files)"
    printf 'done' > "$DEDUP_FILE" 2>/dev/null
  else
    _log "SKIPPED: claude exited 0 but no new file (session likely trivial or wrong path)"
    _log "  reflections dir listing: $(ls -1 "$REFLECTIONS_DIR" 2>/dev/null | tr '\n' ' ')"
    _log "  resolved reflections abs: $(cd "$REFLECTIONS_DIR" 2>/dev/null && pwd -P || echo '<missing>')"
    printf 'skipped' > "$DEDUP_FILE" 2>/dev/null
  fi
else
  _exit=$?
  _log "FAILED: claude exited with code $_exit"
  printf 'failed' > "$DEDUP_FILE" 2>/dev/null
fi

_log "session-reflect finished"
exit 0
