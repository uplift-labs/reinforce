#!/bin/bash
# install.sh — install reinforce into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--with-claude-code]
#
# By default installs only the core guards. With --with-claude-code,
# also installs the Claude Code adapter hooks, merges hook config
# into .claude/settings.json, and copies the reinforce skill.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
WITH_CC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --with-claude-code) WITH_CC=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
# .git is a directory in normal repos, a file in worktrees
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

INSTALL_ROOT="$TARGET/.reinforce"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/guards"
mkdir -p "$INSTALL_ROOT/reflections"

# Ensure .gitignore excludes reflections
GITIGNORE="$TARGET/.gitignore"
if ! grep -qF '.reinforce/reflections/' "$GITIGNORE" 2>/dev/null; then
  printf '\n# Reflections are generated per-session, not tracked in git\n.reinforce/reflections/\n' >> "$GITIGNORE"
  printf '[reinforce] added .reinforce/reflections/ to .gitignore\n'
fi

# sync_sh_dir <src_dir> <dest_dir> — mirror *.sh from src into dest.
sync_sh_dir() {
  local src="$1" dest="$2"
  # shellcheck disable=SC2206
  local files=( "$src"/*.sh )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no *.sh files in %s\n' "$src" >&2
    exit 1
  fi
  rm -f "$dest"/*.sh
  cp "${files[@]}" "$dest/" || {
    printf 'install: copy failed %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

printf '[reinforce] copying core to %s\n' "$INSTALL_ROOT/core"
sync_sh_dir "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib"
sync_sh_dir "$SCRIPT_DIR/core/cmd"    "$INSTALL_ROOT/core/cmd"
sync_sh_dir "$SCRIPT_DIR/core/guards" "$INSTALL_ROOT/core/guards"
cp "$SCRIPT_DIR/core/lib/json-merge.py" "$INSTALL_ROOT/core/lib/json-merge.py"
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh "$INSTALL_ROOT/core/guards/"*.sh

# Copy templates
mkdir -p "$INSTALL_ROOT/core/templates"
cp "$SCRIPT_DIR/core/templates/"*.md "$INSTALL_ROOT/core/templates/" 2>/dev/null || true

# Copy default config (don't overwrite existing user config)
if [ ! -f "$INSTALL_ROOT/config" ]; then
  cp "$SCRIPT_DIR/core/config.defaults" "$INSTALL_ROOT/config"
  printf '[reinforce] created default config at %s/config\n' "$INSTALL_ROOT"
fi

if [ "$WITH_CC" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[reinforce] copying Claude Code adapter to %s\n' "$ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/claude-code/hooks" "$ADAPTER_DIR/hooks"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  # Copy reinforce skill
  SKILL_DEST="$TARGET/.claude/skills/reinforce"
  mkdir -p "$SKILL_DEST"
  cp "$SCRIPT_DIR/skills/reinforce/SKILL.md" "$SKILL_DEST/SKILL.md"
  printf '[reinforce] skill installed at %s\n' "$SKILL_DEST"

  # Merge hooks into settings.json
  SNIPPET="$SCRIPT_DIR/adapters/claude-code/settings-hooks.json"
  SETTINGS="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"

  MERGER="$INSTALL_ROOT/core/lib/json-merge.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[reinforce] ERROR: python3 required to merge hooks into settings.json.\n' >&2
    exit 1
  fi
  printf '[reinforce] merging hooks into %s\n' "$SETTINGS"
  python3 "$MERGER" "$SETTINGS" "$SNIPPET"
fi

printf '[reinforce] done.\n'
printf '  core installed at:  %s\n' "$INSTALL_ROOT/core"
printf '  reflections dir:    %s\n' "$INSTALL_ROOT/reflections"
[ "$WITH_CC" -eq 1 ] && printf '  claude-code adapter: %s\n' "$INSTALL_ROOT/adapter"
[ "$WITH_CC" -eq 1 ] && printf '  retro skill:         %s\n' "$TARGET/.claude/skills/reinforce"
printf '\n  Commit .reinforce/ (and .claude/ if using Claude Code)\n'
printf '  so that guards are available in worktrees.\n'
