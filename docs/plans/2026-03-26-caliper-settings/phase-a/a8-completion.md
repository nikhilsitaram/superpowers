# A8 Completion: Integrate workflow, execution_mode, re_review_threshold into design

## Changes
- **Step 7 Q1 (Workflow):** Replaced hardcoded `(default)` on "Create PR" with a dynamic lookup via `caliper-settings get workflow`. The matching option gets marked as default.
- **Step 7 Q2 (Exec mode):** Added `caliper-settings get execution_mode` lookup. Complexity-based recommendations still override the setting; if they differ, both are noted in labels.
- **Re-review gate (step 10):** Replaced hardcoded `>5` threshold with `caliper-settings get re_review_threshold`.

## Verification
All three `grep -q` checks pass.
