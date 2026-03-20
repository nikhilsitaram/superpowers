---
status: Complete
---

# Add criteria runner to validate-plan Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add criteria runner to validate-plan
**Architecture:** Extend scripts/validate-plan with a do_criteria function that executes success_criteria entries from plan.json, reports pass/fail per criterion with severity awareness, and integrates into the orchestration pipeline at task, phase, and plan completion points.
**Tech Stack:** Bash, jq, timeout/gtimeout, grep -F

---

## Phase A — Criteria Runner and Integration
**Status:** Complete (2026-03-20) | **Rationale:** Single phase because the runner, tests, and skill integration are tightly coupled — shipping the runner without callers is dead code, and the skill changes are a few lines each.

- [x] A1: Write criteria runner test suite — *test_criteria.sh has 12 test cases covering all design scenarios (task/phase/plan scopes, PASS/FAIL/WARN/TIMEOUT, empty criteria, mixed results, usage errors); every test fails because the --criteria flag is not yet implemented*
- [x] A2: Implement do_criteria function and CLI wiring — *All criteria tests pass, all existing test suites still pass, validate-plan --criteria executes criteria and reports PASS/FAIL/WARN/TIMEOUT with correct exit codes*
- [x] A3: Integrate criteria runner into orchestration skills — *Phase dispatcher calls criteria runner after marking task complete; orchestrate calls criteria runner after phase completion and before marking plan complete; integration points match design doc specification*
