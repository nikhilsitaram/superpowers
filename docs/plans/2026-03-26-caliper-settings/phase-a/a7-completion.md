# A7 Completion: Integrate merge_strategy into pr-merge

## Changes
- Updated `skills/pr-merge/SKILL.md` Step 2 merge strategy section
- Reordered to put auto-detected cases first (integration branches, phase PRs)
- Added `caliper-settings get merge_strategy` fallback for standard single-phase PRs
- Preserved existing behavior: integration branches use rebase, phase PRs use squash, explicit `--rebase` flag still works

## Verification
- `grep -q 'caliper-settings get merge_strategy' skills/pr-merge/SKILL.md` passes
