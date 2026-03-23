---
status: Not Yet Started
---

# Add polling-based external review gate after each phase PR and conditional merge strategy for final PR Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add polling-based external review gate after each phase PR and conditional merge strategy for final PR
**Architecture:** Insert check-polling and review-pr invocation into orchestrate SKILL.md between phase PR creation and merge. Add conditional merge strategy (rebase for multi-phase, squash for single-phase) to merge-pr SKILL.md for integration branch PRs. Add review_wait_minutes as optional plan.json field in draft-plan SKILL.md.
**Tech Stack:** Markdown skill files, gh CLI (pr checks, pr merge), jq for plan.json field reads

---

## Phase A — Review gate and merge strategy
**Status:** Not Started | **Rationale:** Single phase because all three file edits are tightly coupled: orchestrate references review_wait_minutes (documented by draft-plan) and the merge strategy (implemented by merge-pr). No meaningful verification gate between them — they form one coherent behavior change.

- [ ] A1: Add poll-review-merge sequence to orchestrate SKILL.md — *Orchestrate SKILL.md steps 14-16 replaced with expanded steps 14-18: create phase PR, poll checks (60s interval, review_wait_minutes cap from plan.json defaulting to 10), invoke review-pr, merge + update integration worktree, clean up. Wave loop summary updated to include poll+review-pr. After All Phases section updated: final PR gets poll + review-pr before merge-pr, merge-pr invoked with --rebase for multi-phase plans. Word count stays at or under 1000.*
- [ ] A2: Add conditional merge strategy to merge-pr SKILL.md — *Merge-pr SKILL.md Step 3 merge command uses conditional strategy: --rebase when plan.json has >1 phase (preserves per-phase commit history), --squash otherwise. Detection: read plan.json from the plan directory if available, count phases. Phase PRs (base is integrate/*) always use --squash (unchanged). Only the final PR (integrate/* to main) uses the conditional. Word count stays at or under 1000.*
- [ ] A3: Add review_wait_minutes to draft-plan SKILL.md schema docs — *Draft-plan SKILL.md plan.json schema example includes review_wait_minutes as optional integer field (default 10). The Optional paragraph below the schema mentions it alongside success_criteria and workflow. Word count stays at or under 1000.*
- [ ] A4: Bump version in marketplace.json — *All three plugin versions in marketplace.json bumped to 1.11.0 (from 1.10.0). Single consistent version across all three plugins.*
- [ ] A5: Run skill-eval for orchestrate and merge-pr — *Skill evals run for orchestrate (new evals.json with 2-3 scenarios covering phase PR review gate behavior) and merge-pr (existing or new evals.json with scenarios covering conditional merge strategy). Benchmark results show after variant pass rate >= before variant. Any regressions investigated and fixed before proceeding.*
