#!/bin/bash
# load-config.sh — Load .reinforce/config into REINFORCE_* variables.
# Source this file; it exports nothing, only sets variables if not already set.
#
# Config lookup order:
#   1. Environment variable (highest priority — always wins)
#   2. .reinforce/config in project root
#   3. Built-in defaults (lowest priority)
#
# Usage:
#   . "$(dirname "$0")/../lib/load-config.sh"

# --- Locate config file ---
# Try .reinforce/config relative to working directory (project root)
_reinforce_config="${REINFORCE_CONFIG_FILE:-.reinforce/config}"

# --- Built-in defaults ---
_reinforce_default_disabled="false"
_reinforce_default_reminder_threshold="5"
_reinforce_default_reflect_model="opus"

# --- Parse config file into associative-style variables ---
_reinforce_cfg_disabled=""
_reinforce_cfg_reminder_threshold=""
_reinforce_cfg_reflect_model=""

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
    esac
  done < "$_reinforce_config"
fi

# --- Apply: env > config > default ---
REINFORCE_DISABLED="${REINFORCE_DISABLED:-${_reinforce_cfg_disabled:-$_reinforce_default_disabled}}"
REINFORCE_REMINDER_THRESHOLD="${REINFORCE_REMINDER_THRESHOLD:-${_reinforce_cfg_reminder_threshold:-$_reinforce_default_reminder_threshold}}"
REINFORCE_REFLECT_MODEL="${REINFORCE_REFLECT_MODEL:-${_reinforce_cfg_reflect_model:-$_reinforce_default_reflect_model}}"

# Normalize disabled: accept true/1/yes → "1", everything else → ""
case "$REINFORCE_DISABLED" in
  true|1|yes) REINFORCE_DISABLED="1" ;;
  *)          REINFORCE_DISABLED="" ;;
esac

# Cleanup temp vars
unset _reinforce_config _reinforce_default_disabled _reinforce_default_reminder_threshold _reinforce_default_reflect_model
unset _reinforce_cfg_disabled _reinforce_cfg_reminder_threshold _reinforce_cfg_reflect_model
unset _key _val
