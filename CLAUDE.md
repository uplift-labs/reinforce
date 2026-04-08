# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reinforce is an automatic reinforcement loop for AI coding sessions. It captures session learnings (reflections), accumulates them, and uses LLM analysis to extract patterns and propose improvements. The system is tool-agnostic at its core, with host-specific adapters (currently Claude Code).

## Architecture

**Core + Adapter pattern:** Tool-agnostic guards in `core/` communicate via stdin JSON / stdout text protocol. Host-specific adapters in `adapters/` translate between the host tool's hook format and the core guards.

**Guard output protocol:**
- `BLOCK:<reason>` — halt the action
- `WARN:<context>` — warn but allow
- Empty — allow silently

**Data flow:** Heartbeat detects session end → `claude -p` generates reflection (background) → Accumulate (reflections dir) → Remind (reflection-reminder) → Distill (`/reinforce` skill in plan mode) → Apply (user approves)

### Key directories

- `core/guards/` — Guard: `reflection-reminder.sh` (reminds to run /reinforce when reflections accumulate)
- `core/cmd/reinforce-run.sh` — Multiplexer that groups guards by hook event, reads stdin once, runs guards in sequence with priority (BLOCK > WARN > pass)
- `core/cmd/session-reflect.sh` — Background reflection orchestrator: calls `claude --resume <session-id> -p` to generate a reflection after session ends
- `core/lib/heartbeat.sh` — Background PID monitor: detects parent Claude Code death, triggers session-reflect.sh
- `core/lib/` — `load-config.sh` (loads `.reinforce/config`), `json-field.sh` (bash JSON extraction), `json-merge.py` (idempotent Python settings merger)
- `core/config.defaults` — Default config template, copied to `.reinforce/config` on install
- `core/templates/` — `reflection.md` (template for reflections), `reflection-prompt.md` (prompt for background `claude -p` call)
- `adapters/claude-code/hooks/` — Two adapter scripts: `session-start.sh` (spawns heartbeat, checks previous session), `stop.sh` (touches heartbeat marker)
- `skills/reinforce/SKILL.md` — Agentic skill spec for batch-processing reflections

### Design principles

- **Fail-open:** Guards always exit 0, never crash the session. Missing files/tools are skipped gracefully.
- **Idempotent:** `install.sh` and `json-merge.py` can run multiple times safely; hooks are deduplicated by command/prompt.
- **No dependencies:** Pure bash for guards/adapters. Python3 only for JSON merge. `claude` CLI required for background reflection.

## Commands

### Install locally into a repo

```bash
bash install.sh --target /path/to/repo --with-claude-code
```

### Install from remote

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/reinforce/main/remote-install.sh) --with-claude-code
```

### Uninstall hooks from settings.json

```bash
python3 core/lib/json-merge.py --uninstall /path/to/.claude/settings.json adapters/claude-code/settings-hooks.json
```

### No build/test/lint pipeline

There are no automated tests. Validation is manual — guards fire via Claude Code hooks, reflections appear in `.reinforce/reflections/`.

## Bash conventions

- Guards use `set -u`, installer uses `set -eu`
- Guards read all stdin into `INPUT=$(cat)`, write results to stdout, log to stderr
- Global kill switches: `REINFORCE_DISABLED=1`, `CI`, `GITHUB_ACTIONS`, `GITLAB_CI` all disable guards
- Per-guard disable: `REINFORCE_DISABLE_REFLECTION_REMINDER`
- ShellCheck is used; `# shellcheck disable=SC2206` appears where needed

## Configuration

Settings are read from `.reinforce/config` (key=value format). Environment variables override config file values.

| Key / Env override | Default | Purpose |
|---|---|---|
| `disabled` / `REINFORCE_DISABLED` | `false` | Global kill switch (`true`, `1`, or `yes` to disable) |
| `reminder_threshold` / `REINFORCE_REMINDER_THRESHOLD` | `5` | Pending reflections count before reminder fires |
| `reflect_model` / `REINFORCE_REFLECT_MODEL` | `opus` | Model for background reflection `claude -p` call |

Per-guard disable via env: `REINFORCE_DISABLE_<GUARD_NAME>=1` (e.g. `REINFORCE_DISABLE_REFLECTION_REMINDER=1`).
