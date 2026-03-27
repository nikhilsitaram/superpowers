# A10 Completion: Integrate re_review_threshold into Review Skills

## Changes Made

Replaced hardcoded "more than 5" re-review threshold in all three review skills with a `caliper-settings get re_review_threshold` lookup (default: 5):

- `skills/design-review/SKILL.md` — Re-review gate line
- `skills/plan-review/SKILL.md` — Re-review gate line
- `skills/implementation-review/SKILL.md` — Re-Review Gate section

## Verification

All three files contain `caliper-settings get re_review_threshold` — confirmed via grep.
