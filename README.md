# reinforce

Automatic reinforcement loop for AI coding sessions. Captures session reflections, accumulates them, and processes them into concrete project improvements.

```
Capture → Accumulate → Remind → Distill (plan mode) → Apply (user approves) → improved next session
   ↑                                                                                    |
   └────────────────────────────────────────────────────────────────────────────────────┘
```

## Why

AI-assisted development generates experience every session — lessons learned, mistakes corrected, approaches that worked. Without a systematic way to capture and process this experience, the same mistakes repeat and improvements never compound.

reinforce closes this loop automatically:

1. **Capture** — when a session ends, a background process detects it via heartbeat and generates a structured reflection using `claude -p`
2. **Accumulate** — reflections collect in `.reinforce/reflections/`
3. **Remind** — when enough reflections accumulate (default: 5), nudges you to run the retro
4. **Distill** — `/reinforce` skill analyses patterns across sessions, proposes improvements in **plan mode** for your review
5. **Clean up** — processed reflections are deleted (git history preserves them)

## Install

### One-liner (remote)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/reinforce/main/remote-install.sh) --with-claude-code
```

### From local clone

```bash
git clone https://github.com/uplift-labs/reinforce.git
cd your-project
bash /path/to/reinforce/install.sh --with-claude-code
```

### Options

| Flag | Effect |
|------|--------|
| `--target <dir>` | Install into a specific repo (default: current directory) |
| `--with-claude-code` | Install Claude Code hooks, merge settings.json, copy retro skill |

### What gets installed

```
your-project/
├── .reinforce/
│   ├── core/guards/          # Guard scripts
│   ├── core/cmd/             # Multiplexer, background reflection
│   ├── core/lib/             # Config loader, JSON utilities, heartbeat
│   ├── core/templates/       # Reflection prompt and template
│   ├── adapter/hooks/        # Claude Code adapters (with --with-claude-code)
│   ├── config                # Settings (key=value)
│   └── reflections/          # Where reflections accumulate
├── .claude/
│   ├── settings.json         # Hooks merged in (with --with-claude-code)
│   └── skills/reinforce/SKILL.md  # Retro skill (with --with-claude-code)
```

## How it works

### Background reflection

When a Claude Code session ends (process exit or `/clear`), a heartbeat monitor detects it and runs `claude -p` in the background to generate a structured reflection. The reflection is saved to `.reinforce/reflections/` with a timestamp filename. Sessions that are too short or trivial are automatically skipped.

### Guards

Guards run inside Claude Code hooks and produce `BLOCK:<reason>` / `WARN:<context>` / empty output.

| Guard | Hook Event | What it does |
|-------|-----------|--------------|
| **reflection-reminder** | SessionStart | Reminds when pending reflections reach the threshold (default: 5) |

### Retro skill (`/reinforce`)

When enough reflections accumulate, run `/reinforce`. The skill:

1. **Loads context** — reads all reflections, CLAUDE.md rules, and previous retro outcomes
2. **Triages** — classifies valid/invalid, assigns recency tiers (recent/older/stale)
3. **Extracts patterns** — 5 lenses: repeating mistakes, recurring action items, success patterns, reasoning patterns, stale lessons (DoT detection). Adds causal linking and confidence tags (strong/moderate/tentative)
4. **Validates** — skeptic + minimalist adversarial check before generating improvements
5. **Generates improvements** — retire-first approach, Trigger-Action-Rationale-Test format, anti-superstition check. Top 3 + up to 2 conditional
6. **Enters plan mode** — proposes improvements with priority ordering and CLAUDE.md rule count check
7. **You review** — approve, adjust, or reject the plan
8. **Executes** approved changes, deletes processed reflections, commits with structured metadata
9. **Skill feedback** — debiased self-evaluation with objective approval rate metric

## Configuration

Settings are read from `.reinforce/config` (key=value), with environment variables taking priority. See `core/config.defaults` for the template.

| Variable / Config key | Default | Purpose |
|----------|---------|---------|
| `REINFORCE_DISABLED` / `disabled` | `false` | Global kill switch (`true`, `1`, or `yes` to disable) |
| `REINFORCE_REMINDER_THRESHOLD` / `reminder_threshold` | `5` | Pending reflections count before reminder fires |
| `REINFORCE_REFLECT_MODEL` / `reflect_model` | `opus` | Model for background `claude -p` reflection call |
| `REINFORCE_DISABLE_REFLECTION_REMINDER` | — | Set to `1` to disable the reminder guard |

Also auto-disabled in CI environments (`CI`, `GITHUB_ACTIONS`, `GITLAB_CI`).

## Reflection template

Each reflection follows this structure:

```markdown
# Session Reflection

**Date:** 2026-04-08-1530
**Turns:** 45
**Tool uses:** 23

## Goal
(one sentence: what the user needed accomplished, in their terms not yours)

## Outcome
(ACCOMPLISHED | PARTIAL | FAILED — what was delivered vs requested)

## What worked
(effective approaches, tools, strategies — specific files, commands, techniques)

## Mistakes and corrections
(what you tried → why it failed → what signal told you to change → what fixed it)

## What was left undone
(incomplete items with reason: blocked by X, deferred because Y)

## Key decision
(most consequential choice: alternatives, reasoning, hindsight)

## Lesson learned
(WHEN [trigger] → DO [action] BECAUSE [evidence from this session])

## Action items
(1-2 concrete changes naming specific file, tool, command, or practice)
```

## Coexistence

reinforce coexists cleanly with other uplift-labs packages:

- [safeguard](https://github.com/uplift-labs/safeguard) — safety guards (PreToolUse/PostToolUse)
- [dev-discipline](https://github.com/uplift-labs/dev-discipline) — git/commit discipline
- [worktree-sandbox](https://github.com/uplift-labs/worktree-sandbox) — session isolation

Each package uses unique hook markers for idempotent installation. No conflicts.

## Architecture

```
core/           — Tool-agnostic guards (pure bash, stdin JSON / stdout text)
adapters/       — Host-specific translators (Claude Code JSON protocol)
skills/         — Agentic skills (retro processing)
```

Guards output a simple text protocol (`BLOCK:<reason>` / `WARN:<context>`). Adapters translate to the host tool's JSON format. This separation means reinforce can support other AI coding tools by adding new adapters.

## License

MIT
