# A3 Completion Notes

**Summary:** Added 16 new tests to `tests/hooks/test_safe_commands.sh` covering 5 new safe commands (ln, dirname, basename, [, command), 7 interpreter resolution cases (bash/sh + script, flag skipping, -euo pipefail limitation, variable script arg deny, bare bash fallthrough, basename extraction), and 4 variable-as-command deny cases ($VAR, "$VAR", ${VAR}, compound with variable). Also added the `assert_output_contains_deny_with_reason` helper.
**Deviations:** None
**Files Changed:** `tests/hooks/test_safe_commands.sh`
**Test Results:** All 48 tests pass (32 existing + 16 new). All 7 PermissionRequest tests pass.
**Deferred Issues:** None
