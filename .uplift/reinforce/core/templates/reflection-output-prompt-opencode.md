You are reviewing a completed OpenCode coding session transcript attached as a file. Your default action is to output a reflection in markdown. Skipping is an exception, not the norm — the project values having a snapshot of every working session over having a curated subset of "interesting" ones.

The transcript is JSON Lines captured from OpenCode events. It may include prompts, assistant text, tool calls, tool results, errors, status transitions, and truncation markers.

**Skip reflection** by outputting exactly `SKIP` ONLY if ALL of these hold:
- Fewer than 3 meaningful events or tool calls happened
- No file edits, writes, or commits happened
- No decisions, mistakes, or user corrections occurred

If you are uncertain whether a session qualifies as "trivial", output the reflection. A thin reflection is strictly better than no reflection — it still counts as a snapshot for the retro cycle.

Output ONLY the reflection markdown using this exact template:

```markdown
# Session Reflection

**Date:** {{DATESTAMP}}

## Goal
(one sentence: what the user needed accomplished, in their terms not yours)

## Outcome
(start with exactly one tag: ACCOMPLISHED | PARTIAL | FAILED — then 1-2 sentences on what was delivered vs requested)

## What worked
(approaches, tools, or strategies that proved effective — name specific files, commands, or techniques; if nothing notable, write "Routine session, no standout wins")

## Mistakes and corrections
(for each mistake: what you tried -> why it failed -> what signal told you to change -> what fixed it; if no mistakes, write "None")

## What was left undone
(incomplete items with reason: blocked by X, deferred because Y, ran out of context; if nothing, write "All goals met")

## Key decision
(the most consequential choice this session: what alternatives existed, why you chose this path, what you'd choose differently with hindsight)

## Quality check
(check for these issues in the session: scope drift from initial request, sycophantic agreement without evidence, test gaps for changed business logic, dismissed user concerns. Note any issues found or write "Clean")

## Lesson learned
(format: WHEN [specific trigger] -> DO [specific action] BECAUSE [evidence from this session]; not generic advice)

## Action items
(1-2 concrete changes; each must name a specific file, tool, command, or practice — "be more careful" is not an action item)
```

Do not wrap the result in code fences. Do not explain your reasoning. Do not modify files or run tools; only read the attached transcript and produce the reflection.
