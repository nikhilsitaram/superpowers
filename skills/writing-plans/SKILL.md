---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

## REQUIRED FIRST STEP: Initialize Task Tracking

Before any exploration or planning, call `TaskList` to check for existing tasks from a prior session. Then call `TaskCreate` for each major planning phase (explore codebase, write tasks, save plan, handoff).

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

**Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits

## Task Persistence

After saving the plan, write a `.tasks.json` file co-located with the plan document. This enables cross-session resume:

```json
{
  "planFile": "docs/plans/YYYY-MM-DD-feature-name.md",
  "createdAt": "ISO-8601 timestamp",
  "tasks": [
    {
      "id": 1,
      "title": "Task 1: Component Name",
      "status": "pending",
      "blockedBy": []
    },
    {
      "id": 2,
      "title": "Task 2: Next Component",
      "status": "pending",
      "blockedBy": [1]
    }
  ]
}
```

**File location:** Same directory as the plan, e.g. `docs/plans/.tasks.json`

When tasks are completed during execution, the executing skill updates this file so progress survives session boundaries.

## Execution Handoff

<HARD-GATE>
After saving the plan and `.tasks.json`, use `AskUserQuestion` to present the execution choice. Do NOT proceed to implementation without an explicit answer.
</HARD-GATE>

Use `AskUserQuestion` with these options:

**Question:** "Plan saved to `docs/plans/<filename>.md`. How would you like to execute?"

**Option 1: Subagent-Driven (this session)**
- Description: "Dispatch an Opus orchestrator subagent with fresh context to run subagent-driven-development. Fast iteration, two-stage review per task."

**Option 2: Parallel Session (separate)**
- Description: "Open a new session in the worktree directory and use executing-plans. Batch execution with human checkpoints between batches."

**After user answers:**

**If Subagent-Driven chosen:**

Dispatch a fresh **Opus** orchestrator subagent via the `Task` tool with `model: "opus"`. The orchestrator starts with zero prior context — all planning baggage stays in the parent. This is the automatic equivalent of `/clear` before execution.

The orchestrator prompt MUST include:
1. The full path to the plan file (e.g. `docs/plans/YYYY-MM-DD-feature.md`)
2. The working directory (worktree path)
3. Instruction to use `superpowers:subagent-driven-development` skill
4. Instruction to use `superpowers:finishing-a-development-branch` when complete

Example Task dispatch:
```
Task(
  description: "Execute implementation plan",
  model: "opus",
  prompt: "You are an orchestrator. Read the plan at docs/plans/<filename>.md and execute it using the superpowers:subagent-driven-development skill. When all tasks are complete, use superpowers:finishing-a-development-branch to wrap up. Working directory: <worktree-path>"
)
```

**If Parallel Session chosen:**
- Guide them to open new session in worktree
- **REQUIRED SUB-SKILL:** New session uses superpowers:executing-plans
