# A1: Rename PR skill directories and update their SKILL.md files

## Status: Complete

## Changes Made

### Directory Renames (git mv)
- `skills/create-pr` -> `skills/pr-create`
- `skills/review-pr` -> `skills/pr-review` (includes `reviewer-prompt.md`)
- `skills/merge-pr` -> `skills/pr-merge`

### pr-create/SKILL.md
- Updated frontmatter name/description to use `pr-create` and `/pr-create` trigger
- Updated all cross-references: `/review-pr` -> `/pr-review`, `/merge-pr` -> `/pr-merge`
- Updated integration section references

### pr-review/SKILL.md
- Updated frontmatter name/description to use `pr-review` and `/pr-review` trigger
- Inserted new Step 2 (Rebase onto Default Branch) between Setup and PR Review
- Renumbered all subsequent steps (old Step 2 -> Step 3, etc.)
- Updated internal step references (e.g., "use in Step 3" -> "use in Step 4")
- Added merge continuation AskUserQuestion to Step 7 (Merge PR / Not yet)
- Updated `--skip-review` argument to reference Step 3 (not Step 2)
- Updated all cross-references to use new pr-* names

### pr-merge/SKILL.md
- Updated frontmatter name/description to use `pr-merge` and `/pr-merge` trigger
- Removed Step 2 (Confirm Merge) entirely -- intent is confirmed by invocation path
- Merged branch protection check into new Step 2 (Merge)
- Renumbered: old Step 4 -> Step 3, old Step 5 -> Step 4
- Updated all cross-references to use new pr-* names

## Verification
- Zero matches for `create-pr|review-pr|merge-pr` across all three SKILL.md files
- Old directories confirmed deleted
- New directories confirmed present with all expected files
- `reviewer-prompt.md` preserved in `pr-review/`

## Commit
`e93c158` - refactor: rename PR skill directories to pr-* namespace and fix pipeline flow
