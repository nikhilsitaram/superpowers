# A2: Update cross-references in non-PR skills — Completion

## Summary

Renamed all `create-pr`, `review-pr`, and `merge-pr` references to `pr-create`, `pr-review`, and `pr-merge` across four non-PR skill files.

## Files Changed

- `skills/design/SKILL.md` — Updated step 7 workflow options (3 references) and step 12 enum mapping (2 references)
- `skills/orchestrate/SKILL.md` — Updated single-phase routing (2 references), multi-phase routing (2 references), continuity note (1 reference), integration line (3 references)
- `skills/draft-plan/SKILL.md` — Updated plan.json example workflow value (1 reference) and optional field documentation (4 references)
- `skills/implementation-review/SKILL.md` — Updated "Leads to" integration reference (1 reference)

## Verification

`grep -rE '\bcreate-pr\b|\breview-pr\b|\bmerge-pr\b'` across all four files returns zero matches.

## Issues

None.
