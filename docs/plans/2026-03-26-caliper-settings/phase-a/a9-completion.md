# A9 Completion Notes

## Changes
- **Review Loop Protocol**: Replaced hardcoded threshold of 5 with `caliper-settings get re_review_threshold` — orchestrate now reads the user's configured threshold at runtime
- **pr-merge workflow routing**: Added `caliper-settings get review_wait_minutes` read before the review poll step, replacing the inline reference to the setting name
- **Setup section**: Added clarifying note that `workflow` and `execution_mode` are read from plan.json (set by design skill), not from caliper-settings at runtime — avoids two sources of truth

## Verification
- `grep -q 'caliper-settings get re_review_threshold'` — PASS
- `grep -q 'caliper-settings get review_wait_minutes'` — PASS
