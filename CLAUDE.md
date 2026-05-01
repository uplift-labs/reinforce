# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reinforce is an automatic reinforcement loop for AI coding sessions. It captures session learnings (reflections), accumulates them, and uses LLM analysis to extract patterns and propose improvements. The system is tool-agnostic at its core, with host-specific adapters for Claude Code and Codex.

## Architecture

**Core + Adapter pattern:** Tool-agnostic guards in `core/` communicate via stdin JSON / stdout text protocol. Host-specific adapters in `adapters/` translate between the host tool's hook format and the core guards.

**Guard output protocol:**
- `BLOCK:<reason>` — halt the action
- `WARN:<context>` — warn but allow
- Empty — allow silently

**Adapter-level (Claude Code):** For SessionStart hooks, guards wrap messages as `{"decision":"block","reason":"<message>"}` JSON to stdout (exit 0) — this renders the message directly in Claude Code UI.

**Data flow:** Heartbeat detects session end → host reflection backend generates reflection (background) → Accumulate (reflections dir) → Remind (reflection-reminder) → Distill (`/reinforce` or `$reinforce` skill in plan mode) → Apply (user approves)

### Key directories

- `core/guards/` — Guard: `reflection-reminder.sh` (reminds to run /reinforce when reflections accumulate)
- `core/cmd/reinforce-run.sh` — Multiplexer that groups guards by hook event, reads stdin once, runs guards in sequence with priority (BLOCK > WARN > pass)
- `core/cmd/session-reflect.sh` — Background reflection orchestrator: calls `claude --resume <session-id> -p` to generate a reflection after session ends
- `core/cmd/session-reflect-codex.sh` — Codex reflection orchestrator: reads Codex `transcript_path`, calls `codex exec` read-only, and writes reflection markdown itself
- `core/lib/heartbeat.sh` — Background PID monitor: detects host process death, triggers the appropriate reflection backend
- `core/lib/` — `load-config.sh` (loads installed config), `json-field.sh` (bash JSON extraction), `json-merge.py` (idempotent Python JSON merger), `toml-set-bool.py` (minimal TOML feature updater)
- `core/config.defaults` — Default config template, copied to `.uplift/reinforce/config` on install
- `core/templates/` — `reflection.md` (template for reflections), `reflection-prompt.md` (prompt for background `claude -p` call)
- `adapters/claude-code/hooks/` — Two adapter scripts: `session-start.sh` (spawns heartbeat, checks previous session), `stop.sh` (touches heartbeat marker)
- `adapters/codex/hooks/` — Codex SessionStart/Stop adapters plus `hooks.json`
- `skills/reinforce/SKILL.md` — Agentic skill spec for batch-processing reflections; installed into `.claude/skills` for Claude Code and `.agents/skills` for Codex

### Design principles

- **Fail-open:** Guards always exit 0, never crash the session. Missing files/tools are skipped gracefully.
- **Idempotent:** `install.sh` and `json-merge.py` can run multiple times safely; hooks are deduplicated by command/prompt.
- **No dependencies:** Pure bash for guards/adapters. Python3 only for JSON merge. `claude` CLI required for background reflection.

## Commands

### Install locally into a repo

```bash
bash install.sh --target /path/to/repo --with-claude-code
```

### Install locally into a repo for Codex

```bash
bash install.sh --target /path/to/repo --with-codex
```

### Install from remote

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/reinforce/main/remote-install.sh) --with-claude-code --with-codex
```

### Uninstall hooks from settings.json

```bash
python3 core/lib/json-merge.py --uninstall /path/to/.claude/settings.json adapters/claude-code/settings-hooks.json
```

### No build/test/lint pipeline

Validation is via focused shell tests plus manual host-hook checks. Reflections appear in `.uplift/reinforce/reflections/` by default.

## Bash conventions

- Guards use `set -u`, installer uses `set -eu`
- Guards read all stdin into `INPUT=$(cat)`, write results to stdout, log to stderr
- Global kill switches: `REINFORCE_DISABLED=1`, `CI`, `GITHUB_ACTIONS`, `GITLAB_CI` all disable guards
- Per-guard disable: `REINFORCE_DISABLE_REFLECTION_REMINDER`
- ShellCheck is used; `# shellcheck disable=SC2206` appears where needed

## Configuration

Settings are read from `.uplift/reinforce/config` (key=value format). Environment variables override config file values.

| Key / Env override | Default | Purpose |
|---|---|---|
| `disabled` / `REINFORCE_DISABLED` | `false` | Global kill switch (`true`, `1`, or `yes` to disable) |
| `reminder_threshold` / `REINFORCE_REMINDER_THRESHOLD` | `5` | Pending reflections count before reminder fires |
| `reflect_model` / `REINFORCE_REFLECT_MODEL` | `opus` | Model for background reflection `claude -p` call |
| `codex_reflect_model` / `REINFORCE_CODEX_REFLECT_MODEL` | empty | Optional model override for `codex exec` reflection |
| `codex_reflect_reasoning_effort` / `REINFORCE_CODEX_REFLECT_REASONING_EFFORT` | `medium` | Reasoning effort for `codex exec` reflection |
| `codex_reflect_timeout_sec` / `REINFORCE_CODEX_REFLECT_TIMEOUT_SEC` | `240` | Watchdog timeout for Codex reflection |

Per-guard disable via env: `REINFORCE_DISABLE_<GUARD_NAME>=1` (e.g. `REINFORCE_DISABLE_REFLECTION_REMINDER=1`).

## Development workflow

After editing files under `core/`, `adapters/`, or `skills/`, re-run the installer to update the installed copy before testing:

```bash
bash install.sh --target . --with-claude-code --with-codex
```

The `.uplift/reinforce/` directory contains copies of source files — edits to repo sources do NOT auto-propagate to the installed copy.
