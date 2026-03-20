# Design: Success Criteria Runner

## Problem

Success criteria fields exist in plan.json at task, phase, and plan levels — but nothing executes them. "Plan complete" is a status label, not a verified outcome. The orchestration pipeline has no programmatic way to catch when a task claims completion but doesn't actually meet its criteria. This gap means criteria are decorative: the schema validates their structure, but the promises they encode are never checked.

## Goal

Add a `--criteria` mode to `scripts/validate-plan` that executes `success_criteria` entries from plan.json, reports pass/fail per criterion with severity awareness, and integrates into the orchestration pipeline at task, phase, and plan completion points.

## Success Criteria

1. `validate-plan --criteria plan.json --task A1` executes all criteria for task A1 and exits 0 when all blocking criteria pass
2. A criterion with `expect_exit: 0` whose command exits 1 produces a FAIL line and causes exit 1
3. A criterion with `expect_output: "2 passed"` whose command stdout lacks that substring produces a FAIL line and causes exit 1
4. A criterion with `severity: "warning"` that fails produces a WARN line but does not affect the exit code
5. A command that exceeds its `timeout` is killed and reported as TIMEOUT (blocking failure)
6. Empty criteria arrays (no criteria defined) produce exit 0 with no output
7. The orchestrate and phase-dispatcher skills call the criteria runner at the documented integration points

## Architecture

### CLI Interface

```text
validate-plan --criteria <plan.json> --task <ID>
validate-plan --criteria <plan.json> --phase <LETTER>
validate-plan --criteria <plan.json> --plan
```

Scope is inferred from which target flag is present (`--task`, `--phase`, or `--plan`) — matching the existing `--update-status` pattern. No `--scope` flag needed. Each invocation runs only the criteria at that level — no cascading. The orchestration pipeline handles calling the right scope at the right time.

### Execution Semantics

For each criterion in the target's `success_criteria` array:

1. Run the `run` command via `timeout <seconds> bash -c "<command>"` (or `gtimeout` on macOS). Default timeout is 60s when the `timeout` field is omitted.
2. Capture stdout to a temp file for `expect_output` matching; let stderr pass through
3. If `expect_exit` is present: exact match on exit code (exit 124 from timeout = TIMEOUT)
4. If `expect_output` is present: substring match on captured stdout
5. When both are specified, both must pass. The schema validator ensures at least one of `expect_exit` or `expect_output` is present, so the case where neither exists is caught before execution.
6. `severity: "blocking"` (default) — failure causes overall exit 1
7. `severity: "warning"` — failure is reported but doesn't affect exit code

### Output Format

One line per criterion, human-readable:

```text
PASS  task A1 criteria[0]: "npm test" — exit=0 (expected 0), output contains "2 passed"
FAIL  task A1 criteria[1]: "npm run lint" — exit=1 (expected 0)
WARN  phase A criteria[0]: "npm run coverage" — exit=0, output missing "90%" [warning, non-blocking]
TIMEOUT task B1 criteria[0]: "npm test" — killed after 60s [blocking]
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All blocking criteria passed (or no criteria to run) |
| 1 | At least one blocking criterion failed |
| 2 | Usage error (bad arguments) |

### Working Directory

Commands execute in the caller's current directory (the repo root). The script does not cd — same contract as the existing modes.

### Timeout Portability

At script startup, check for `timeout` then `gtimeout`. If neither exists, warn to stderr and run commands without timeout enforcement. Acceptable for a dev-machine tool.

## Key Decisions

- **No cascading across scopes** — `--criteria --phase A` runs only phase A's criteria, not its tasks' criteria. The orchestration pipeline controls when each scope runs. This keeps the runner simple and the pipeline's control flow explicit.
- **Substring matching, not regex** — `expect_output` does substring matching (`grep -F`). Covers the common case ("2 passed", "ok"). Regex would add complexity for little benefit and was explicitly listed as a non-goal in the structured-plans design.
- **Human-readable output, not JSON** — The consumers are LLM agents (orchestrate, phase-dispatcher) that parse natural language. JSON adds parsing overhead without benefit. Exit code provides the machine-readable signal.
- **Temp file for stdout capture** — `output=$(bash -c "$cmd")` loses trailing newlines and has issues with null bytes. A temp file via `mktemp` preserves exact output and works with `grep -F` directly. Cleaned up with trap.
- **Extend validate-plan, not a standalone script** — The criteria live in plan.json, which validate-plan already parses. A separate script would duplicate the JSON extraction logic. The existing `do_schema` validates criteria structure; `do_criteria` executing them is a natural extension from static to dynamic validation. Inline in skills was rejected because it would duplicate execution/timeout/severity logic across multiple skill prompts.
- **timeout/gtimeout with bash -c** — Running `run` commands through `bash -c` ensures shell features (pipes, redirects, &&) work in criteria commands. The `timeout` wrapper handles the kill-after-N-seconds semantics.

## Non-Goals

- Regex support in `expect_output` (substring matching covers 90% of cases)
- Parallel criterion execution (criteria within a scope run sequentially — simpler, predictable)
- JSON output format (LLM consumers don't need it)
- CI integration (dev-machine tool; CI can call the script directly if needed later)

## Implementation Approach

**Single phase.** The runner, tests, and skill integration are tightly coupled. Shipping the runner without callers is dead code, and the skill changes are a few lines each.

### Script Changes (`scripts/validate-plan`)

Add a `do_criteria` function alongside existing `do_schema`, `do_render`, `do_update_status_*`. Parse `--criteria` flag in the existing argument parser. Reuse the existing `--task`, `--phase`, `--plan` target flags — rename `UPDATE_TARGET`/`UPDATE_ID` to `TARGET_TYPE`/`TARGET_ID` to reflect their now-general purpose. Detect timeout command at function entry.

### Skill Integration

**Phase dispatcher** (`skills/orchestrate/phase-dispatcher-prompt.md`): After step 9 (mark task complete), before step 10 (cross-phase handoffs), add: `validate-plan --criteria {PLAN_DIR}/plan.json --task {TASK_ID}`. If exit 1, report failure to orchestrate — do not proceed to next task.

**Orchestrate** (`skills/orchestrate/SKILL.md`): Two new calls:
1. After step 8 (append review changes to completion.md), before step 9 (emit phase summary): `validate-plan --criteria plan.json --phase {LETTER}`. If exit 1, pause and report to user.
2. After final phase, before marking plan Complete: `validate-plan --criteria plan.json --plan`. If exit 1, do not mark complete — report to user.

### Test Suite

New file `tests/validate-plan/test_criteria.sh`:
- Happy path: matching exit code → PASS
- Happy path: matching output substring → PASS
- Both checks: expect_exit + expect_output → PASS
- Exit mismatch → FAIL, exit 1
- Output mismatch → FAIL, exit 1
- Timeout → TIMEOUT, exit 1
- Warning severity → WARN, exit 0
- Empty criteria → exit 0, no output
- Mixed blocking pass + blocking fail → exit 1
- Usage errors (missing target flag, nonexistent task/phase) → exit 2

### Affected Files

| File | Change |
|------|--------|
| `scripts/validate-plan` | Add `do_criteria` function + CLI flags |
| `tests/validate-plan/test_criteria.sh` | New test suite |
| `skills/orchestrate/SKILL.md` | Add phase + plan criteria calls |
| `skills/orchestrate/phase-dispatcher-prompt.md` | Add task criteria call |
