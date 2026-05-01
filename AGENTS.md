# AGENTS.md

This file provides guidance to Codex when working with this repository.

## Project Overview

Reinforce is an automatic reinforcement loop for AI coding sessions. It captures session learnings as reflections, accumulates them, and uses agent analysis to extract patterns and propose project improvements.

The system is tool-agnostic at its core, with host-specific adapters:

- `adapters/claude-code/` for Claude Code hooks and skills
- `adapters/codex/` for Codex lifecycle hooks and skills

## Architecture

Core scripts in `core/` communicate through simple stdin/stdout contracts. Host adapters translate each tool's lifecycle JSON into the core protocol.

Guard output protocol:

- `BLOCK:<reason>` — halt the action when the host supports blocking
- `WARN:<context>` — warn but allow
- empty output — allow silently

Claude Code uses `.claude/settings.json` hooks and installs the retro skill into `.claude/skills/reinforce/`.

Codex uses `.codex/hooks.json` with `features.codex_hooks = true` and installs the retro skill into `.agents/skills/reinforce/`.

## Key Directories

- `core/guards/` — tool-agnostic guards such as `reflection-reminder.sh`
- `core/cmd/reinforce-run.sh` — guard multiplexer
- `core/cmd/session-reflect.sh` — Claude Code reflection backend using `claude --resume`
- `core/cmd/session-reflect-codex.sh` — Codex reflection backend using `codex exec` over transcript input
- `core/lib/heartbeat.sh` — background monitor that triggers reflection after parent process death
- `core/lib/load-config.sh` — loads `.uplift/reinforce/config`
- `core/lib/json-merge.py` — idempotent hook JSON merger
- `core/lib/toml-set-bool.py` — minimal TOML feature updater
- `core/templates/` — reflection prompts
- `skills/reinforce/SKILL.md` — retro processing skill

## Commands

Install locally into a repo for Claude Code:

```bash
bash install.sh --target /path/to/repo --with-claude-code
```

Install locally into a repo for Codex:

```bash
bash install.sh --target /path/to/repo --with-codex
```

Install both adapters:

```bash
bash install.sh --target /path/to/repo --with-claude-code --with-codex
```

After editing files under `core/`, `adapters/`, or `skills/`, rerun the installer to update the installed copy before testing.

## Development Rules

- Keep core logic host-agnostic. Put host wire-format translation in `adapters/<host>/`.
- Preserve fail-open behavior. Hooks and background reflection scripts should exit `0` unless the command usage itself is invalid.
- Avoid adding runtime dependencies beyond bash and Python 3.
- Keep installer changes idempotent. Running `install.sh` twice must not duplicate hooks or config entries.
- When adding host hooks, verify both the raw hook output contract and an installed temp-repo flow.
