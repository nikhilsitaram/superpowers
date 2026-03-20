#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
rm -f "$TMPDIR/plan.md"
"$VALIDATE" --render "$TMPDIR/plan.json"
if diff -u "$FIXTURES/valid-plan/plan.md" "$TMPDIR/plan.md"; then
  echo "PASS: render matches expected output"
  ((PASS++)) || true
else
  echo "FAIL: render does not match expected output"
  ((FAIL++)) || true
fi

"$VALIDATE" --render "$TMPDIR/plan.json"
if diff -u "$FIXTURES/valid-plan/plan.md" "$TMPDIR/plan.md"; then
  echo "PASS: render is idempotent"
  ((PASS++)) || true
else
  echo "FAIL: render is not idempotent"
  ((FAIL++)) || true
fi

jq '.phases[0].tasks[0].status = "complete"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
"$VALIDATE" --render "$TMPDIR/plan.json"
if grep -q '\[x\] A1' "$TMPDIR/plan.md"; then
  echo "PASS: completed task renders with [x]"
  ((PASS++)) || true
else
  echo "FAIL: completed task does not render with [x]"
  ((FAIL++)) || true
fi

if grep -q '\[ \] A2' "$TMPDIR/plan.md"; then
  echo "PASS: pending task renders with [ ]"
  ((PASS++)) || true
else
  echo "FAIL: pending task does not render with [ ]"
  ((FAIL++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
