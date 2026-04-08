You are reviewing a completed coding session. Analyze the conversation above and decide whether it contains substantive work worth reflecting on.

**Skip reflection** (write nothing, output nothing) if:
- The session was trivial (just a question, a quick lookup, fewer than ~5 meaningful exchanges)
- The session was interrupted before meaningful work happened
- No lessons, mistakes, decisions, or outcomes worth capturing

**If the session IS worth reflecting on**, write a reflection file to `{{REFLECTIONS_DIR}}/{{DATESTAMP}}.md` using this exact template:

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
(for each mistake: what you tried → why it failed → what signal told you to change → what fixed it; if no mistakes, write "None")

## What was left undone
(incomplete items with reason: blocked by X, deferred because Y, ran out of context; if nothing, write "All goals met")

## Key decision
(the most consequential choice this session: what alternatives existed, why you chose this path, what you'd choose differently with hindsight)

## Quality check
(check for these issues in the session: scope drift from initial request, sycophantic agreement without evidence, test gaps for changed business logic, dismissed user concerns. Note any issues found or write "Clean")

## Lesson learned
(format: WHEN [specific trigger] → DO [specific action] BECAUSE [evidence from this session]; not generic advice)

## Action items
(1-2 concrete changes; each must name a specific file, tool, command, or practice — "be more careful" is not an action item)
```

Write ONLY the reflection file. Do not explain your reasoning. If the session is not worth reflecting on, output nothing.
