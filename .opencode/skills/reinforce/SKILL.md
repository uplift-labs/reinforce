---
name: reinforce
description: Process OpenCode reinforce reflections into actionable improvements via plan mode; use when the user says $reinforce or asks to process accumulated session reflections.
---

# Reflection Retro

Batch-process OpenCode session reflections into patterns and concrete project improvements. Work in plan mode: analyze first, propose a plan, wait for user approval, then execute approved changes.

**Trigger:** User says `$reinforce`, asks to process reinforce reflections, or OpenCode reminder context says reflections have accumulated.

**Scope boundary:** This skill processes reflection files. Session reflections are written by the OpenCode plugin and background reflection backend.

**Resource context:** Input: markdown files in `.uplift/reinforce/reflections/`. Output: improvement plan, user-approved changes, and cleanup of processed reflection files.

## Agentic Protocol

- Complete the full retro cycle once started; partial analysis leaves patterns undiscovered.
- Verify every claim with tools: read reflection files, check git history, and confirm referenced paths exist.
- Do not apply changes before the user approves the plan.
- Do not commit unless the user explicitly asks for a commit.

## Phase 1: Analyze (Read-Only)

### Step 0: Load Context

1. Locate the reflections directory. Check `$REINFORCE_REFLECTIONS_DIR`, then `.uplift/reinforce/reflections/`. Use the first that exists.
2. Read all `.md` files in the reflections directory and count them.
3. If fewer than 3 files exist, tell the user that the retro works best with 3+ reflections and ask whether to proceed.
4. Read `AGENTS.md` and relevant nested instruction files when present. Use them to avoid duplicate improvements and to count existing rules.
5. Check `git log --oneline -10 -- <reflections-dir>` for recent retro commits to avoid repeating past findings.
6. Load previous retro outcomes with `git log --format=%B -1 --grep="feat(retro)"` when available.

**Gate:** Do not proceed until all reflection files have been read.

### Step 1: Triage

For each reflection file, classify:

| Class | Criteria |
|-------|----------|
| Valid | Has substantive content in at least 4 template sections |
| Invalid | Empty, stub, malformed, shorter than 5 lines of real content, or automated alert noise |

Accept older section names if they appear in existing reflection history, such as "What was asked" for "Goal" or "What was done" for "Outcome".

For each valid reflection, assign recency:

| Tier | Age | Use |
|------|-----|-----|
| Recent | Less than 7 days | Full weight for patterns and action items |
| Older | 7-21 days | Pattern evidence; action items deprioritized |
| Stale | More than 21 days | Pattern evidence only |

Output a summary table: filename, valid/invalid, recency, outcome tag.

### Step 2: Extract Patterns

For each valid reflection, extract:

| Field | Source |
|-------|--------|
| Goal | `Goal` section |
| Outcome | `Outcome` section, especially ACCOMPLISHED / PARTIAL / FAILED |
| Wins | `What worked` section |
| Mistakes | `Mistakes and corrections` causal chains |
| Reasoning | `Key decision` section |
| Lesson | `Lesson learned` section |
| Action items | `Action items` section |

Then find cross-session patterns using these lenses:

1. Repeating mistakes: same error type across 2+ sessions.
2. Recurring action items: same improvement suggested 2+ times but not applied.
3. Success patterns: tools, workflows, or approaches that repeatedly worked.
4. Reasoning patterns: recurring decision flaws or consistently effective reasoning.
5. Stale lessons: same lesson or action item appears across 3+ dates without effective adoption.

For each PARTIAL or FAILED outcome with a repeating mistake, identify whether the previously proposed fix was never applied, applied but ineffective, or the problem recurred for a different reason.

Annotate confidence:

| Confidence | Evidence |
|------------|----------|
| Strong | 4+ reflections |
| Moderate | 2-3 reflections |
| Tentative | Observed but insufficient evidence |

Tentative patterns are reported but not acted on unless they align with a stronger pattern.

### Step 2.5: Validate Patterns

Challenge extracted patterns before proposing improvements:

1. Skeptic: Which patterns might be coincidence, expectation bias, or explained by task type?
2. Minimalist: What is the smallest change addressing the strongest pattern, and would doing nothing be better than adding process?

Downgrade or drop patterns that do not survive these checks.

## Phase 2: Plan / Review

### Step 3: Generate Improvements

Check for retirements before additions. If existing `AGENTS.md` rules are contradicted by recent reflections or are redundant, propose removing or consolidating them before adding new rules.

For each surviving pattern, produce a Trigger-Action-Rationale-Test improvement:

```text
TRIGGER: When [specific condition observed in 2+ reflections]
ACTION: [small concrete change and target file]
RATIONALE: [why, citing reflection evidence]
TEST: [observable verification]
```

Limit output to the top 3 actionable improvements plus up to 2 clearly labeled conditional experiments. Fewer high-quality improvements are better than padded recommendations.

### Step 4: Write the Plan

The plan must include:

| Section | Content |
|---------|---------|
| Previous retro review | What helped, what did not, what to retire |
| Context | Reflection count, valid/invalid breakdown, recency distribution |
| Patterns | Key patterns with confidence and evidence |
| Improvements | File, exact change, rationale, and test criteria |
| Continue | Practices that are working and need no change |
| Cleanup | Reflection files to delete after execution |

Before proposing additions to `AGENTS.md`, count existing rules. If it already has 15+ rules, recommend consolidation or retirement before adding more.

### Step 5: Wait for Approval

Present the plan and wait. The user may approve, adjust, or reject it. Do not execute changes before approval.

## Phase 3: Execute After Approval

### Step 6: Apply Improvements

Apply only the user-approved changes. Keep the diff minimal and targeted.

### Step 7: Clean Up Processed Reflections

1. Delete all processed reflection files from the reflections directory.
2. Verify cleanup with `ls <reflections-dir>/*.md 2>/dev/null | wc -l`.
3. If files remain from the processed batch, delete them before finishing.
4. Stage or commit only if the user explicitly requested that action.

## Reinforcement

Full cycle: load, triage, extract, validate, plan, wait for approval, execute, delete processed reflections, verify deletion. Every actionable pattern needs evidence from 2+ reflections. Prefer retiring or simplifying existing process over adding new rules.
