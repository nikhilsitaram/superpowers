---
status: Not Yet Started
---

# Make caliper-settings self-locating, move plan artifacts to gitignored .claude/claude-caliper/, rename test scripts to caliper-test_* prefix, and add glob matching to safe-commands hook. Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Make caliper-settings self-locating, move plan artifacts to gitignored .claude/claude-caliper/, rename test scripts to caliper-test_* prefix, and add glob matching to safe-commands hook.
**Architecture:** Phase A builds infrastructure: caliper-settings self-location + source subcommand, safe-commands prefix/glob matching, and test script renames. Phase B updates all consumer skills and hooks to use the new plan path (.claude/claude-caliper/), adds settings-aware prompting to design skill, moves the schema reference doc, and deletes docs/plans/.
**Tech Stack:** Bash scripts, jq, Claude Code plugin hooks, SKILL.md files

---

## Phase A — Infrastructure
**Status:** Not Started | **Rationale:** Phase B consumers depend on the source subcommand, renamed test files, and prefix matching built here.

- [ ] A1: caliper-settings self-location and source subcommand — *caliper-settings resolves CLAUDE_PLUGIN_ROOT from dirname when env var not set, source subcommand returns 'default' or 'user' correctly, existing tests pass under new name*
- [ ] A2: Safe-commands prefix/glob matching — *Entries ending with * use prefix matching, exact-match entries unchanged, new test cases validate prefix matching, all existing safe-commands tests pass under new name*
- [ ] A3: Rename all test scripts and update safe-commands.txt — *All 22 test scripts renamed from test_* to caliper-test_*, old test_* files deleted, safe-commands.txt has single caliper-test_* glob entry instead of 18 individual entries, all renamed tests pass*

## Phase B — Consumers and cleanup
**Status:** Not Started | **Rationale:** Updates all skill files and hooks to use the new infrastructure (source subcommand, new plan path, renamed tests). Must run after Phase A because skills reference the source subcommand and hooks reference renamed test files.

- [ ] B1: Design skill: new plan path and settings-aware prompting — *Design skill creates plan dir under .claude/claude-caliper/, uses caliper-settings source to skip prompts when user has overrides, no git add/commit of plan files, all docs/plans/ references replaced*
- [ ] B2: Draft-plan skill: new plan path and move schema reference — *Draft-plan saves to .claude/claude-caliper/, no git commit of plan files, schema reference doc copied to skills/draft-plan/schema-reference.md with updated See reference, all docs/plans/ references replaced*
- [ ] B3: Design-review and plan-review skills: new plan path references — *All docs/plans/ path references in design-review and plan-review replaced with .claude/claude-caliper/*
- [ ] B4: Sentinel hook: update search path — *Sentinel hook searches .claude/claude-caliper/ instead of docs/plans/, test updated to create sentinels under new path, all tests pass*
- [ ] B5: Delete docs/plans/ and update CLAUDE.md — *docs/plans/ directory deleted from tracked files via git rm -r, CLAUDE.md repo structure section updated to reference .claude/claude-caliper/ for plan artifacts, version bumped in marketplace.json*
