# Design: Spec-Driven Development via Design Review

## Problem

Implementation success is currently measured by "code works and tests pass" — not by whether the feature achieves its stated goal. The design doc captures what to build and how, but has no measurable success criteria, no review gate, and no mechanism to carry spec compliance through to implementation verification.

Concretely: a plan drafter can produce a technically correct plan that misses the point of the design, and an implementation can pass all tests while failing to deliver the intended outcome. Without explicit success criteria, there's no contract to verify against — "done" means "code was written," not "the goal was met."

This affects every user of the plugin's workflow skills (design → draft-plan → orchestrate → ship).

## Goal

Ensure implementation success is measured against the design spec, not just code correctness, by adding success criteria to design docs, a review gate for designs, and traceability from criteria through planning to implementation verification.

## Success Criteria

- The design doc template includes Problem and Success Criteria sections with human-verifiable behavioral statements
- A design-review skill validates design docs before draft-plan is dispatched — covering structural completeness, spec quality, alternative assessment, feasibility, scope alignment, and handoff quality
- Success criteria flow through the workflow: plan-review checks that every criterion maps to at least one task, implementation-review checks that every criterion is fulfilled by the implementation
- The design doc remains the single source of truth for criteria — downstream skills reference the design doc path, never duplicate criteria
- A user can invoke design-review directly on any existing design doc without going through the design skill workflow

## Architecture

### Design Doc Template Upgrade

Add `## Problem` section before Goal and `## Success Criteria` section between Goal and Architecture. Each criterion:
- Human-verifiable statement about observable behavior or outcome
- Independent of implementation (not "tests pass" or "middleware installed")
- Complete — if all criteria pass, the goal is met; if any is unmet, it isn't

Updated template section ordering: Problem, Goal, Success Criteria, Architecture, Key Decisions, Non-Goals, Implementation Approach.

### Design-Review Skill

New skill: `skills/design-review/` with SKILL.md and reviewer-prompt.md.

Fresh-eyes Opus subagent dispatched after design doc is written. Follows the same prompt-template pattern as plan-review: SKILL.md lists the 8 checks by name with one-line descriptions (matching plan-review's checklist table pattern), reviewer-prompt.md expands each check with specific sub-checks, flag conditions, and heuristics in a fenced code block with `{DESIGN_DOC_PATH}` and `{REPO_PATH}` placeholder variables (matching plan-review's reviewer-prompt.md pattern).

**8-point review checklist:**

1. **Problem Clarity** — specific problem statement, identifies who is affected, states consequences of not solving
2. **Success Criteria Quality** — criteria are human-verifiable, implementation-independent, collectively complete (cover full goal), individually necessary
3. **Architecture-Problem Fit** — architecture addresses the stated problem, appropriately scoped; feasibility check: are there technical risks or unproven assumptions that could derail implementation?
4. **Alternative Assessment** — considers whether more effective or efficient approaches exist. Concrete heuristics: check if any existing skill already partially covers the functionality, check if the codebase has a similar pattern that could be extended, consider established approaches in the problem domain
5. **Scope Alignment** — the design solves the stated problem and not more. Changes are justified by the problem statement. Features or complexity beyond what the problem requires are flagged as potential scope creep. Non-goals are correctly scoped with rationale
6. **Decision Justification** — key decisions include trade-off analysis with alternatives considered
7. **Internal Consistency** — names, paths, and concepts used consistently across all sections. Architecture section matches the file change table. No contradictions between sections
8. **Handoff Quality** — a plan drafter with zero conversation context can produce a correct plan from this doc alone; no implicit assumptions left uncaptured; file paths and change descriptions are specific enough

**Output:** Issues found (category, problem, fix with specific text suggestions) + assessment table (PASS/FAIL per check) + "Ready for planning?" verdict.

**Fix loop:** Design-review runs as a subagent dispatched by the design skill. When the review finds issues, the subagent reports them back. The design skill (running in the main user-interactive context) presents issues to the user, collaborates on fixes to the design doc, then re-dispatches design-review. Same pattern as draft-plan dispatching plan-review and iterating until clean.

### Design Doc Path Propagation

Downstream skills need access to the design doc. The mechanism:

1. **draft-plan** receives the design doc path in its dispatch prompt (already works this way)
2. **draft-plan** writes `design-doc: <path>` into the plan document's YAML frontmatter
3. **plan-review** receives `{DESIGN_DOC_PATH}` as an input variable (already works this way) — reads the full design doc to check architecture alignment and success criteria coverage
4. **orchestrate** extracts the design doc path from plan frontmatter when dispatching implementation-review
5. **implementation-review** receives `{DESIGN_DOC_PATH}` (new variable) — reads only the Goal and Success Criteria sections to verify fulfillment. Does not need the full design (architecture, decisions, etc.)

### Downstream Patches

**plan-review** — new 7th check: "Success Criteria Coverage" — every criterion in the design doc maps to at least one task's "done when" field. A criterion is covered if one or more tasks' "done when" fields collectively satisfy the criterion's behavioral intent (the mapping need not be 1:1). Orphaned criteria flagged.

**implementation-review** — new 8th cross-task category: "Success Criteria Fulfillment" — reads Goal and Success Criteria from the design doc. For each criterion, verifies it's met by the implementation. Partially met or unmet criteria flagged.

**draft-plan** — plan frontmatter gains `design-doc: <path>` field, written by the plan drafter when a design doc exists.

**orchestrate** — when dispatching implementation-review, extracts `design-doc` from plan frontmatter and passes it as `{DESIGN_DOC_PATH}`.

### Workflow Integration

Design skill checklist changes:
```text
Current:  8. Write design doc → 9. Dispatch draft-plan
New:      8. Write design doc → 9. Dispatch design-review → 10. Dispatch draft-plan
```

Design-review blocks draft-plan dispatch (hard gate), same pattern as plan-review blocking orchestrate. The design skill only dispatches draft-plan after design-review passes.

## Key Decisions

1. **Success criteria are human-verifiable, not machine-verifiable** — design docs describe desired outcomes at a behavioral level. Runnable test commands are the plan's job. Criteria like "users can log in" are stable across architecture changes; "pytest tests/auth passes" is not.

2. **Design doc is single source of truth** — downstream skills reference the design doc path via plan frontmatter. Draft-plan and plan-review read the full design doc. Implementation-review reads only goal + success criteria (it verifies outcomes, not architecture).

3. **Design-review is a fresh-eyes subagent** — the designer and user collaborate interactively and converge on an approach, making them both biased toward it. A fresh subagent with no conversation context catches blind spots: unmeasurable criteria, unconsidered alternatives, implicit assumptions.

4. **8-point checklist, not free-form review** — structured checks prevent the reviewer from fixating on one aspect. Each check has clear pass/fail criteria. The 8 checks cover the full quality space: clarity (1), spec quality (2), fitness (3), alternatives (4), scope (5), justification (6), consistency (7), handoff (8). Matches the structured-checklist pattern established by plan-review and implementation-review.

5. **Alternative Assessment targets effectiveness, not simplicity** — the review challenges whether a better or more efficient approach exists, not whether a simpler one does. The goal is the most effective path to meeting success criteria.

6. **Implementation-review gets goal + criteria only** — the implementation reviewer doesn't need to understand the design's architecture or decisions to verify that behavioral outcomes were achieved. Limiting scope keeps the review focused on fulfillment rather than re-evaluating design choices.

## Non-Goals

- No changes to the TDD or testing workflow within tasks — success criteria operate at a higher level than individual test cases
- No changes to orchestrate's execution model — only adding design-doc path extraction for implementation-review dispatch
- No machine-verifiable criteria or automated acceptance testing — future work
- No changes to merge-pr or ship skills
- No migration of existing design docs — new template applies going forward; existing plans without `design-doc` frontmatter continue to work (downstream checks skip when no design doc exists)

## Implementation Approach

Single phase. The changes are to prompt/template files (SKILL.md, reviewer-prompt.md) with no code dependencies between them. The constraint is internal consistency — the criteria format, design doc template, and propagation mechanism must be referenced identically across all modified skills.

### Files Changed/Created

| File | Change |
|------|--------|
| `skills/design-review/SKILL.md` | **Create** — new skill: when to use, dispatch instructions, 8-point checklist summary |
| `skills/design-review/reviewer-prompt.md` | **Create** — reviewer subagent prompt template (fenced code block with `{DESIGN_DOC_PATH}` and `{REPO_PATH}` variables), full 8-point checklist |
| `skills/design/SKILL.md` | **Modify** — update design doc template (add Problem + Success Criteria sections, updated section ordering), add design-review dispatch step between write-doc and draft-plan, update checklist numbering |
| `skills/draft-plan/SKILL.md` | **Modify** — plan frontmatter gains `design-doc: <path>` field |
| `skills/plan-review/SKILL.md` | **Modify** — add 7th check: Success Criteria Coverage |
| `skills/plan-review/reviewer-prompt.md` | **Modify** — add Success Criteria Coverage check to reviewer prompt with mapping guidance |
| `skills/implementation-review/SKILL.md` | **Modify** — add 8th category: Success Criteria Fulfillment, add `{DESIGN_DOC_PATH}` to template variables |
| `skills/implementation-review/reviewer-prompt.md` | **Modify** — add `{DESIGN_DOC_PATH}` input, add Success Criteria Fulfillment category (reads only Goal + Success Criteria sections) |
| `skills/orchestrate/SKILL.md` | **Modify** — extract `design-doc` from plan frontmatter, pass as `{DESIGN_DOC_PATH}` when dispatching implementation-review |
| `.claude-plugin/marketplace.json` | **Modify** — add `./skills/design-review` to `claude-caliper` and `claude-caliper-workflow` plugin skill arrays (not `claude-caliper-tooling`), bump version |
