---
name: reflection-retro
description: Process accumulated session reflections into actionable improvements via plan mode — analyze patterns, propose changes, user reviews, then execute
---

# Reflection Retro

Batch-process session reflections into patterns and concrete project improvements. Works in **plan mode**: analyse first, propose a plan, user reviews, then execute approved changes.

**Trigger:** User says `/reflection-retro`, or `reflection-reminder` guard signals 3+ pending reflections at session start.

**Scope boundary:** This skill processes reflection files and produces improvement plans. Session reflections themselves are written by the `session-reflection.sh` guard (Stop hook).

**Resource context:** Claude Max, no API budget. Input: markdown files in reflections pending directory. Output: improvement plan → user-approved changes → commit.

## Agentic Protocol

- Complete the full retro cycle without stopping — partial analysis leaves patterns undiscovered.
- Use tools to verify every claim — read the actual reflection files, check git history, confirm file paths exist before referencing them.
- Commit applied improvements before finishing.

## Instructions

### Phase 1: Analyse (read-only)

#### Step 0 — Load Context

1. Locate the reflections directory. Check in order: `$REINFORCE_PENDING_DIR`, `.reinforce/reflections/pending/`, `docs/reflections/pending/`. Use the first that exists.
2. Read all `.md` files in the pending directory. Count them.
3. If < 3 files, inform user that retro works best with 3+ reflections and ask whether to proceed.
4. Read `CLAUDE.md` (current rules) — needed to avoid duplicate improvements.
5. Check `git log --oneline -10 -- <pending-dir>` for recent retro commits — avoid repeating past findings.

**Gate:** Do not proceed unless you have read all pending reflections.

#### Step 1 — Triage

For each reflection file, classify:
- **Valid** — has substantive content in at least 3 of 6 template sections
- **Invalid** — empty, stub, malformed (< 5 lines of real content), or automated alerts (e.g., file-size checks)

Note invalid files for cleanup. Continue with valid files only.

#### Step 2 — Extract Patterns

Analyze valid reflections using the **ERL heuristic extraction** method:

For each reflection, extract:

| Field | Description |
|-------|-------------|
| **Goal** | What was the user trying to do? |
| **Outcome** | Accomplished / Partially / Failed |
| **Mistakes** | From "Mistakes and corrections" section |
| **Lesson** | From "Lesson learned" section |
| **Action items** | From "Action items" section |

Then find **cross-session patterns** using 3 lenses:

1. **REPEATING MISTAKES** — Same error type across 2+ sessions (highest priority)
2. **RECURRING ACTION ITEMS** — Same improvement suggested 2+ times but never applied
3. **SUCCESS PATTERNS** — What worked well consistently? Reinforce, don't discard.

#### Step 3 — Generate Improvements

For each pattern found, produce a **Trigger-Action-Rationale** heuristic:

```
TRIGGER: When [specific condition observed in 2+ reflections]
ACTION: [Concrete step — what to change and where]
RATIONALE: [Why — citing which reflections showed this pattern]
```

Categorize improvements into:

| Category | Action |
|----------|--------|
| **Start** | New practice to adopt |
| **Stop** | Practice causing harm to remove |
| **Continue** | Working practice to reinforce |

Limit to **top 5 actionable improvements** (Start/Stop only). List Continue items separately as validation — they don't count toward the 5.

### Phase 2: Plan (enter plan mode)

#### Step 4 — Write Improvement Plan

Enter plan mode and write the plan file with:

**Context section:**
- How many reflections analysed (valid/invalid breakdown)
- Key patterns found with evidence (which reflections)

**Improvements section (top 5 Start/Stop):**
For each improvement:
- What file to change (full path)
- What specifically to change (before → after, or new content)
- Why (citing pattern and reflections)

Improvements can target **anything the analysis warrants**:
- CLAUDE.md rules
- Code, scripts, utilities
- Configuration files
- Skills or guard scripts
- Documentation
- New files if needed

**Continue section:**
- What's working well, keep doing (no action needed)

**Cleanup section:**
- Which reflection files to delete after execution (all processed files)

#### Step 5 — Exit Plan Mode

Call ExitPlanMode so the user can review the proposed improvements. The user will approve, adjust, or reject.

### Phase 3: Execute (after user approval)

#### Step 6 — Apply Improvements

Apply all user-approved improvements from the plan.

#### Step 7 — Clean Up and Commit

1. Delete all processed reflection files from the pending directory (git history preserves them).
2. Commit all changes with: `feat(retro): process N reflections, apply M improvements`
3. Include in the commit body: patterns found and improvements applied.

### Phase 4: Skill Feedback

#### Step 8 — Capture Skill Improvement Signal

Reflect on the retro process:
- Did pattern extraction find real patterns or noise?
- Were the improvements actionable or too vague?
- Did any improvement conflict with existing rules?

If you identify a concrete improvement to this skill:
1. Append a structured entry to `.reinforce/skill-feedback.md`:
   ```
   ## [date] Retro feedback
   **Problem:** [what went wrong or could be better in the retro process]
   **Suggestion:** [specific change to SKILL.md — what to add/remove/modify]
   **Evidence:** [which reflections showed this]
   ```
2. Do NOT edit SKILL.md directly — the skill spec is a stable contract maintained via PRs.
3. Inform the user: "Skill improvement suggestion saved to `.reinforce/skill-feedback.md`. Consider submitting as a PR to uplift-labs/reinforce."

## Reinforcement

Full cycle: load → triage → extract → plan → user review → execute → clean up. Every pattern needs evidence from 2+ reflections. Top 5 improvements max. Plan mode for user review. Commit before finishing. Skill improvements go to feedback file, never to SKILL.md directly.
