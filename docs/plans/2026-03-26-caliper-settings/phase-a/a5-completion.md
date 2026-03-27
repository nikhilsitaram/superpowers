# A5 Completion: Integrate skip_tests into pr-create

## What Changed
- Added caliper-settings fallback to Step 4 (Run Tests) in `skills/pr-create/SKILL.md`
- CLI flags (`--skip-tests`/`-T`) remain tier 1 and always override
- When no flag is passed, the skill now checks `caliper-settings get skip_tests` and skips tests if it returns `true`

## Verification
- `grep -q 'caliper-settings get skip_tests' skills/pr-create/SKILL.md` passes
