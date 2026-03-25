# Design: Execution Modes for Orchestration

## Problem

The orchestrate skill currently requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — an experimental env var that can't be set mid-session (child shell can't modify parent process environment). This blocks users without the flag from using orchestration entirely (#124). Additionally, agent teams is overkill for small plans (#127). Users need execution mode options scaled to plan complexity.

## Goal

Let users choose how orchestration executes tasks — sequentially in the main context, in parallel via subagents, or in parallel via agent teams — with the choice stored in plan.json and enforced by orchestrate.

## Success Criteria

1. Users can orchestrate a 3-task single-phase plan using main context mode (no env var, no subagent dispatch)
2. Users can orchestrate an 8-task plan using subagent mode with parallel worktree-isolated dispatches (no agent teams env var required)
3. Users can orchestrate a 12-task multi-phase plan using agent teams mode (existing behavior preserved)
4. Design skill presents a combined decision point (workflow extent + execution mode + design approval) as a single AskUserQuestion with auto-suggested execution mode
5. When a user selects agent-teams without the env var set, they receive the exact shell command to run and instructions to restart Claude Code
6. `validate-plan --schema` rejects plan.json files with missing or invalid `execution_mode` values
7. All existing tests continue to pass (no regressions)

## Architecture

### Three Execution Modes

| Mode | `execution_mode` value | Dispatch mechanism | Parallelism | Env requirement |
|------|----------------------|-------------------|-------------|-----------------|
| Main context | `main` | Lead implements directly | Sequential | None |
| Subagents | `subagents` | Agent tool + `isolation: "worktree"` + `run_in_background` | Parallel | None |
| Agent teams | `agent-teams` | Teammate spawn (current model) | Parallel + push notifications + mailbox | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |

### Auto-Suggestion Thresholds

Based on estimated task count and phase count from design discussion:

- **≤5 tasks** → suggest `main`
- **≤10 tasks AND ≤2 phases** → suggest `subagents`
- **>10 tasks OR >2 phases OR >3 tasks able to run in parallel** → suggest `agent-teams`

### Review Feedback Loop Per Mode

- **main**: Lead fixes directly after review findings
- **subagents**: Dispatch a NEW implementer subagent with original task context + reviewer findings (no mailbox — can't reuse the original agent)
- **agent-teams**: Send review feedback to original implementer via mailbox (current behavior)

### Files Changed

**Design skill:**
- `skills/design/SKILL.md` — Remove agent teams prerequisite section. Replace steps 7+8 with combined AskUserQuestion. Add auto-suggestion logic and agent-teams fallback flow.

**Orchestrate skill:**
- `skills/orchestrate/SKILL.md` — Read `execution_mode` at setup. Replace inline dispatch/completion sections with `Read ./dispatch-${EXEC_MODE}.md`.
- `skills/orchestrate/dispatch-main.md` — New: sequential execution protocol
- `skills/orchestrate/dispatch-subagents.md` — New: parallel Agent tool dispatch protocol
- `skills/orchestrate/dispatch-agent-teams.md` — New: extracted current teammate protocol

**Plan infrastructure:**
- `scripts/validate-plan` — Add `execution_mode` to schema as required enum
- `skills/draft-plan/SKILL.md` (or supporting file) — Pass execution_mode through to plan.json

**Tests:**
- `tests/validate-plan/test_schema.sh` — New cases for execution_mode validation

## Key Decisions

1. **execution_mode is a required enum in plan.json** (`["main", "subagents", "agent-teams"]`). Draft-plan writes it; validate-plan enforces it.
2. **Mode-specific dispatch lives in separate template files** — keeps orchestrate SKILL.md under the 1,500-word budget while supporting three distinct dispatch protocols.
3. **No mid-plan mode switching** — execution_mode is read once at setup and fixed for the plan's lifetime.
4. **No automatic shell profile modification** — design skill provides the exact command but does not run it. This eliminates the #124 confusion.
5. **Combined decision point** — workflow extent + execution mode + design approval in a single AskUserQuestion reduces back-and-forth.
6. **Subagent review fixes use fresh agents** — no mailbox emulation. The new subagent receives original task context + reviewer findings.

## Non-Goals

- Mid-plan mode switching
- Automatic shell profile modification
- Subagent mailbox emulation
- Backward compatibility with plans missing `execution_mode` (new field is required; old plans without it fail schema validation — this is acceptable since plans are ephemeral)

## Implementation Approach

Single phase — all changes are tightly coupled (design reads mode, orchestrate dispatches on mode, plan schema validates mode).

8 tasks with dependency structure:
- T1 (schema) → [T2 (design SKILL.md), T3 (extract dispatch-agent-teams.md), T7 (draft-plan)] → [T4 (dispatch-subagents.md), T5 (dispatch-main.md)] → T6 (refactor orchestrate SKILL.md) → T8 (tests)

Parallel waves: T1 → [T2, T3, T7] → [T4, T5] → T6 → T8
