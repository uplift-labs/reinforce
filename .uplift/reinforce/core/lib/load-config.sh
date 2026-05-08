#!/bin/bash
# load-config.sh — Load installed reinforce config into REINFORCE_* variables.
# Source this file; it exports nothing, only sets variables if not already set.
#
# Config lookup order:
#   1. Environment variable (highest priority — always wins)
#   2. installed reinforce config
#   3. Built-in defaults (lowest priority)
#
# Usage:
#   . "$(dirname "$0")/../lib/load-config.sh"

# --- Locate config file ---
# Derive install dir from this script's location (core/lib/load-config.sh → install root)
_reinforce_install_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"
_reinforce_config="${REINFORCE_CONFIG_FILE:-$_reinforce_install_dir/config}"

# --- Built-in defaults ---
_reinforce_default_disabled="false"
_reinforce_default_reminder_threshold="5"
_reinforce_default_reflect_model="opus"
_reinforce_default_codex_reflect_model=""
_reinforce_default_codex_reflect_reasoning_effort="medium"
_reinforce_default_codex_reflect_timeout_sec="240"
_reinforce_default_opencode_reflect_command=""
_reinforce_default_opencode_reflect_model=""
_reinforce_default_opencode_reflect_timeout_sec="240"
_reinforce_default_opencode_idle_reflect_sec="0"
_reinforce_default_opencode_transcript_max_bytes="1048576"

# --- Parse config file into associative-style variables ---
_reinforce_cfg_disabled=""
_reinforce_cfg_reminder_threshold=""
_reinforce_cfg_reflect_model=""
_reinforce_cfg_codex_reflect_model=""
_reinforce_cfg_codex_reflect_reasoning_effort=""
_reinforce_cfg_codex_reflect_timeout_sec=""
_reinforce_cfg_opencode_reflect_command=""
_reinforce_cfg_opencode_reflect_model=""
_reinforce_cfg_opencode_reflect_timeout_sec=""
_reinforce_cfg_opencode_idle_reflect_sec=""
_reinforce_cfg_opencode_transcript_max_bytes=""

if [ -f "$_reinforce_config" ]; then
  while IFS='=' read -r _key _val; do
    # Skip comments and blank lines
    case "$_key" in
      \#*|"") continue ;;
    esac
    # Trim whitespace
    _key=$(printf '%s' "$_key" | tr -d '[:space:]')
    _val=$(printf '%s' "$_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$_key" in
      disabled)            _reinforce_cfg_disabled="$_val" ;;
      reminder_threshold)  _reinforce_cfg_reminder_threshold="$_val" ;;
      reflect_model)       _reinforce_cfg_reflect_model="$_val" ;;
      codex_reflect_model) _reinforce_cfg_codex_reflect_model="$_val" ;;
      codex_reflect_reasoning_effort) _reinforce_cfg_codex_reflect_reasoning_effort="$_val" ;;
      codex_reflect_timeout_sec) _reinforce_cfg_codex_reflect_timeout_sec="$_val" ;;
      opencode_reflect_command) _reinforce_cfg_opencode_reflect_command="$_val" ;;
      opencode_reflect_model) _reinforce_cfg_opencode_reflect_model="$_val" ;;
      opencode_reflect_timeout_sec) _reinforce_cfg_opencode_reflect_timeout_sec="$_val" ;;
      opencode_idle_reflect_sec) _reinforce_cfg_opencode_idle_reflect_sec="$_val" ;;
      opencode_transcript_max_bytes) _reinforce_cfg_opencode_transcript_max_bytes="$_val" ;;
    esac
  done < "$_reinforce_config"
fi

# --- Apply: env > config > default ---
REINFORCE_DISABLED="${REINFORCE_DISABLED:-${_reinforce_cfg_disabled:-$_reinforce_default_disabled}}"
REINFORCE_REMINDER_THRESHOLD="${REINFORCE_REMINDER_THRESHOLD:-${_reinforce_cfg_reminder_threshold:-$_reinforce_default_reminder_threshold}}"
REINFORCE_REFLECT_MODEL="${REINFORCE_REFLECT_MODEL:-${_reinforce_cfg_reflect_model:-$_reinforce_default_reflect_model}}"
REINFORCE_CODEX_REFLECT_MODEL="${REINFORCE_CODEX_REFLECT_MODEL:-${_reinforce_cfg_codex_reflect_model:-$_reinforce_default_codex_reflect_model}}"
REINFORCE_CODEX_REFLECT_REASONING_EFFORT="${REINFORCE_CODEX_REFLECT_REASONING_EFFORT:-${_reinforce_cfg_codex_reflect_reasoning_effort:-$_reinforce_default_codex_reflect_reasoning_effort}}"
REINFORCE_CODEX_REFLECT_TIMEOUT_SEC="${REINFORCE_CODEX_REFLECT_TIMEOUT_SEC:-${_reinforce_cfg_codex_reflect_timeout_sec:-$_reinforce_default_codex_reflect_timeout_sec}}"
REINFORCE_OPENCODE_REFLECT_COMMAND="${REINFORCE_OPENCODE_REFLECT_COMMAND:-${_reinforce_cfg_opencode_reflect_command:-$_reinforce_default_opencode_reflect_command}}"
REINFORCE_OPENCODE_REFLECT_MODEL="${REINFORCE_OPENCODE_REFLECT_MODEL:-${_reinforce_cfg_opencode_reflect_model:-$_reinforce_default_opencode_reflect_model}}"
REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC="${REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC:-${_reinforce_cfg_opencode_reflect_timeout_sec:-$_reinforce_default_opencode_reflect_timeout_sec}}"
REINFORCE_OPENCODE_IDLE_REFLECT_SEC="${REINFORCE_OPENCODE_IDLE_REFLECT_SEC:-${_reinforce_cfg_opencode_idle_reflect_sec:-$_reinforce_default_opencode_idle_reflect_sec}}"
REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES="${REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES:-${_reinforce_cfg_opencode_transcript_max_bytes:-$_reinforce_default_opencode_transcript_max_bytes}}"

# Normalize disabled: accept true/1/yes → "1", everything else → ""
case "$REINFORCE_DISABLED" in
  true|1|yes) REINFORCE_DISABLED="1" ;;
  *)          REINFORCE_DISABLED="" ;;
esac

# Cleanup temp vars
unset _reinforce_config _reinforce_default_disabled _reinforce_default_reminder_threshold _reinforce_default_reflect_model
unset _reinforce_default_codex_reflect_model _reinforce_default_codex_reflect_reasoning_effort _reinforce_default_codex_reflect_timeout_sec
unset _reinforce_default_opencode_reflect_command _reinforce_default_opencode_reflect_model _reinforce_default_opencode_reflect_timeout_sec
unset _reinforce_default_opencode_idle_reflect_sec _reinforce_default_opencode_transcript_max_bytes
unset _reinforce_cfg_disabled _reinforce_cfg_reminder_threshold _reinforce_cfg_reflect_model
unset _reinforce_cfg_codex_reflect_model _reinforce_cfg_codex_reflect_reasoning_effort _reinforce_cfg_codex_reflect_timeout_sec
unset _reinforce_cfg_opencode_reflect_command _reinforce_cfg_opencode_reflect_model _reinforce_cfg_opencode_reflect_timeout_sec
unset _reinforce_cfg_opencode_idle_reflect_sec _reinforce_cfg_opencode_transcript_max_bytes
unset _key _val
