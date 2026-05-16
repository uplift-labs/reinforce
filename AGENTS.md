# AGENTS.md

This file provides guidance when working with this repository in OpenCode.

## Project Overview

Reinforce is an automatic reinforcement loop for OpenCode coding sessions. It captures OpenCode session events, summarizes them into reflections, accumulates those reflections, and provides a skill for turning repeated lessons into project improvements.

## Architecture

- `adapters/opencode/plugins/reinforce.ts` is the source OpenCode project plugin.
- `.opencode/plugins/reinforce.ts` is the installed plugin used by this repo.
- `core/cmd/session-reflect-opencode.sh` reads captured OpenCode event transcripts and runs either `opencode run` or a configured external reflection command.
- `core/lib/load-config.sh` loads `.uplift/reinforce/config` for the reflection backend.
- `core/templates/reflection-output-prompt-opencode.md` is the reflection prompt used by the backend.
- `skills/reinforce/SKILL.md` is the source retro-processing skill.
- `.opencode/skills/reinforce/SKILL.md` is the installed skill used by this repo.

OpenCode loads `.opencode/plugins/reinforce.ts` directly. Do not add hook/config layers for other AI tools.

## Commands

Install locally into a repo:

```bash
bash install.sh --target /path/to/repo
```

Run tests:

```bash
bash tests/run.sh
```

After editing files under `core/`, `adapters/`, or `skills/`, rerun the installer to update the installed copy before testing this repo's active OpenCode integration:

```bash
bash install.sh --target .
```

## Development Rules

- Keep the OpenCode plugin in `adapters/opencode/`; keep reusable shell backend logic in `core/`.
- Preserve fail-open behavior. Plugin and background reflection failures must not break OpenCode startup or user sessions.
- Avoid adding runtime dependencies beyond bash, Python-free shell utilities, and OpenCode itself.
- Keep installer changes idempotent. Running `install.sh` twice must not duplicate or corrupt the plugin, skill, config, or installed core files.
- Do not route OpenCode through non-OpenCode hook files. Use native `.opencode/plugins/*.ts` plugin surfaces.
