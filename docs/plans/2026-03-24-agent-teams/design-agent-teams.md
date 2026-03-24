# Design: Agent Teams for Orchestrate

## Problem

The orchestrate skill's two-level polling supervision (L1: 60s, L2: 30s) has three structural problems:

1. **Token overhead**: ~60K tokens for a 60-minute orchestration, mostly sleep + TaskOutput parsing cycles that produce no useful work.
2. **Fragile detection**: Permission prompt regex, repeated-error heuristics, and no-progress consensus are all brittle against format changes. A single Claude Code UI update can silently degrade detection.
3. **Latency**: Worst-case 3 minutes to detect a stuck agent. Escalation files sit unread for up to 60 seconds between L1 polls.

The phase dispatcher intermediary adds ~1,700 words of prompt per phase. Its sole purpose — sequential task execution + supervision — can be replaced by agent teams with task dependencies and push-based notifications.

The current model also inverts parallelism suboptimally: phases run in parallel (requiring complex rebase-before-merge) while tasks within a phase run sequentially (underutilizing available concurrency).

## Goal

Replace the polling-based supervision architecture with Claude Code agent teams. The orchestrator becomes the team lead, each task becomes a teammate, and push-based idle notifications replace sleep/poll loops. Invert the parallelism model: sequential phases, parallel tasks within each phase.

## Success Criteria

1. A multi-phase plan completes with zero sleep/poll loops in the orchestrator
2. All tasks within a phase execute concurrently (one teammate per task)
3. Phases execute sequentially — Phase B tasks don't start until Phase A is fully merged
4. No git conflicts between teammates — each task touches a unique set of files, enforced at plan time by draft-plan and validated by plan-review and validate-plan
5. Stuck teammates are surfaced to the lead within 30 seconds via idle notification or direct messaging
6. Token overhead for supervision drops by >70% (from ~60K to <15K for a 60-minute orchestration)
7. Single-phase and multi-phase plans both work correctly
8. Per-task reviewers run in parallel as implementer teammates complete, without blocking other active teammates
9. validate-plan catches plan structural errors before execution begins (task prose files, ID format, status consistency, file-set overlaps, phase ordering)

## Architecture

### Current vs Proposed

```
Current:  Orchestrator ──poll 60s──▶ Phase Dispatchers ──poll 30s──▶ Task Implementers
                                     (1 per phase)                   (1 at a time)

Proposed: Lead (orchestrator) ──push notifications──▶ Teammates (1 per task, parallel)
                               ──push notifications──▶ Reviewer Teammates (1 per task, parallel)
```

### Execution Model

For each phase (sequential):

1. Lead reads plan.json, identifies the current phase's tasks
2. Lead spawns one implementer teammate per task — each gets an auto-worktree from the feature branch
3. All teammates execute in parallel (non-overlapping file sets guaranteed by plan constraints)
4. As each teammate completes, lead receives an idle notification (no polling)
5. Lead dispatches a reviewer teammate for each completed task — reviewers run concurrently with still-active implementers
6. When all implementers + reviewers for the phase are done:
   - Lead merges all task branches into the feature branch (no conflicts due to file-set isolation)
   - Lead runs implementation review (cross-task holistic) for the phase
   - Lead creates + merges phase PR (if multi-phase) or final PR (if single-phase)
7. Move to next phase from the updated feature branch

### Parallelism Inversion

| Dimension | Current | Proposed |
|-----------|---------|----------|
| Phases | Parallel (DAG-based waves) | Sequential |
| Tasks within phase | Sequential | Parallel (non-overlapping files) |
| Supervision | Polling (60s/30s) | Push (idle notifications) |
| Per-task review | Serial (after each task) | Parallel (as tasks complete) |

Sequential phases eliminate rebase-before-merge complexity. Parallel tasks within a phase are safe because each task touches a unique file set — enforced at plan time, validated before execution.

### File-Set Isolation

Each task in plan.json declares its file set via the existing `files` object (`create`, `modify`, `test` arrays). The constraint: no two tasks in the same phase may share any file path across any of these arrays.

Enforcement chain:
- **draft-plan**: Decomposes work so each task owns a unique file set
- **plan-review**: Validates file-set isolation as a review criterion
- **validate-plan**: Deterministic check — rejects plans with overlapping `create`, `modify`, or `test` paths within a phase

### Teammate Responsibilities

Implementer teammates are autonomous. Each teammate:

1. Reads its task metadata and prose
2. Marks task in-progress via `validate-plan --update-status`
3. Implements via TDD (red/green/refactor)
4. Commits work
5. Self-reviews
6. Writes task completion notes to `{PHASE_DIR}/{task_id_lower}-completion.md`
7. Marks task complete via `validate-plan --update-status`
8. Reports back to lead

This is a change from the current model where the phase dispatcher handles steps 1, 2, 7, and writes a single phase-level completion.md. With the dispatcher eliminated, teammates self-manage their lifecycle.

### Review Stack

1. **Per-task reviewer teammate** — dispatched by lead when an implementer teammate finishes. Runs the 6-point checklist (spec fidelity, TDD discipline, test quality, correctness, security, simplicity). Produces structured review-summary JSON. Runs concurrently with other active teammates.
2. **Implementation review** — after all tasks + reviews in a phase complete, a fresh-eyes Opus subagent reviews the full phase diff for cross-task issues (duplication, inconsistency, dead code).
3. **No per-task review blocking** — reviewer teammates don't block implementer teammates in the same phase.

### Escalation

Teammates that hit unresolvable issues send a structured message directly to the lead via the agent team mailbox. The lead receives it immediately (no polling delay). The lead can:
- Respond with guidance and keep the teammate working
- Stop the teammate and reassign the task
- Escalate to the user via AskUserQuestion

### Git Strategy

- **Single-phase**: Feature branch directly. Teammates work in auto-worktrees from the feature branch. Lead merges task branches into feature branch, creates PR to main.
- **Multi-phase**: `integrate/<feature>` branch. Per-phase, teammates work in auto-worktrees. Lead merges task branches into integration branch, creates phase PR. Final PR: integration branch → main.
- **Between phases**: Lead merges all task branches, ensuring the next phase's teammates start from the fully-integrated codebase.
- **No rebase-before-merge**: Phases are sequential, so the integration branch is never contested by parallel phase merges.

## Key Decisions

1. **Sequential phases, parallel tasks** — inverts the current model. Eliminates rebase-before-merge complexity. Tasks within a phase run concurrently because each touches a unique file set (enforced at plan time).

2. **File-set isolation as a plan constraint** — each task declares its file set in plan.json. No two tasks in the same phase share files. draft-plan enforces this at authoring time, plan-review validates it, validate-plan rejects violations deterministically.

3. **Flat hierarchy (no phase dispatcher)** — lead coordinates tasks directly. Phase boundaries enforced through sequential execution, not intermediary agents. Eliminates ~1,700 words of phase-dispatcher prompt per phase.

4. **Push-based completion, no polling** — idle notifications replace sleep/poll loops at both levels. Zero token overhead for supervision.

5. **Per-task reviewer teammates in parallel** — dispatched as implementer teammates finish. Run concurrently with still-active implementers. Same quality gate, no serial blocking.

6. **Agent teams only** — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. No fallback to polling. Simplifies implementation — one code path.

7. **Teammates self-manage lifecycle** — mark their own tasks in-progress/complete, write their own completion notes. The lead validates but doesn't micromanage.

8. **Comprehensive validate-plan checks** — 8 new deterministic checks catch structural errors before execution begins, reducing runtime failures.

## Non-Goals

- Parallel phase execution (sequential phases by design)
- Backward compatibility with polling-based supervision
- Language-specific linting or tooling in hooks
- Nested teams or sub-teams
- Auto-recovery from all failure modes (lead escalates to user when stuck)
- Fallback to subagent polling when agent teams feature flag is off

## Implementation Approach

**Single phase** — the changes are tightly coupled. The orchestrate SKILL.md rewrite depends on the implementer prompt changes, which depend on the validate-plan updates. Splitting into multiple phases would create intermediate broken states where the skill references features that don't exist yet.

### Tasks

1. **Update plan.json schema** — remove `supervision` config object, document `file_set` constraint for the `files` object (already has `create`/`modify`/`test` arrays)
2. **Update draft-plan** — enforce file-set isolation when decomposing tasks within a phase
3. **Update plan-review** — validate file-set isolation as a review criterion
4. **Rewrite orchestrate SKILL.md** — replace wave loop + supervision with agent team coordination (sequential phases, parallel teammates, push-based completion)
5. **Delete phase-dispatcher-prompt.md** — no longer needed with flat hierarchy
6. **Update implementer-prompt.md** — teammates mark task in-progress/complete, write per-task completion notes
7. **Update task-reviewer-prompt.md** — adapt for teammate dispatch model (reviewer is a teammate, not a subagent of the phase dispatcher)
8. **Update validate-plan** — add 8 new checks: task prose files exist, task ID format matches phase, status consistency (task→phase→plan), files exist after completion, file-set overlap for modify/test within phase, task completion file exists when complete, no orphaned task files, phase letter ordering
9. **Bump version** — increment in marketplace.json
