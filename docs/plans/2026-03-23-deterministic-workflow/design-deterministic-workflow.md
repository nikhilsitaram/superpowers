# Deterministic Workflow Gates

## Problem

Agents skip workflow steps — reviews, re-review loops, and PR creation — because enforcement is prose-only. The current skills describe review gates and continuity expectations in natural language, but agents under context pressure ignore these instructions. There's no mechanism to verify a review actually happened, no machine-readable review output, and no script-level gate preventing advancement without completed reviews. This affects anyone using the orchestrate/design workflow: skipped reviews let bugs through, and early stops leave work incomplete.

## Goal

Make the workflow deterministic: reviews can't be skipped, issue counts are tracked with audit trails, re-review loops are enforced, and agents continue through the full workflow to the specified endpoint — all enforced via script gates, not prose.

## Success Criteria

1. Every review produces a machine-parseable record in `reviews.json` that the controlling context verifies before advancing
2. Re-review loops are enforced: >5 actionable issues triggers a fresh reviewer, max 3 iterations before escalation to user
3. Agents cannot mark a phase complete (`validate-plan --update-status`) without a passing impl-review in `reviews.json`
4. Agents cannot mark the plan complete without passing design-review, plan-review, and all phase impl-reviews
5. `validate-plan --check-workflow` verifies the full pipeline reached the expected endpoint (PRs created/merged per workflow choice)
6. Reviews are dispatched by the controlling context (design or orchestrate), not delegated to sub-agents that might skip them
7. Dismissed review items are tracked with reasoning in `reviews.json` for audit trail
8. When invoked from automated merge-pr workflow, review-pr does not offer "Skip fixes, proceed"

## Architecture

### Review JSON Contract

Single `reviews.json` file in the plan directory. Each review cycle appends a record:

```json
[
  {
    "type": "design-review|plan-review|task-review|impl-review",
    "scope": "design|plan|task-A1|phase-A|final",
    "iteration": 1,
    "issues_found": 7,
    "severity": { "critical": 1, "high": 2, "medium": 3, "low": 1 },
    "actionable": 4,
    "dismissed": 3,
    "dismissals": [
      { "issue": "#2", "reason": "Pre-existing pattern, not introduced by this phase" }
    ],
    "fixed": 4,
    "remaining": 0,
    "verdict": "pass|fail",
    "timestamp": "2026-03-23T14:00:00Z"
  }
]
```

Verdict is binary: `pass` (zero remaining issues) or `fail` (issues remain or re-review needed). Only the controlling context writes to `reviews.json` — reviewer subagents output JSON in their response, the controller reads it, triages, fixes, and writes the complete record.

### Review Loop Protocol

Every dispatcher (design, orchestrate, phase-dispatcher) runs the same deterministic loop:

```
MAX_ITERATIONS = 3
iteration = 0

LOOP:
  iteration += 1
  dispatch reviewer → reviewer outputs JSON summary in response
  controller triages: each issue → "fix" or "dismiss" (with reasoning)
  actionable_count = issues categorized as "fix"
  fix all actionable issues

  if actionable_count == 0 and no issues found:
    write record with verdict: "pass" → advance
  if actionable_count <= 5:
    verify fixes, write record with verdict: "pass" → advance
  if actionable_count > 5:
    write record with verdict: "fail"
    if iteration >= MAX_ITERATIONS:
      → escalate to user (AskUserQuestion)
    else:
      → LOOP (dispatch fresh reviewer)
```

### PR Tracking

Add `prs` array to plan.json for tracking PR state:

```json
{
  "prs": [
    { "scope": "phase-A", "number": 42, "url": "https://...", "state": "merged" },
    { "scope": "final", "number": 43, "url": "https://...", "state": "open" }
  ]
}
```

Controlling context writes these after create-pr and merge-pr.

### validate-plan Enforcement

**Gated `--update-status`:**

Phase completion (`--update-status --phase A --status "Complete (...)"`) checks:
- `reviews.json` has a record with `scope: "phase-A"`, `type: "impl-review"`, `verdict: "pass"`

Plan completion (`--update-status --plan --status Complete`) checks:
- All phases have "Complete" status
- Passing design-review in reviews.json
- Passing plan-review in reviews.json
- Passing impl-review for each phase
- Passing final-impl-review if multi-phase

**New `--check-review` flag:**

```bash
validate-plan --check-review plan.json --scope phase-A-impl-review
```

Reads reviews.json, finds latest record matching scope, checks `verdict == "pass"` and `remaining == 0`.

**New `--check-workflow` flag:**

```bash
validate-plan --check-workflow plan.json
```

Checks based on `workflow` field:

| Workflow | Gates |
|----------|-------|
| `plan-only` | design-review passed, plan-review passed |
| `create-pr` | plan-review passed, plan status Complete, all phase PRs + final PR in `prs` array |
| `merge-pr` | everything above + final PR `state == "merged"` |

### Centralized Review Dispatch

**Principle:** The dispatcher owns the loop. Whoever dispatches work also dispatches review, reads results, and decides whether to proceed.

**Before (plan-review buried):**
```
design → design-review (sub) → draft-plan (sub) → plan-review (sub-sub)
```

**After (all reviews at controlling level):**
```
design → design-review (sub) → draft-plan (sub) → plan-review (sub)
orchestrate → phase-dispatcher (sub) → impl-review (sub) → create-pr
```

Task-review stays in phase-dispatcher — it's tightly coupled to per-task implementation and the dispatcher is explicitly a dispatch-only agent.

### Workflow Continuity

Script-enforced via `--check-workflow`. The controlling context calls this as its final action. If gates are unsatisfied, the script exits 1 with the specific missing gates.

Additionally, `--update-status` refuses to advance status if prerequisite reviews haven't passed. This prevents agents from marking phases/plan complete without doing the work.

## Key Decisions

**Single reviews.json vs per-review files:** Single file is simpler to manage and audit. No concurrency issue because orchestrate processes phase completions serially. Trade-off: slightly more complex jq append vs simple file creation.

**Reviewer outputs JSON in response vs writes file directly:** Controller writes to reviews.json, not the reviewer. This ensures only one agent writes to the file and the controller can add triage/resolution fields. Trade-off: reviewer's JSON must be captured from subagent response.

**Re-review threshold on actionable count (post-triage) vs total count:** Actionable count is fairer — if a reviewer produces many false positives, you shouldn't be penalized with re-review cycles. Trade-off: agent could over-dismiss to stay under threshold, but dismissals are tracked for audit.

**Gating --update-status vs separate gate check:** Gating the existing command is more deterministic — the agent already calls --update-status to advance, so the gate is on the natural advancement path. A separate check could be skipped. Trade-off: makes --update-status slower (reads reviews.json).

## Non-Goals

- Validating review quality via script (inherently subjective — script only checks that review happened and passed)
- Full state machine in plan.json (workflow field + reviews.json + prs array is sufficient)
- Changing the >5 threshold (it's about fresh reviewer quality, not a skip mechanism)
- Changing task-review dispatch location (stays in phase-dispatcher)

## Implementation Approach

Single phase — changes are interconnected. Task order:

1. Define reviews.json schema and add `--check-review` to validate-plan
2. Gate `--update-status` on review completion
3. Add `--check-workflow` and `prs` array support to validate-plan
4. Update all reviewer prompts to output JSON summary blocks
5. Add review loop protocol to design, orchestrate, phase-dispatcher
6. Move plan-review dispatch from draft-plan to design
7. Add workflow continuity enforcement to orchestrate
8. Remove "Skip fixes" from review-pr in automated mode
