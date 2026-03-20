# Auto-Enable acceptEdits After Design Approval

## Problem

When using the design skill in default permission mode, every Edit/Write operation after design approval requires manual user confirmation. This creates unnecessary friction — the user already approved the design, signaling intent to proceed with file creation. The repeated permission dialogs slow down the workflow (design doc writing, design-review, draft-plan, orchestration) without adding safety value.

## Goal

Automatically switch the Claude Code session to acceptEdits mode when the user approves a design, so all subsequent file operations proceed without permission dialogs.

## Success Criteria

1. A user in default permission mode who approves a design via AskUserQuestion sees no Edit/Write permission dialogs for the remainder of the session
2. Without a `.design-approved` sentinel file, Edit/Write permission dialogs behave normally (no false positives)
3. The hooks ship with the plugin — no manual configuration required after plugin installation
4. The design skill's collaborative dialogue phase (steps 1-6) works identically in both default and acceptEdits modes (no edits needed during dialogue)

## Architecture

Two-hook chain triggered by design approval:

```
AskUserQuestion (design approval)
    ↓ PostToolUse hook
Creates docs/plans/YYYY-MM-DD-topic/.design-approved sentinel
    ↓ Skill calls Write (design doc)
    ↓ PermissionRequest hook
Finds sentinel → allows Write + sets acceptEdits mode (session)
    ↓
All subsequent Edit/Write: auto-approved
```

### Hook 1: PostToolUse on AskUserQuestion

**Script:** `hooks/post-tool-use-design-approval.sh`

**Trigger:** `tool_input.metadata.source == "design-approval"`

**Logic:**
1. Read stdin JSON, extract `tool_name`, `metadata.source`, user response, and question text
2. Bail if `tool_name != "AskUserQuestion"` or `source != "design-approval"`
3. Bail if user response indicates rejection (e.g., "Needs changes")
4. Parse plan directory path from question text (format: `Plan dir: docs/plans/YYYY-MM-DD-topic`)
5. `mkdir -p` the plan directory in CWD
6. `touch .design-approved` inside the plan directory

**Output:** None (hook creates files as side effect, no decision to return).

### Hook 2: PermissionRequest on Edit|Write

**Script:** `hooks/permission-request-accept-edits.sh`

**Trigger:** Permission dialog about to show for Edit or Write tool.

**Logic:**
1. Read stdin JSON, extract `cwd`
2. `find "$cwd/docs/plans" -maxdepth 2 -name .design-approved` (shallow, fast)
3. If found: return JSON with `behavior: "allow"` and `updatedPermissions: [{ type: "setMode", mode: "acceptEdits", destination: "session" }]`
4. If not found: `exit 0` (passthrough, normal permission dialog shows)

**Output:** Structured JSON decision when sentinel found; no output otherwise.

### Design Skill Changes

**Reordered checklist** (worktree moved before approval gate):

1. Explore context
2. Challenge assumptions
3. Ask clarifying questions
4. Propose 2-3 approaches
5. Present design (section by section)
6. Set up worktree (moved from step 7 to step 6)
7. Design approval AskUserQuestion — includes `metadata: { source: "design-approval" }` and plan dir in question text
8. Write design doc (auto-approved via hooks)
9. Dispatch design-review subagent
10. Dispatch draft-plan subagent

**AskUserQuestion format:**
```json
{
  "questions": [{
    "question": "Design approved? Plan dir: docs/plans/2026-03-20-topic",
    "header": "Approval",
    "options": [
      { "label": "Approved", "description": "Write design doc and proceed to review" },
      { "label": "Needs changes", "description": "Continue iterating on the design" }
    ],
    "multiSelect": false
  }],
  "metadata": { "source": "design-approval" }
}
```

### Plugin Manifest Changes

Add `hooks` field to plugin declarations in `marketplace.json` (claude-caliper and claude-caliper-workflow packages, which include the design skill):

```json
"hooks": {
  "PostToolUse": [{
    "matcher": "AskUserQuestion",
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use-design-approval.sh"
    }]
  }],
  "PermissionRequest": [{
    "matcher": "Edit|Write",
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/permission-request-accept-edits.sh"
    }]
  }]
}
```

## Key Decisions

1. **metadata.source for identification** — structured field, not fragile text matching. Doesn't break if question wording changes. The `source` field is designed for this purpose.

2. **Plan dir in question text** — the skill embeds the directory path naturally in the question ("Plan dir: docs/plans/..."). Human-readable for the user, machine-parseable for the hook via prefix match.

3. **Sentinel as artifact** — `.design-approved` is not cleaned up. It's removed when the worktree is cleaned up after ship/merge. Doubles as an audit trail of design approval.

4. **Session-scoped mode change** — `destination: "session"` means acceptEdits resets on next session. No permanent settings modification.

5. **Worktree before approval** — worktree must exist before the AskUserQuestion so the PostToolUse hook can create files in it. The worktree is lightweight and safe to create before final approval.

## Non-Goals

- No Bash command auto-approval (only Edit|Write)
- No sentinel cleanup mechanism
- No retroactive activation for existing sessions
- No plan mode integration (native plan mode UX conflicts with design skill's collaborative flow)

## Implementation Approach

Single phase — small surface area (2 scripts, 2 file edits):

**Phase A: Hook infrastructure + skill update**
1. Create `hooks/post-tool-use-design-approval.sh`
2. Create `hooks/permission-request-accept-edits.sh`
3. Update `skills/design/SKILL.md` (reorder steps, add metadata/plan-dir to approval question)
4. Update `.claude-plugin/marketplace.json` (add hooks to plugin declarations)
5. Version bump
