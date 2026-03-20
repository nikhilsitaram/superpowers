# Phase A Completion Notes

**Date:** 2026-03-20
**Summary:** Added a criteria runner to the `validate-plan` script. A1 wrote the test suite (test_criteria.sh, 12 test cases, all RED). A2 implemented `do_criteria()` and `--criteria` CLI mode in `scripts/validate-plan`, supporting task/phase/plan scope with PASS/FAIL/WARN/TIMEOUT reporting and correct exit codes. A3 integrated the criteria runner into both the phase dispatcher prompt (task-scope, blocking on exit 1) and the orchestrate skill (phase-scope after implementation review, plan-scope before final status update).
**Deviations:** None — plan followed exactly.
