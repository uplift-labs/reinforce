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

1. **Capture** — at session end, prompts for a structured reflection (goal, outcome, what worked, mistakes, key decision, lesson)
2. **Accumulate** — reflections collect in `.reinforce/reflections/`
3. **Remind** — when 3+ reflections accumulate, nudges you to run the retro
4. **Audit** — optional LLM audit catches sycophancy, scope drift, and test quality issues
5. **Distill** — `/reinforce` skill analyses patterns across sessions, proposes improvements in **plan mode** for your review
6. **Clean up** — processed reflections are deleted (git history preserves them)

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
│   ├── core/guards/          # 3 guard scripts
│   ├── core/cmd/             # Multiplexer
│   ├── core/lib/             # JSON utilities
│   ├── adapter/hooks/        # Claude Code adapters (with --with-claude-code)
│   └── reflections/          # Where reflections accumulate
├── .claude/
│   ├── settings.json         # Hooks merged in (with --with-claude-code)
│   └── skills/reinforce/SKILL.md  # Retro skill (with --with-claude-code)
```

## How it works

### Guards

| Guard | Hook Event | What it does |
|-------|-----------|--------------|
| **session-reflection** | Stop, UserPromptSubmit | Prompts for structured reflection at session end; mid-session checkpoints on long sessions |
| **reflection-reminder** | SessionStart, Stop | Reminds when 3+ reflections are waiting to be processed |
| **session-quality-audit** | Stop | Optional LLM audit of session tail for quality issues (requires `claude` CLI) |

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

All configuration via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `REINFORCE_DISABLED` | — | Set to `1` to disable all guards |
| `REINFORCE_DISABLE_SESSION_REFLECTION` | — | Disable reflection capture |
| `REINFORCE_DISABLE_REFLECTION_REMINDER` | — | Disable accumulation reminders |
| `REINFORCE_DISABLE_SESSION_QUALITY_AUDIT` | — | Disable LLM audit (auto-skipped if `claude` CLI unavailable) |
| `REINFORCE_REFLECTIONS_DIR` | `.reinforce/reflections` | Custom reflections directory |
| `REINFORCE_MIN_TURNS` | `10` | Min assistant turns to trigger reflection |
| `REINFORCE_MIN_TOOLS` | `10` | Min tool uses to trigger reflection |
| `REINFORCE_MIN_LINES` | `200` | Min transcript lines to trigger reflection |
| `REINFORCE_REMINDER_THRESHOLD` | `3` | Pending count before reminder fires |

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
