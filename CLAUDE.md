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

**Data flow:** Capture (session-reflection) → Accumulate (reflections dir) → Remind (reflection-reminder) → Distill (`/reinforce` skill in plan mode) → Apply (user approves)

### Key directories

- `core/guards/` — Three bash guards: `session-reflection.sh`, `reflection-reminder.sh`, `session-quality-audit.sh`
- `core/cmd/reinforce-run.sh` — Multiplexer that groups guards by hook event (`stop`, `user-prompt`, `session-start`), reads stdin once, runs guards in sequence with priority (BLOCK > WARN > pass)
- `core/lib/` — `json-field.sh` (bash JSON extraction), `json-merge.py` (idempotent Python settings merger)
- `adapters/claude-code/hooks/` — Three adapter scripts translating Claude Code hook JSON to core guard protocol
- `skills/reinforce/SKILL.md` — Agentic skill spec for batch-processing reflections

### Design principles

- **Fail-open:** Guards always exit 0, never crash the session. Missing files/tools are skipped gracefully.
- **Idempotent:** `install.sh` and `json-merge.py` can run multiple times safely; hooks are deduplicated by command/prompt.
- **No dependencies:** Pure bash for guards/adapters. Python3 only for JSON merge. `claude` CLI optional (audit guard).

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
- Per-guard disable: `REINFORCE_DISABLE_SESSION_REFLECTION`, `REINFORCE_DISABLE_REFLECTION_REMINDER`, `REINFORCE_DISABLE_SESSION_QUALITY_AUDIT`
- ShellCheck is used; `# shellcheck disable=SC2206` appears where needed

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `REINFORCE_REFLECTIONS_DIR` | `.reinforce/reflections` | Reflections storage |
| `REINFORCE_MIN_TURNS` | `10` | Min assistant turns to trigger reflection |
| `REINFORCE_MIN_TOOLS` | `10` | Min tool uses to trigger |
| `REINFORCE_MIN_LINES` | `200` | Min transcript lines |
| `REINFORCE_REMINDER_THRESHOLD` | `3` | Pending count before reminder fires |
