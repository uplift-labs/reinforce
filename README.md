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

1. **Capture** — at session end, prompts for a structured reflection (what was asked, done, mistakes, lessons)
2. **Accumulate** — reflections collect in `.reinforce/reflections/pending/`
3. **Remind** — when 3+ reflections accumulate, nudges you to run the retro
4. **Audit** — optional LLM audit catches sycophancy, scope drift, and test quality issues
5. **Distill** — `/reflection-retro` skill analyses patterns across sessions, proposes improvements in **plan mode** for your review

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
│   └── reflections/pending/  # Where reflections accumulate
├── .claude/
│   ├── settings.json         # Hooks merged in (with --with-claude-code)
│   └── skills/reinforce-retro/SKILL.md  # Retro skill (with --with-claude-code)
```

## How it works

### Guards

| Guard | Hook Event | What it does |
|-------|-----------|--------------|
| **session-reflection** | Stop, UserPromptSubmit | Prompts for structured reflection at session end; mid-session checkpoints on long sessions |
| **reflection-reminder** | SessionStart, Stop | Reminds when 3+ reflections are waiting to be processed |
| **session-quality-audit** | Stop | Optional LLM audit of session tail for quality issues (requires `claude` CLI) |

### Retro skill (`/reflection-retro`)

When enough reflections accumulate, run `/reflection-retro`. The skill:

1. **Analyses** all pending reflections (read-only)
2. **Extracts patterns** — repeating mistakes, recurring action items, success patterns
3. **Enters plan mode** — proposes concrete improvements to any project files
4. **You review** — approve, adjust, or reject the plan
5. **Executes** approved changes and commits

## Configuration

All configuration via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `REINFORCE_DISABLED` | — | Set to `1` to disable all guards |
| `REINFORCE_DISABLE_SESSION_REFLECTION` | — | Disable reflection capture |
| `REINFORCE_DISABLE_REFLECTION_REMINDER` | — | Disable accumulation reminders |
| `REINFORCE_DISABLE_SESSION_QUALITY_AUDIT` | — | Disable LLM audit (auto-skipped if `claude` CLI unavailable) |
| `REINFORCE_PENDING_DIR` | `.reinforce/reflections/pending` | Custom reflections directory |
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

## What was asked
## What was done
## What was left undone
## Mistakes and corrections
## Lesson learned
## Action items
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
