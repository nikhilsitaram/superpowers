# Design: /caliper-settings — User-Configurable Defaults

## Problem

Every configurable behavior in claude-caliper resets each invocation. Users must pass `--skip-tests` every time, re-specify their preferred review mode, or re-select workflow preferences. There's no persistent layer between shipped defaults and per-invocation CLI flags.

This means:
- Repeated flag typing for common preferences
- No way to set "always use automated review" without repeating `--automated`
- Workflow preferences (pr-create vs pr-merge) must be re-selected in every design session

## Goal

A `/caliper-settings` skill backed by a bash script that reads/writes persistent user preferences to `${CLAUDE_PLUGIN_DATA}/settings.json`, with 3-tier precedence: CLI flag > user setting > shipped default.

## Success Criteria

1. Running `/caliper-settings` displays all available settings with current values, defaults, and descriptions
2. Running `/caliper-settings set skip_tests true` persists across sessions — a new session sees the value
3. Running `/caliper-settings reset skip_tests` restores the shipped default
4. Setting a value with wrong type (e.g., `set skip_tests banana`) produces a clear error message naming the expected type
5. Each consuming skill respects its settings when no CLI flag overrides them:
   - pr-create skips tests when `skip_tests` is `true` and no `--skip-tests` flag
   - pr-review uses automated mode when `review_mode` is `automated` and no `--automated` flag
   - design pre-selects workflow and execution_mode from settings in its AskUserQuestion prompt
   - orchestrate reads `workflow`, `execution_mode`, and `review_wait_minutes` from settings
   - pr-merge uses configured `merge_strategy` when no explicit strategy flag
   - review skills (design-review, plan-review, implementation-review) use `re_review_threshold`
   - pr-review uses `skip_review` and `bot_poll_timeout_minutes`
6. CLI flags always override settings — `--skip-tests=false` overrides a `true` setting

## Architecture

### Components

```text
defaults.json                          # Structured schema (repo root)
scripts/caliper-settings               # Bash script — get/set/reset/list
skills/caliper-settings/SKILL.md       # Thin skill wrapping the script
```

### Data Flow

```text
defaults.json (CLAUDE_PLUGIN_ROOT)  →  merge  →  settings.json (CLAUDE_PLUGIN_DATA)
        tier 3 (lowest)                              tier 2

CLI flags (per-invocation)  →  override  →  final value
        tier 1 (highest)
```

The script handles tiers 2-3 (merge user settings over defaults). Tier 1 (CLI flag override) stays in each consuming skill — the skill checks its flags first, only calls `scripts/caliper-settings get <key>` when no flag was passed.

### Storage

- **Defaults:** `${CLAUDE_PLUGIN_ROOT}/defaults.json` — shipped with the plugin, read-only at runtime
- **User overrides:** `${CLAUDE_PLUGIN_DATA}/settings.json` — persistent across sessions and plugin updates
- **Merge strategy:** Flat top-level merge. User values override defaults for matching keys. Missing keys fall back to defaults.

### Environment Variables

- `${CLAUDE_PLUGIN_ROOT}` — absolute path to plugin installation directory (set by Claude Code plugin loader)
- `${CLAUDE_PLUGIN_DATA}` — persistent data directory for plugin state (set by Claude Code plugin loader, survives updates)

Both are substituted inline in skill content and exported to hook/script subprocesses.

## Key Decisions

### Structured defaults.json schema

Each setting has type metadata for validation and display:

```json
{
  "skip_tests": {
    "type": "bool",
    "default": false,
    "description": "Skip test suite before committing",
    "used_by": ["pr-create"]
  },
  "review_mode": {
    "type": "enum",
    "values": ["automated", "deliberate"],
    "default": "deliberate",
    "description": "Default PR review mode",
    "used_by": ["pr-review"]
  }
}
```

Types supported: `bool`, `enum` (with `values` array), `int`.

### Script interface

```bash
caliper-settings get <key>           # Prints merged value to stdout. Exit 1 if unknown key.
caliper-settings set <key> <value>   # Validates type, writes to settings.json. Exit 1 on validation error.
caliper-settings reset [key]         # Removes key from settings.json (or all keys if no arg).
caliper-settings list                # Prints table: key, current value, default, description.
```

### Consumer integration pattern

Each consuming skill adds a one-liner fallback per setting. Example for pr-create:

```text
If `--skip-tests` was not passed, run `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get skip_tests`.
If it returns `true`, skip the test step.
```

This keeps SKILL.md changes minimal — one sentence per setting, no boilerplate.

### Why not userConfig?

The `userConfig` field in plugin.json prompts at install-time and stores in Claude Code's `pluginConfigs` in settings.json. It's designed for secrets and one-time setup (API keys, endpoints). `/caliper-settings` is for workflow preferences that users tweak frequently — different UX, different storage, complementary purposes.

## Settings Catalog

### PR Workflow

| Key | Type | Default | Used by | Description |
|-----|------|---------|---------|-------------|
| `skip_tests` | bool | `false` | pr-create | Skip test suite before committing |
| `review_mode` | enum: `automated`, `deliberate` | `deliberate` | pr-review | Default PR review mode |
| `skip_review` | bool | `false` | pr-review | Skip fresh-eyes subagent review dispatch |
| `merge_strategy` | enum: `squash`, `rebase` | `squash` | pr-merge | Default merge strategy for PRs |

### Orchestration

| Key | Type | Default | Used by | Description |
|-----|------|---------|---------|-------------|
| `workflow` | enum: `pr-create`, `pr-merge`, `plan-only` | `pr-create` | design, orchestrate | Default post-orchestration workflow |
| `execution_mode` | enum: `subagents`, `agent-teams` | `subagents` | design, orchestrate | Default execution mode for plan dispatch |
| `review_wait_minutes` | int | `10` | orchestrate, pr-review | Minutes to wait for external review bot comments |

### Review

| Key | Type | Default | Used by | Description |
|-----|------|---------|---------|-------------|
| `re_review_threshold` | int | `5` | design-review, plan-review, implementation-review | Issue count above which reviewer is re-dispatched after fixes |
| `bot_poll_timeout_minutes` | int | `10` | pr-review | Timeout for polling external review bot comments |

## Non-Goals

- Per-project settings (`.claude-caliper.json` in project root — future enhancement)
- Settings validation beyond type checking (no range checks, no cross-setting dependencies)
- `userConfig` install-time prompts (complementary mechanism, not a replacement)
- Migration from CLI flags to settings-only (flags always remain as overrides)

## Implementation Approach

Single phase. Infrastructure tasks first (sequential), then consumer integrations (parallel):

**Sequential foundation (tasks 1-4):**
1. `defaults.json` with all 9 settings
2. `scripts/caliper-settings` bash script
3. Test suite for the script
4. `skills/caliper-settings/SKILL.md`

**Parallel consumer integrations (tasks 5-10, all depend on task 2):**
5. pr-create: `skip_tests`
6. pr-review: `review_mode`, `skip_review`, `bot_poll_timeout_minutes`
7. pr-merge: `merge_strategy`
8. design: `workflow`, `execution_mode`
9. orchestrate: `workflow`, `execution_mode`, `review_wait_minutes`
10. Review skills: `re_review_threshold` in design-review, plan-review, implementation-review

**Wrap-up:**
11. Version bump in marketplace.json
