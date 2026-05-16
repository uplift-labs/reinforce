# reinforce

Automatic reinforcement loop for OpenCode coding sessions. It captures OpenCode session events, writes session reflections, accumulates them, and helps turn repeated lessons into concrete project improvements.

```
Capture -> Accumulate -> Remind -> Distill in plan mode -> Apply after approval
   ^                                                                  |
   +------------------------------------------------------------------+
```

## Why

AI-assisted development creates useful experience every session: mistakes corrected, workflows that worked, and decisions worth revisiting. Without a capture loop, those lessons stay transient and the same issues repeat.

Reinforce closes the loop for OpenCode:

1. **Capture** - the OpenCode plugin records session events into JSON Lines transcripts.
2. **Reflect** - on session deletion, server disposal, or optional idle debounce, a background backend summarizes the transcript.
3. **Accumulate** - reflections collect in `.uplift/reinforce/reflections/`.
4. **Remind** - when enough reflections accumulate, OpenCode receives reminder context to run `$reinforce`.
5. **Distill** - the `$reinforce` skill analyzes patterns and proposes changes in plan mode for user review.
6. **Clean up** - approved retros delete processed reflections after applying improvements.

## Requirements

- Node.js and npm
- OpenCode

## Install

### From Local Clone

```text
npm install
npm run build
node dist/cli/install.js --target /path/to/your-project
```

From inside the target project:

```text
node /path/to/reinforce/dist/cli/install.js
```

### Options

| Flag | Effect |
|------|--------|
| `--target <dir>` | Install into a specific repo (default: current directory) |
| `--prefix <dir>` | Install runtime files under `<dir>/reinforce` (default: `.uplift`) |

OpenCode support is installed by default. There are no host selection flags.

### What gets installed

```
your-project/
├── .uplift/reinforce/
│   ├── adapters/opencode/plugins/reinforce.ts
│   ├── dist/core/config.js
│   ├── dist/core/session-reflect-opencode.js
│   ├── core/templates/reflection-output-prompt-opencode.md
│   ├── config
│   └── reflections/
└── .opencode/
    ├── plugins/reinforce.ts
    └── skills/reinforce/SKILL.md
```

Commit `.uplift/reinforce/` and `.opencode/` so the integration is available in worktrees. Generated `dist/` files are ignored in this repository; rebuild and rerun the installer after source changes. OpenCode project-local plugins require the project config/plugin layer to be trusted by OpenCode.

## How It Works

The native OpenCode plugin captures selected event bus records, including session lifecycle, message updates, command execution, diffs, and status transitions. Events are written to `.uplift/reinforce/opencode/transcripts/` with size limits to avoid unbounded growth.

When reflection is triggered, the plugin starts `.uplift/reinforce/dist/core/session-reflect-opencode.js` with Node.js in the background. By default, the backend runs:

```text
opencode run --pure --format default --dir <repo> --file <transcript> <prompt>
```

You can replace the default backend with `opencode_reflect_command` in `.uplift/reinforce/config`.

## Configuration

Settings are read from `.uplift/reinforce/config` with environment variables taking priority. See `core/config.defaults` for the template.

| Variable / Config key | Default | Purpose |
|----------|---------|---------|
| `REINFORCE_DISABLED` / `disabled` | `false` | Global kill switch (`true`, `1`, or `yes` to disable) |
| `REINFORCE_REMINDER_THRESHOLD` / `reminder_threshold` | `5` | Pending reflections count before OpenCode reminder context is injected |
| `REINFORCE_OPENCODE_REFLECT_COMMAND` / `opencode_reflect_command` | empty | Optional external reflection command; empty uses `opencode run` |
| `REINFORCE_OPENCODE_REFLECT_MODEL` / `opencode_reflect_model` | empty | Optional model override for the default OpenCode backend |
| `REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC` / `opencode_reflect_timeout_sec` | `240` | Watchdog timeout for reflection command |
| `REINFORCE_NODE_COMMAND` / `node_command` | `node` | Node.js command used by the OpenCode plugin to launch the compiled backend |
| `REINFORCE_OPENCODE_IDLE_REFLECT_SEC` / `opencode_idle_reflect_sec` | `0` | Optional idle debounce before reflection; `0` disables idle reflection |
| `REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES` / `opencode_transcript_max_bytes` | `1048576` | Max OpenCode event transcript size per session before truncation |

Also auto-disabled in CI environments (`CI`, `GITHUB_ACTIONS`, `GITLAB_CI`).

## Custom Reflection Command

Custom commands receive the transcript on stdin and these environment variables:

| Variable | Meaning |
|----------|---------|
| `REINFORCE_REFLECT_PROMPT` | Prompt text from `reflection-output-prompt-opencode.md` |
| `REINFORCE_TRANSCRIPT_PATH` | Path to the captured transcript file |
| `REINFORCE_REPO_ROOT` | Repository root |
| `REINFORCE_OUTPUT_FILE` | Suggested output path for command implementations that write files directly |

The command should print either `SKIP` or a markdown reflection to stdout.

## Retro Skill

Run `$reinforce` in OpenCode when reflections have accumulated. The skill:

1. Loads reflection files and project instructions.
2. Triage-validates reflection quality and recency.
3. Extracts repeating mistakes, recurring action items, success patterns, reasoning patterns, and stale lessons.
4. Challenges patterns with skeptic and minimalist checks.
5. Proposes a plan with the smallest high-value improvements.
6. Waits for user approval before applying changes.
7. Deletes processed reflections after approved changes are applied.

## Development

Run the full test suite:

```text
npm test
```

After editing source files under `core/`, `adapters/`, or `skills/`, reinstall into this repo before testing the active project plugin:

```text
npm run install:local
```

## Architecture

```
adapters/opencode/  - OpenCode plugin source
cli/                - TypeScript installer CLI
core/               - TypeScript reflection backend, config loader, prompt template
skills/             - OpenCode retro-processing skill source
tests/              - TypeScript installer and reflection backend tests
```

## License

MIT
