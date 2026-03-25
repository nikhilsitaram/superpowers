# A5 Completion: Update test fixtures and test scripts

## Changes

- **`tests/validate-plan/fixtures/valid-plan/plan.json`**: Changed `"workflow": "create-pr"` to `"workflow": "pr-create"`
- **`tests/validate-plan/test_schema.sh`**: Updated Test 17 from `merge-pr` to `pr-merge`, updated Tests 20-22 from `create-pr` to `pr-create`, added Tests 18d/18e to reject old `create-pr`/`merge-pr` values
- **`tests/validate-plan/test_check_workflow.sh`**: Updated section headers and Tests 5-9b from `create-pr`/`merge-pr` to `pr-create`/`pr-merge`
- **`tests/validate-plan/test_check_deps.sh`**: Updated all six occurrences of `"workflow": "create-pr"` to `"workflow": "pr-create"`

## Test Results

- `test_schema.sh`: 27 passed, 0 failed
- `test_check_workflow.sh`: 11 passed, 0 failed
- `test_check_deps.sh`: 6 passed, 0 failed

## Self-review

Grep confirmed no remaining `"create-pr"` or `"merge-pr"` in test files except in Tests 18d/18e which intentionally test that old values are rejected.
