# Design: Permissions Fix (Issue #115)

## Problem

Permission prompts interrupt agent workflow during plan execution. 7 observed incidents across multiple sessions, caused by:

1. **Missing commands in safe-commands.txt** — `ln`, `dirname`, `basename`, `[`, `command` are standard Unix tools used by skills but not in the safe list
2. **`bash <script>` pattern** — agents run `bash scripts/validate-plan` or `bash tests/...sh`, but the hook only checks the command word `bash` (not in the safe list) and never examines the script argument
3. **Variable-as-command** — agents occasionally use `"$VALIDATE" --help` where the command word is a shell variable the hook can't resolve

These prompts block unattended orchestration and force user intervention for safe operations.

## Goal

Eliminate observed permission prompt interruptions without adding unsafe blanket approvals.

## Success Criteria

1. All 7 observed patterns (screenshots in issue #115) auto-approve without user intervention
2. `bash scripts/validate-plan` resolves to `validate-plan` (safe) via shell interpreter resolution
3. `bash "$VALIDATE"` and `"$VALIDATE" --help` deny with actionable feedback message
4. All existing 45 hook tests continue to pass
5. New tests cover: added commands, shell interpreter resolution, variable-as-command deny

## Architecture

### A. Safe Commands List Update

Add to `hooks/safe-commands.txt`:

| Command | Used by | Purpose |
|---------|---------|---------|
| `ln` | dependency-bootstrap.md | Symlink `.venv`/`node_modules` into worktrees |
| `dirname` | orchestrate SKILL.md | `$(dirname "$(realpath plan.json)")` |
| `basename` | test runner patterns | `$(basename $f)` |
| `[` | orchestrate/design | `[ -f "$FILE" ]` conditional (equivalent to `test`, already safe) |
| `command` | dependency-bootstrap.md | `command -v uv` tool detection |

### B. Shell Interpreter Resolution

In `extract_command_words_from_segment`, when the extracted command word is a known shell interpreter (`bash`, `sh`, `zsh`):

1. Skip flags: tokens matching `^-` (handles `-e`, `-x`, `-euo`, `--verbose`). Stop skipping at `--` (end-of-flags) or the first non-flag token.
2. Extract the first non-flag argument (the script path)
3. If it's a variable reference (`$VAR`, `"$VAR"`) → emit the variable token (will fail safe-list check, triggering deny path)
4. Otherwise → extract basename and emit that instead of the interpreter name
5. If no script argument exists (bare `bash`) → emit `bash` as the command word (fails safe-list check → deny)

This means `bash scripts/validate-plan --args` → `validate-plan` → safe → approved. `bash -e scripts/validate-plan` → `validate-plan` → safe. `bash "$f"` → `$f` → deny. Bare `bash` → deny.

The `bash -c 'command string'` pattern is not handled specially — `-c` is a flag, `'command string'` becomes the "script" token, its basename won't match the safe list, so it denies. This is safe-by-default and correct.

The existing basename extraction logic (`${word##*/}`) already handles path stripping — we just apply it one word deeper for shell interpreters.

### C. Variable-as-Command Deny with Feedback

In the main verification loop, when a command word starts with `$` (after stripping quotes):

- Set a flag indicating variable-as-command was detected
- After the loop, if the flag is set, output a PreToolUse deny with `permissionDecisionReason`: "Command word is a shell variable — the safe commands hook cannot verify safety. Use the literal path instead of variable indirection."

The deny response format: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`

The `permissionDecisionReason` is surfaced to the agent (not the user), enabling self-correction without user interruption.

This gives agents clear, actionable feedback. The agent rewrites with the literal path, which the hook can then verify normally. No user interruption needed.

### D. Dead Code Check

Verify no orphaned permission-prompt-forwarding code remains from the pre-agent-teams supervision loop. Preliminary analysis: the old supervision loop was a design doc + plan, replaced entirely by agent teams (PR #123). No runtime code to remove.

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Shell interpreter resolution instead of adding `bash` to safe list | `bash` is an arbitrary execution vector — resolving the script basename is targeted and safe |
| Deny with feedback for variable-as-command | Agent gets clear error and self-corrects; no user interruption needed |
| Add `[` as safe | Read-only conditional check, equivalent to `test` (already in safe list) |
| Don't add `bash`/`sh`/`zsh` to safe list | They remain unresolvable as standalone — only approved when their script argument resolves to a safe basename |

## Non-Goals

- Resolving shell variables at hook time (fragile, incomplete)
- Adding package managers (`pip`, `yarn`, `pnpm`, `cargo`, `go`) to safe list
- Changing skill templates to avoid `bash` prefix (agents will generate the pattern regardless)
- Modifying Claude Code's built-in security checks (our PermissionRequest hook handles the fallout)

## Implementation Approach

Single phase — all changes in `hooks/` and `tests/hooks/`:

| Task | Description | Files |
|------|-------------|-------|
| T1 | Add `ln`, `dirname`, `basename`, `[`, `command` to safe list | `hooks/safe-commands.txt` |
| T2 | Shell interpreter resolution in `extract_command_words_from_segment` | `hooks/pretooluse-safe-commands.sh` |
| T3 | Variable-as-command deny with feedback message | `hooks/pretooluse-safe-commands.sh` |
| T4 | Tests for new safe commands (5 commands) | `tests/hooks/test_safe_commands.sh` |
| T5 | Tests for shell interpreter resolution (safe script, variable script, no-arg) | `tests/hooks/test_safe_commands.sh` |
| T6 | Tests for variable-as-command deny (bare `$VAR`, quoted `"$VAR"`, `${VAR}`) | `tests/hooks/test_safe_commands.sh` |
| T7 | Verify no dead permission-forwarding code in orchestrate skills | Read-only check |
