# A7 Completion: Update design skill doc to write integration_branch

## What Changed
Added a conditional `integration_branch` write instruction to step 11 (Route workflow) in `skills/design/SKILL.md`. For multi-phase plans, the design skill now writes `integration_branch` to plan.json via jq alongside the existing `workflow` and `execution_mode` fields.

## Verification
- `grep -q 'integration_branch' skills/design/SKILL.md` passes
- Only multi-phase plans trigger the write (single-phase plans unaffected)
- Placed in step 11 where plan.json overrides already happen — no new step needed

## Commit
`docs: add integration_branch write to design skill doc`
