---
status: In Development
---

# Replace unrestricted bypassPermissions with auto mode + a deterministic safe commands hook + a learning loop so subagents run with prompt injection safeguards while common dev commands execute without friction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Replace unrestricted bypassPermissions with auto mode + a deterministic safe commands hook + a learning loop so subagents run with prompt injection safeguards while common dev commands execute without friction
**Architecture:** Three layers: (1) all 5 subagent prompt files switch from bypassPermissions to auto mode for built-in prompt injection safeguards, (2) a PreToolUse hook reads hooks/safe-commands.txt prefixes and instantly approves matching Bash commands (zero token cost), logging non-matches to a temp file for auto mode to evaluate, (3) the phase dispatcher reads the non-match log after each task and asks the user whether to add new commands to the safe list.
**Tech Stack:** Bash, jq, Claude Code hooks API (PreToolUse), Claude Code auto mode

---

## Phase A — Hook infrastructure, permission migration, and learning loop
**Status:** Not Started | **Rationale:** Single phase because the three layers are tightly coupled: auto mode without the hook causes friction on safe commands, the hook without auto mode leaves non-safe commands unprotected, and the learning loop requires both to be in place. No meaningful verification gate exists between them.

- [x] A1: Write test suite for the PreToolUse safe commands hook — *test_safe_commands.sh has 15 tests for: single safe command approved, single unsafe command logs and falls through, compound command (&&) all safe approved, compound command with one unsafe falls through, pipe chain all safe approved, pipe with unsafe falls through, subshell $() extraction, quoted strings not split, path basename extraction (./node_modules/.bin/jest -> jest), empty input handled, variable assignment VAR=$(cmd) extracts cmd, semicolon separator treated like &&, 20-command-word limit enforced, log file written with non-matching commands. All tests FAIL because hook script does not exist.*
- [x] A2: Create safe-commands.txt and PreToolUse hook script — *safe-commands.txt contains ~35 dev workflow prefixes from design doc. Hook script reads stdin JSON, extracts Bash command, splits on &&/;/|, extracts command words from $() and VAR=, checks basenames against safe-commands.txt, returns {permissionDecision: allow} when all match, logs non-matches to $TMPDIR/claude-safe-cmds-nonmatch.log and exits silently when any don't match. All A1 tests pass.*
- [x] A3: Register PreToolUse hook in hooks.json — *hooks.json has a PreToolUse entry with matcher 'Bash' pointing to ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-safe-commands.sh. Existing PostToolUse and PermissionRequest entries unchanged. All hook tests still pass.*
- [x] A4: Switch all 5 subagent prompt files from bypassPermissions to auto — *All 5 prompt files have mode: "auto" instead of mode: "bypassPermissions". No other content changes. grep finds zero occurrences of bypassPermissions in skills/.*
- [x] A5: Add learning loop to phase dispatcher prompt — *Phase dispatcher prompt has a new section in 'Your Process' after step 4 (update plan doc) that: reads $TMPDIR/claude-safe-cmds-nonmatch.log, deduplicates entries, presents them via AskUserQuestion for user to approve, appends approved commands to hooks/safe-commands.txt, truncates the log. Instructions are clear enough for a fresh dispatcher subagent to execute without clarification.*
- [x] A6: Update orchestrate SKILL.md with hook documentation — *Orchestrate SKILL.md has a brief section explaining: subagents run in auto mode, the PreToolUse hook auto-approves commands matching safe-commands.txt, non-matching commands are logged and surfaced per-task via the learning loop. Section is concise (under 100 words) to respect the 1000-word skill cap.*
- [x] A7: Write setup documentation for hook wiring — *docs/safe-commands-setup.md explains how to wire the PreToolUse hook in the user's settings.json, including: the hook config JSON snippet, where settings.json lives (~/.claude/settings.json), that the hook coexists with personal hooks, and a note that plugin-installed hooks wire automatically but settings.json hooks require manual setup.*
- [x] A8: Bump version in marketplace.json — *All three plugin versions bumped (version number incremented from whatever the current value is at implementation time). Single consistent version across all three plugins. All hook test suites pass (test_safe_commands.sh, test_post_tool_use.sh, test_permission_request.sh), confirming existing pipeline behavior unchanged (SC5).*
