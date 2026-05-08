#!/bin/bash
# session-reflect-codex.sh - Background reflection orchestrator for Codex.
#
# Reads a Codex transcript and asks `codex exec` to summarize it into a
# reflection. The nested Codex run is read-only; this script writes the final
# markdown file itself to keep file writes deterministic.
#
# Usage:
#   bash session-reflect-codex.sh --session-id <id> --transcript-path <path> \
#                                [--reinforce-root <path>]
#
# Always exits 0 (fail-open). Never blocks the user session.

set -u

SESSION_ID=""
TRANSCRIPT_PATH=""
REINFORCE_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --session-id)      SESSION_ID="$2";      shift 2 ;;
    --transcript-path) TRANSCRIPT_PATH="$2"; shift 2 ;;
    --reinforce-root)  REINFORCE_ROOT="$2";  shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$SESSION_ID" ] && exit 0
[ -z "$TRANSCRIPT_PATH" ] && exit 0

if [ -z "$REINFORCE_ROOT" ]; then
  REINFORCE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

. "$REINFORCE_ROOT/core/lib/load-config.sh"

[ "${REINFORCE_DISABLED}" = "1" ] && exit 0
[ "${CI:-}" = "true" ] && exit 0
[ -n "${GITHUB_ACTIONS:-}" ] && exit 0

_safe_session=$(printf '%s' "$SESSION_ID" | tr '/\\:' '___')
PROJECT_ROOT="$(git -C "$REINFORCE_ROOT" rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$REINFORCE_ROOT")")"
PROJECT_HASH=$(printf '%s' "$PROJECT_ROOT" | tr '/\\:' '___')
STATE_DIR="/tmp/reinforce-sessions/codex/$PROJECT_HASH"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
DEDUP_FILE="$STATE_DIR/${_safe_session}.reflect"
LOCK_DIR="$STATE_DIR/${_safe_session}.lock"

_dedup_state=$(cat "$DEDUP_FILE" 2>/dev/null || true)
case "$_dedup_state" in
  done|skipped) exit 0 ;;
  claimed) [ -d "$LOCK_DIR" ] && exit 0 ;;
esac

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
cleanup_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
trap cleanup_lock EXIT

printf 'claimed' > "$DEDUP_FILE" 2>/dev/null

command -v codex >/dev/null 2>&1 || { rm -f "$DEDUP_FILE" 2>/dev/null; exit 0; }
[ -f "$TRANSCRIPT_PATH" ] || { rm -f "$DEDUP_FILE" 2>/dev/null; exit 0; }

REPO_ROOT="$(git -C "$(dirname "$REINFORCE_ROOT")" rev-parse --show-toplevel 2>/dev/null || dirname "$REINFORCE_ROOT")"
REFLECTIONS_DIR="$REINFORCE_ROOT/reflections"
mkdir -p "$REFLECTIONS_DIR" 2>/dev/null || true

DATESTAMP=$(date '+%Y-%m-%d-%H%M%S' 2>/dev/null || echo "undated")
TARGET_FILE="$REFLECTIONS_DIR/${DATESTAMP}-codex-${_safe_session}-$$.md"
TEMPLATE_FILE="$REINFORCE_ROOT/core/templates/reflection-output-prompt.md"

if [ -f "$TEMPLATE_FILE" ]; then
  PROMPT=$(cat "$TEMPLATE_FILE" 2>/dev/null)
else
  PROMPT="Review the Codex transcript provided on stdin. If trivial, output exactly SKIP. Otherwise output a markdown reflection with sections: Goal, Outcome, What worked, Mistakes and corrections, What was left undone, Key decision, Quality check, Lesson learned, Action items."
fi

PROMPT=$(printf '%s' "$PROMPT" \
  | sed "s|{{DATESTAMP}}|$DATESTAMP|g")

LOG_FILE="$STATE_DIR/session-reflect-codex-${_safe_session}.log"
OUT_FILE="$STATE_DIR/session-reflect-codex-${_safe_session}.out"

_log() { printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null; }

_log "session-reflect-codex started for $_safe_session"
_log "REINFORCE_ROOT: $REINFORCE_ROOT"
_log "TRANSCRIPT_PATH: $TRANSCRIPT_PATH"

if [ -d "$REPO_ROOT" ] && cd "$REPO_ROOT" 2>/dev/null; then
  _log "cwd-set: $REPO_ROOT"
else
  _log "cwd-recovery-failed: $REPO_ROOT missing or cd failed"
  printf 'failed' > "$DEDUP_FILE" 2>/dev/null
  exit 0
fi

WATCHDOG_SEC="${REINFORCE_CODEX_WATCHDOG_SEC:-${REINFORCE_CODEX_REFLECT_TIMEOUT_SEC:-240}}"
MODEL="${REINFORCE_CODEX_REFLECT_MODEL:-}"
EFFORT="${REINFORCE_CODEX_REFLECT_REASONING_EFFORT:-medium}"

_run_with_timeout() {
  local _pid _exit_code _watchdog
  local _cmd=(codex exec -C "$REPO_ROOT" --sandbox read-only --ask-for-approval never -c features.codex_hooks=false)
  [ -n "$MODEL" ] && _cmd+=(--model "$MODEL")
  [ -n "$EFFORT" ] && _cmd+=(-c "model_reasoning_effort=\"$EFFORT\"")
  _cmd+=("$PROMPT")

  REINFORCE_DISABLED=1 "${_cmd[@]}" < "$TRANSCRIPT_PATH" > "$OUT_FILE" 2>> "$LOG_FILE" &
  _pid=$!
  _log "codex pid=$_pid watchdog=${WATCHDOG_SEC}s model=${MODEL:-<default>} effort=${EFFORT:-<default>}"

  (
    _sleep_pid=""
    trap 'kill "$_sleep_pid" 2>/dev/null; exit 0' TERM INT
    sleep "$WATCHDOG_SEC" &
    _sleep_pid=$!
    wait "$_sleep_pid" 2>/dev/null || exit 0
    kill "$_pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  _watchdog=$!

  wait "$_pid" 2>/dev/null
  _exit_code=$?
  kill "$_watchdog" 2>/dev/null || true
  wait "$_watchdog" 2>/dev/null || true

  return "$_exit_code"
}

if _run_with_timeout; then
  OUTPUT=$(cat "$OUT_FILE" 2>/dev/null)
  _compact=$(printf '%s' "$OUTPUT" | tr -d '[:space:]')
  case "$_compact" in
    ""|SKIP)
      _log "SKIPPED: codex returned no reflection"
      printf 'skipped' > "$DEDUP_FILE" 2>/dev/null
      exit 0
      ;;
  esac

  printf '%s\n' "$OUTPUT" > "$TARGET_FILE" 2>/dev/null || {
    _log "FAILED: could not write $TARGET_FILE"
    printf 'failed' > "$DEDUP_FILE" 2>/dev/null
    exit 0
  }
  _log "SUCCESS: reflection file created at $TARGET_FILE"
  printf 'done' > "$DEDUP_FILE" 2>/dev/null
else
  _exit=$?
  _log "FAILED: codex exited with code $_exit"
  printf 'failed' > "$DEDUP_FILE" 2>/dev/null
fi

_log "session-reflect-codex finished"
exit 0
