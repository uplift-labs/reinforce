#!/bin/bash
# heartbeat.sh — Background PID monitor for reinforce reflection.
#
# Launched by the session-start adapter hook. Monitors the parent Claude Code
# process. When the parent dies, invokes session-reflect.sh to generate a
# background reflection via `claude -p`.
#
# Usage:
#   bash heartbeat.sh --marker <path> --session-id <id> --reinforce-root <path> \
#                      [--pid <target-pid>] [--parent-winpid <windows-pid>] \
#                      [--interval <seconds>] [--max-age <seconds>]
#
# Sidecar file:
#   Writes "<heartbeat_pid> <parent_winpid|0> <monitored_pid|0>" to
#   "${MARKER}.hb" on startup. Used by session-start.sh to kill old heartbeats.
#
# Exit conditions (all graceful):
#   - Target PID dies (kill -0 fails) — triggers reflection
#   - Windows parent PID dies (wmic check) — triggers reflection
#   - SIGHUP received (terminal close) — triggers reflection
#   - Marker file deleted
#   - Max age reached (safety valve)

set -u

PID=""
MARKER=""
SESSION_ID=""
REINFORCE_ROOT=""
INTERVAL=2
MAX_AGE=86400   # 24 hours — safety valve
PARENT_WINPID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pid)            PID="$2";            shift 2 ;;
    --marker)         MARKER="$2";         shift 2 ;;
    --session-id)     SESSION_ID="$2";     shift 2 ;;
    --reinforce-root) REINFORCE_ROOT="$2"; shift 2 ;;
    --interval)       INTERVAL="$2";       shift 2 ;;
    --max-age)        MAX_AGE="$2";        shift 2 ;;
    --parent-winpid)  PARENT_WINPID="$2";  shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$MARKER" ] && exit 1
[ -z "$SESSION_ID" ] && exit 1
[ -z "$REINFORCE_ROOT" ] && exit 1

# PID=0 or empty → marker-only mode (no PID monitoring).
_check_pid=1
if [ -z "$PID" ] || [ "$PID" = "0" ]; then
  _check_pid=0
fi

# Windows parent PID monitoring via wmic (MSYS only).
# wmic takes ~200ms per call, so check every N ticks instead of every tick.
_check_winpid=0
WINPID_CHECK_EVERY=2
if [ -n "$PARENT_WINPID" ] && [ "$PARENT_WINPID" != "0" ]; then
  _check_winpid=1
fi

# Write sidecar with our PID.
_hb_sidecar="${MARKER}.hb"
_parent_died=0

# shellcheck disable=SC2329
cleanup() {
  if [ "$_parent_died" = 1 ]; then
    return  # leave sidecar — session-reflect.sh may need it
  fi
  rm -f "$_hb_sidecar" 2>/dev/null
}
trap cleanup EXIT

# SIGHUP arrives when the terminal closes. Treat it as parent death.
trap '_parent_died=1' HUP

printf '%s %s %s' "$$" "${PARENT_WINPID:-0}" "${PID:-0}" > "$_hb_sidecar" 2>/dev/null || exit 1

_start=$(date +%s)
_tick=0

while true; do
  # SIGHUP received — terminal closed, parent is dead.
  [ "$_parent_died" = 1 ] && break

  # Marker gone — someone cleaned up.
  [ -f "$MARKER" ] || break

  # PID mode: target PID dead.
  if [ "$_check_pid" = 1 ]; then
    if ! kill -0 "$PID" 2>/dev/null; then
      _parent_died=1; break
    fi
  fi

  # MSYS Windows PID mode: check native parent every WINPID_CHECK_EVERY ticks.
  if [ "$_check_winpid" = 1 ] && [ $((_tick % WINPID_CHECK_EVERY)) -eq 0 ]; then
    if ! wmic process where "ProcessId=$PARENT_WINPID" get ProcessId /format:value 2>/dev/null \
         | grep -q "ProcessId"; then
      _parent_died=1; break
    fi
  fi

  # Max-age safety valve.
  _now=$(date +%s)
  if [ $((_now - _start)) -ge "$MAX_AGE" ]; then
    break
  fi

  # Refresh marker mtime.
  touch "$MARKER" 2>/dev/null

  sleep "$INTERVAL"
  _tick=$((_tick + 1))
done

# --- On parent death: trigger background reflection ---
if [ "$_parent_died" = 1 ]; then
  _reflect_log="/tmp/reinforce-sessions/heartbeat-${SESSION_ID}.log"
  printf '[%s] heartbeat: parent died, triggering session-reflect\n' \
    "$(date '+%H:%M:%S' 2>/dev/null)" > "$_reflect_log" 2>/dev/null
  bash "$REINFORCE_ROOT/core/cmd/session-reflect.sh" \
    --session-id "$SESSION_ID" \
    --reinforce-root "$REINFORCE_ROOT" \
    </dev/null >> "$_reflect_log" 2>&1 &
fi

exit 0
