# Safe Commands Hook + Auto Mode Permission Migration

## Problem

All five subagent prompt files use `bypassPermissions`, which runs every command without oversight — no prompt injection safeguards, no visibility into what commands are executed, and no mechanism to build a curated allowlist over time. Meanwhile, users who run the plugin in safer permission modes (like `acceptEdits`) get friction from perfectly safe commands (e.g., `stat`, `brew`) that aren't pre-approved.

There's no middle ground: either everything is auto-approved or common dev commands trigger manual prompts.

## Goal

Layer three permission mechanisms — auto mode, a safe commands hook, and a learning loop — so subagents run with oversight while common dev commands execute without friction, and the safe list grows over time based on actual usage.

## Success Criteria

1. All five subagent prompt files use `permissionMode: auto` instead of `bypassPermissions`
2. A PreToolUse hook auto-approves Bash commands matching prefixes in `hooks/safe-commands.txt` before auto mode evaluates them
3. Commands not in the safe list are logged to a temp file during execution
4. Phase dispatcher checks the log after each task (post-implementer + post-reviewer) and asks the user via AskUserQuestion whether to add flagged commands to `safe-commands.txt`
5. User-approved additions take effect immediately — subsequent tasks in the same phase benefit
6. Existing pipeline behavior (TDD, review gates, commit workflow) is unchanged

## Architecture

### Layer 1: Auto Mode (base permission mode)

All subagent prompt files switch from `mode: "bypassPermissions"` to `mode: "auto"`. Auto mode lets Claude evaluate each permission request with built-in prompt injection safeguards. Edits, reads, and safe-looking commands are approved automatically; risky operations are flagged or blocked.

**Files changed:**
- `skills/orchestrate/implementer-prompt.md`
- `skills/orchestrate/phase-dispatcher-prompt.md`
- `skills/orchestrate/task-reviewer-prompt.md`
- `skills/implementation-review/reviewer-prompt.md`
- `skills/merge-pr/reviewer-prompt.md`

### Layer 2: Safe Commands Hook (deterministic pre-approval)

A PreToolUse hook intercepts every Bash command before auto mode evaluates it. If the command matches a prefix in `hooks/safe-commands.txt`, the hook returns `permissionDecision: allow` — zero token cost, instant approval. If no match, the hook logs the command to a temp file and falls through to auto mode.

```text
hooks/
  safe-commands.txt              # One prefix per line, version-controlled
  pretooluse-safe-commands.sh    # PreToolUse hook script
```

**safe-commands.txt** ships with ~25-30 common dev workflow prefixes:

```text
awk
bash
cat
cd
chmod
cp
curl
diff
du
echo
env
file
find
git
grep
head
jq
ls
mkdir
mv
node
npm
npx
pytest
python
python3
pwd
readlink
realpath
rm
ruff
sed
sort
stat
tail
test
touch
uv
uvx
wc
which
xargs
```

**Hook flow:**

```text
Bash command arrives
  → Hook parses command words (split on &&, ;, |, $())
  → Check each command word against safe-commands.txt prefixes
  → ALL match → return { permissionDecision: "allow" }
  → ANY non-match → log non-matching commands to $TMPDIR/claude-safe-cmds-nonmatch.log
                   → return nothing (fall through to auto mode)
```

### Layer 3: Learning Loop (per-task surfacing)

After each task's implementer + reviewer cycle, the phase dispatcher reads the non-safe commands log. If entries exist, it asks the user via AskUserQuestion whether to add them to `safe-commands.txt`. Approved additions are appended immediately — subsequent tasks benefit.

**Phase dispatcher additions:**
- After task reviewer completes, before starting next task:
  1. Read `$TMPDIR/claude-safe-cmds-nonmatch.log`
  2. If non-empty, deduplicate and present via AskUserQuestion (multiSelect)
  3. User selects which to add → append to `hooks/safe-commands.txt`
  4. Truncate the log for the next task

## Key Decisions

### Auto mode as base instead of acceptEdits
Auto mode provides prompt injection safeguards that `acceptEdits` lacks, and handles the long tail of commands the safe list doesn't cover. The safe commands hook reduces auto mode's per-evaluation token overhead for common commands.

### Phase dispatcher owns per-task user communication
The orchestrator only sees phase results. Per-task granularity requires the dispatcher (a subagent) to call AskUserQuestion directly. This is architecturally unusual — subagents typically don't communicate with users — but the user explicitly chose this pattern for faster feedback.

### Deterministic safe list alongside auto mode
Auto mode's judgments are probabilistic. The safe list provides a deterministic fast-path for known commands — predictable, zero token cost, and version-controlled so teams share the same baseline.

### Dev workflow commands only
The safe list ships with ~40 common dev prefixes. Domain-specific tools (MCP servers, Dataiku, Tableau) are left to users' personal hooks. This keeps the plugin generic.

### Hook distribution gap
Hook scripts ship with the plugin (files in `hooks/`), but `settings.json` hook config doesn't auto-install via the plugin system. Users must manually wire the hook. The setup path will be documented; a setup skill may follow later.

## Non-Goals

- MCP tool auto-approval (users extend with personal hooks)
- Automatic additions without user confirmation
- Replacing users' personal safe commands hooks
- Solving the plugin hook distribution gap in this PR (document-only for now)

## Implementation Approach

**Single phase** — no dependency layers. All changes are tightly coupled (permission mode + hook + dispatcher integration).

### Tasks

1. **Create hook infrastructure** — `hooks/safe-commands.txt` (prefixes) + `hooks/pretooluse-safe-commands.sh` (PreToolUse script that reads the list, auto-approves matches, logs non-matches)
2. **Switch permission modes** — Update all 5 prompt files from `bypassPermissions` to `auto`
3. **Update phase dispatcher** — Add per-task non-safe command check after task reviewer: read log, AskUserQuestion (multiSelect) for additions, append approved commands, truncate log
4. **Update orchestrate SKILL.md** — Document the hook requirement and safe commands workflow in the orchestrate skill instructions
5. **Test hook** — Shell tests for the hook: matching commands, non-matching commands, compound commands, log file behavior
6. **Documentation** — Setup instructions for wiring the hook into settings.json
