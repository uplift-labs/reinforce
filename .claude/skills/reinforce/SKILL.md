---
name: reinforce
description: Process accumulated session reflections into actionable improvements via plan mode — analyze patterns, propose changes, user reviews, then execute
---

# Reflection Retro

Batch-process session reflections into patterns and concrete project improvements. Works in **plan mode**: analyse first, propose a plan, user reviews, then execute approved changes.

**Trigger:** User says `/reinforce`, or `reflection-reminder` guard signals 3+ reflections at session start.

**Scope boundary:** This skill processes reflection files and produces improvement plans. Session reflections themselves are written by the `session-reflection.sh` guard (Stop hook).

**Resource context:** Claude Max, no API budget. Input: markdown files in reflections directory. Output: improvement plan → user-approved changes → commit.

## Agentic Protocol

- Complete the full retro cycle without stopping — partial analysis leaves patterns undiscovered.
- Use tools to verify every claim — read the actual reflection files, check git history, confirm file paths exist before referencing them.
- Commit applied improvements before finishing.

## Instructions

### Phase 1: Analyse (read-only)

#### Step 0 — Load Context

1. Locate the reflections directory. Check in order: `$REINFORCE_REFLECTIONS_DIR`, `.reinforce/reflections/`, `docs/reflections/`. Use the first that exists.
2. Read all `.md` files in the reflections directory. Count them.
3. If < 3 files, inform user that retro works best with 3+ reflections and ask whether to proceed.
4. Read `CLAUDE.md` (current rules) — needed to avoid duplicate improvements and to count existing rules.
5. Check `git log --oneline -10 -- <reflections-dir>` for recent retro commits — avoid repeating past findings.
6. Load previous retro outcomes: run `git log --format=%B -1 --grep="feat(retro)"` to extract the last retro's applied improvements and their TEST criteria. If found, hold for Step 4 review.
**Gate:** Do not proceed unless you have read all reflections.

#### Step 1 — Triage

For each reflection file, classify:
- **Valid** — has substantive content in at least 4 of 8 template sections
- **Invalid** — empty, stub, malformed (< 5 lines of real content), or automated alerts (e.g., file-size checks)

**Backward compatibility:** older reflections may use previous section names ("What was asked" → "Goal", "What was done" → "Outcome"). Accept both formats.

For each valid reflection, assign a recency tier based on file date:
- **Recent** (< 7 days): full weight for patterns and action items
- **Older** (7–21 days): contributes to patterns; action items deprioritized
- **Stale** (> 21 days): pattern evidence only; action items likely outdated

Output a summary table: filename | valid/invalid | recency | outcome tag (ACCOMPLISHED/PARTIAL/FAILED).

Note invalid files for cleanup. Continue with valid files only.

#### Step 2 — Extract Patterns

Analyze valid reflections using the **ERL heuristic extraction** method:

For each reflection, extract:

| Field | Description |
|-------|-------------|
| **Goal** | From "Goal" section — what the user needed |
| **Outcome** | From "Outcome" section — look for ACCOMPLISHED / PARTIAL / FAILED tag |
| **Wins** | From "What worked" section — effective approaches and tools |
| **Mistakes** | From "Mistakes and corrections" section — causal chains (tried → failed → signal → fix) |
| **Reasoning** | From "Key decision" section — alternatives considered, hindsight evaluation |
| **Lesson** | From "Lesson learned" section — already in WHEN → DO → BECAUSE format |
| **Action items** | From "Action items" section |

Then find **cross-session patterns** using 5 lenses:

1. **REPEATING MISTAKES** — Same error type across 2+ sessions (highest priority)
2. **RECURRING ACTION ITEMS** — Same improvement suggested 2+ times but never applied
3. **SUCCESS PATTERNS** — From "What worked" sections: what tools, approaches, or strategies proved effective consistently? Reinforce, don't discard.
4. **REASONING PATTERNS** — From "Key decision" sections: recurring flaws in decision-making (e.g., always choosing the complex approach when simpler exists, ignoring certain alternatives)
5. **STALE LESSONS** — Same lesson or action item appears in 3+ reflections across different dates, never applied. When detected: do NOT re-propose the same action. Instead escalate — either (a) the action is impractical and should be dropped, (b) it needs a different formulation, or (c) it requires an architectural change rather than a rule.

**Causal linking:** For each PARTIAL or FAILED outcome with a repeating mistake, trace the chain — was the previously proposed fix (a) never applied, (b) applied but ineffective, or (c) applied and the problem recurred for a different reason? This distinction determines what improvement to propose.

**Confidence tags:** Annotate each pattern with evidence strength:
- **Strong** — 4+ reflections show this pattern
- **Moderate** — 2–3 reflections
- **Tentative** — observed but insufficient evidence

Tentative patterns are reported but not acted upon unless they align with a Strong or Moderate pattern.

#### Step 2.5 — Validate Patterns

Before generating improvements, re-examine extracted patterns from two adversarial angles:

1. **Skeptic:** "Which patterns might be coincidence? Am I seeing what I expect? Could a simpler explanation account for this?"
2. **Minimalist:** "What is the smallest change addressing the strongest pattern? Would doing nothing be better than adding more rules?"

Write 2–3 sentences per perspective. If a pattern survives both challenges, proceed. If not, downgrade its confidence or drop it.

#### Step 3 — Generate Improvements

**Retire check first:** Before proposing new improvements, check — are there existing CLAUDE.md rules from previous retros that are (a) contradicted by recent reflections showing they hurt, or (b) redundant with other rules? If so, propose RETIRE items. Removing a bad rule is higher ROI than adding a good one.

For each surviving pattern, produce a **Trigger-Action-Rationale-Test** heuristic:

```
TRIGGER: When [specific condition observed in 2+ reflections]
ACTION: [Concrete step — what to change and where]
RATIONALE: [Why — citing which reflections showed this pattern]
TEST: [How to verify — what observable behavior should change]
```

**Anti-superstition check:** For each proposed improvement, verify it addresses a root cause visible in the reflections, not coincidental correlation. Ask: "Could this pattern be explained by the user working on a specific type of task that naturally produces it?" If yes, note it as context-dependent rather than universal.

Categorize improvements into:

| Category | Action |
|----------|--------|
| **Retire** | Existing rule to remove (highest priority) |
| **Start** | New practice to adopt |
| **Stop** | Practice causing harm to remove |
| **Continue** | Working practice to reinforce |

Limit to **top 3 actionable improvements** (Retire/Start/Stop with Strong or Moderate confidence) + **up to 2 conditional** (lower confidence, explicitly flagged as experimental). Do not pad the list — fewer high-quality improvements beat more mediocre ones. List Continue items separately as validation.

### Phase 2: Plan (enter plan mode)

#### Step 4 — Write Improvement Plan

Enter plan mode and write the plan file with:

**Previous retro review** (if previous retro outcomes loaded in Step 0):
- Which past improvements showed evidence of helping (visible in success patterns or absence of previously-recurring mistakes)?
- Which showed no effect or negative effect?
- Any to retire?

**Context section:**
- How many reflections analysed (valid/invalid breakdown, recency distribution)
- Key patterns found with confidence tags and evidence (which reflections)

**Improvements section (top 3 + up to 2 conditional):**

Priority order: (1) RETIRE items first, (2) Strong confidence Start/Stop, (3) Moderate confidence, (4) Conditional/experimental.

For each improvement:
- What file to change (full path)
- What specifically to change (before → after, or new content)
- Why (citing pattern, confidence tag, and reflections)
- How to verify (TEST criteria)

**CLAUDE.md rule count check:** Before proposing additions to CLAUDE.md, count existing rules. If 15+, flag: "CLAUDE.md has N rules. Consider consolidating or retiring before adding more."

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

1. Delete all processed reflection files from the reflections directory (git history preserves them).
2. Commit all changes with structured metadata:

```
feat(retro): process N reflections, apply M improvements

Patterns found:
- [pattern] (confidence: strong/moderate, evidence: N reflections)

Improvements applied:
1. [improvement] — TEST: [verification criteria]

Retired rules: [list or "none"]
Previous retro assessed: [kept/retired/not-yet-evaluated or "first retro"]
```

## Reinforcement

Full cycle: load → triage (with recency) → extract (5 lenses + causal linking + confidence) → validate (skeptic + minimalist) → generate (retire-first, TART format, anti-superstition) → plan (previous retro review, rule count check) → user review → execute → clean up with structured commit. Every pattern needs evidence from 2+ reflections. Top 3 + up to 2 conditional improvements. Plan mode for user review. Commit before finishing. If the retro process itself needs improving, include SKILL.md changes in the plan like any other improvement.
