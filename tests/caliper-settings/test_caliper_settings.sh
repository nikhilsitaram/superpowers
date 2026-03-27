#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/caliper-settings"
DEFAULTS_FILE="$REPO_ROOT/defaults.json"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    ((FAIL++)) || true
  fi
}

check_fail() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "FAIL: $desc (expected failure but succeeded)"
    ((FAIL++)) || true
  else
    echo "PASS: $desc"
    ((PASS++)) || true
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (output did not contain '$needle')"
    ((FAIL++)) || true
  fi
}

NUM_SETTINGS=$(jq 'keys | length' "$DEFAULTS_FILE")
ALL_KEYS=$(jq -r 'keys[]' "$DEFAULTS_FILE")
FIRST_BOOL_KEY=$(jq -r 'to_entries[] | select(.value.type == "bool") | .key' "$DEFAULTS_FILE" | head -1)
FIRST_BOOL_DEFAULT=$(jq -r --arg k "$FIRST_BOOL_KEY" '.[$k].default' "$DEFAULTS_FILE")
FIRST_ENUM_KEY=$(jq -r 'to_entries[] | select(.value.type == "enum") | .key' "$DEFAULTS_FILE" | head -1)
FIRST_ENUM_DEFAULT=$(jq -r --arg k "$FIRST_ENUM_KEY" '.[$k].default' "$DEFAULTS_FILE")
FIRST_ENUM_VALUES=$(jq -r --arg k "$FIRST_ENUM_KEY" '.[$k].values | join(", ")' "$DEFAULTS_FILE")
FIRST_ENUM_ALT=$(jq -r --arg k "$FIRST_ENUM_KEY" '.[$k].values[1]' "$DEFAULTS_FILE")
FIRST_INT_KEY=$(jq -r 'to_entries[] | select(.value.type == "int") | .key' "$DEFAULTS_FILE" | head -1)
FIRST_INT_DEFAULT=$(jq -r --arg k "$FIRST_INT_KEY" '.[$k].default' "$DEFAULTS_FILE")

setup() {
  TMPDIR=$(mktemp -d)
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
  export CLAUDE_PLUGIN_DATA="$TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

echo "=== Environment validation ==="

setup
check_fail "fails without CLAUDE_PLUGIN_ROOT" env -u CLAUDE_PLUGIN_ROOT bash "$SCRIPT" list
check_fail "fails without CLAUDE_PLUGIN_DATA" env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" list
teardown

echo ""
echo "=== Usage ==="

setup
check_fail "no args exits non-zero" bash "$SCRIPT"
output=$(bash "$SCRIPT" 2>&1 || true)
assert_contains "no args shows usage" "$output" "Usage"
check_fail "unknown subcommand exits non-zero" bash "$SCRIPT" foobar
teardown

echo ""
echo "=== list ==="

setup
output=$(bash "$SCRIPT" list)
assert_contains "list shows KEY header" "$output" "KEY"
assert_contains "list shows CURRENT header" "$output" "CURRENT"
assert_contains "list shows DEFAULT header" "$output" "DEFAULT"
assert_contains "list shows DESCRIPTION header" "$output" "DESCRIPTION"
for key in $ALL_KEYS; do
  assert_contains "list shows key $key" "$output" "$key"
done
teardown

echo ""
echo "=== get ==="

setup
assert_eq "get bool default" "$FIRST_BOOL_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_BOOL_KEY")"
assert_eq "get enum default" "$FIRST_ENUM_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_ENUM_KEY")"
assert_eq "get int default" "$FIRST_INT_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_INT_KEY")"
check_fail "get unknown key fails" bash "$SCRIPT" get nonexistent_key
output=$(bash "$SCRIPT" get nonexistent_key 2>&1 || true)
assert_contains "get unknown key message" "$output" "Unknown setting"
teardown

echo ""
echo "=== set ==="

setup
check "set bool to true" bash "$SCRIPT" set "$FIRST_BOOL_KEY" true
assert_eq "get bool after set" "true" "$(bash "$SCRIPT" get "$FIRST_BOOL_KEY")"
check "settings.json created" test -f "$TMPDIR/settings.json"
stored=$(jq -r --arg k "$FIRST_BOOL_KEY" '.[$k]' "$TMPDIR/settings.json")
assert_eq "bool stored as JSON boolean" "true" "$stored"

check "set enum" bash "$SCRIPT" set "$FIRST_ENUM_KEY" "$FIRST_ENUM_ALT"
assert_eq "get enum after set" "$FIRST_ENUM_ALT" "$(bash "$SCRIPT" get "$FIRST_ENUM_KEY")"

check "set int" bash "$SCRIPT" set "$FIRST_INT_KEY" 42
assert_eq "get int after set" "42" "$(bash "$SCRIPT" get "$FIRST_INT_KEY")"
stored_int=$(jq --arg k "$FIRST_INT_KEY" '.[$k]' "$TMPDIR/settings.json")
assert_eq "int stored as JSON number" "42" "$stored_int"
teardown

echo ""
echo "=== set validation ==="

setup
check_fail "set bool rejects non-bool" bash "$SCRIPT" set "$FIRST_BOOL_KEY" yes
output=$(bash "$SCRIPT" set "$FIRST_BOOL_KEY" yes 2>&1 || true)
assert_contains "bool error message" "$output" "expected bool"

check_fail "set enum rejects invalid" bash "$SCRIPT" set "$FIRST_ENUM_KEY" invalid_value
output=$(bash "$SCRIPT" set "$FIRST_ENUM_KEY" invalid_value 2>&1 || true)
assert_contains "enum error message" "$output" "expected one of"

check_fail "set int rejects non-int" bash "$SCRIPT" set "$FIRST_INT_KEY" abc
output=$(bash "$SCRIPT" set "$FIRST_INT_KEY" abc 2>&1 || true)
assert_contains "int error message" "$output" "expected int"

check_fail "set unknown key fails" bash "$SCRIPT" set nonexistent_key value
teardown

echo ""
echo "=== reset ==="

setup
bash "$SCRIPT" set "$FIRST_BOOL_KEY" true > /dev/null
assert_eq "before reset" "true" "$(bash "$SCRIPT" get "$FIRST_BOOL_KEY")"
check "reset single key" bash "$SCRIPT" reset "$FIRST_BOOL_KEY"
assert_eq "after reset single" "$FIRST_BOOL_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_BOOL_KEY")"

bash "$SCRIPT" set "$FIRST_BOOL_KEY" true > /dev/null
bash "$SCRIPT" set "$FIRST_INT_KEY" 99 > /dev/null
check "reset all" bash "$SCRIPT" reset
assert_eq "after reset all bool" "$FIRST_BOOL_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_BOOL_KEY")"
assert_eq "after reset all int" "$FIRST_INT_DEFAULT" "$(bash "$SCRIPT" get "$FIRST_INT_KEY")"
teardown

echo ""
echo "=== reset no-op when no settings.json ==="

setup
check "reset with no settings.json is no-op" bash "$SCRIPT" reset
check "reset key with no settings.json is no-op" bash "$SCRIPT" reset "$FIRST_BOOL_KEY"
check_fail "reset unknown key fails" bash "$SCRIPT" reset nonexistent_key
teardown

echo ""
echo "=== corrupted settings.json ==="

setup
echo "NOT JSON" > "$TMPDIR/settings.json"
output=$(bash "$SCRIPT" list 2>&1)
assert_contains "warns about invalid JSON" "$output" "invalid JSON"
assert_contains "still shows defaults" "$output" "$FIRST_BOOL_KEY"
teardown

echo ""
echo "=== list reflects overrides ==="

setup
bash "$SCRIPT" set "$FIRST_BOOL_KEY" true > /dev/null
output=$(bash "$SCRIPT" list)
assert_contains "list shows overridden value" "$output" "true"
teardown

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
