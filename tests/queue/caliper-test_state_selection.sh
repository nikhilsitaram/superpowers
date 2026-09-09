#!/usr/bin/env bash
# Regression test for #286: usage-window state is keyed per session so a Claude
# session signed into a DIFFERENT account/plan can't poison this one's reading.
#
# Drives the real producer (statusline-wrapper.sh) and both real consumers
# (check-usage.sh, compute-fire.sh) against a temp QUEUE_STATE_DIR, with NO
# QUEUE_STATE_FILE set (that would pin legacy single-file mode). The producer
# keys on the payload's `session_id`; the consumers key on $CLAUDE_CODE_SESSION_ID.
#
# macOS/BSD only: consumers use `date -r`; the prune case uses `date -v`. Skips
# gracefully on GNU date (Linux CI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$REPO_ROOT/skills/queue/scripts/statusline-wrapper.sh"
COMPUTE_FIRE="$REPO_ROOT/skills/queue/scripts/compute-fire.sh"
CHECK_USAGE="$REPO_ROOT/skills/usage-guard/scripts/check-usage.sh"

if ! date -r 0 >/dev/null 2>&1; then
  echo "SKIP: state-selection test requires BSD date (-r epoch / -v); not available here."
  exit 0
fi

pass=0; fail=0
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
now="$(date +%s)"
F5=$(( (now/3600 + 2)*3600 + 17*60 ))   # a future 5h reset (whole future :17)
F7=$(( F5 + 7*86400 ))                   # a future 7d reset, a week out

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $desc"; pass=$((pass+1))
  else echo "FAIL: $desc"; echo "  cond: $cond"; fail=$((fail+1)); fi
}

# Producer: a session (its id lives in the payload) renders a statusline blob.
produce() {  # produce <blob>
  printf '%s' "$1" | env -u QUEUE_STATE_FILE QUEUE_STATE_DIR="$DIR" \
    QUEUE_STATUSLINE="cat" PATH="$PATH" HOME="$HOME" bash "$WRAPPER" >/dev/null
}
# Consumer: a session (its id in $CLAUDE_CODE_SESSION_ID) reads its usage.
run() {  # run <session_id> <helper> [args...]
  local sid="$1" helper="$2"; shift 2
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env -u QUEUE_STATE_FILE QUEUE_STATE_DIR="$DIR" CLAUDE_CODE_SESSION_ID="$sid" \
    PATH="$PATH" HOME="$HOME" bash "$helper" "$@" >"$tmp_out" 2>"$tmp_err"
  RC=$?
  set -e
  STDOUT="$(cat "$tmp_out")"; STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}
field() { echo "$STDOUT" | sed -n "s/^$1=//p"; }

ours_blob="{\"session_id\":\"sess-ours\",\"rate_limits\":{\"five_hour\":{\"resets_at\":$F5,\"used_percentage\":59},\"seven_day\":{\"resets_at\":$F7,\"used_percentage\":49}}}"
# Foreign account/plan: NO five_hour block; seven_day on the SAME Monday epoch but
# a DIFFERENT weekly figure — exactly the payload that used to poison the shared file.
foreign_blob="{\"session_id\":\"sess-foreign\",\"rate_limits\":{\"seven_day\":{\"resets_at\":$F7,\"used_percentage\":4}}}"

# --- Producer keys per session ---
produce "$ours_blob"
assert "producer writes state.d/<session>.json"  '[[ -f "$DIR/state.d/sess-ours.json" ]]'
assert "producer does NOT write legacy state.json when session_id present" '[[ ! -f "$DIR/state.json" ]]'
assert "own file has our 5h (59)"                 '[[ "$(jq -r .used_percentage "$DIR/state.d/sess-ours.json")" == "59" ]]'
assert "own file has our 7d (49)"                 '[[ "$(jq -r .seven_day.used_percentage "$DIR/state.d/sess-ours.json")" == "49" ]]'

# --- The bug: a foreign session must NOT touch our file ---
produce "$foreign_blob"
assert "foreign session writes its OWN file"      '[[ -f "$DIR/state.d/sess-foreign.json" ]]'
assert "our 5h survives foreign write (still 59)" '[[ "$(jq -r .used_percentage "$DIR/state.d/sess-ours.json")" == "59" ]]'
assert "our 7d survives foreign write (still 49)" '[[ "$(jq -r .seven_day.used_percentage "$DIR/state.d/sess-ours.json")" == "49" ]]'

# --- Consumer reads its OWN session's file (authoritative), foreign is fresher ---
run sess-ours "$CHECK_USAGE"
assert "check-usage as ours reads own 5h (59), exit 0" '[[ $RC -eq 0 && "$(field USED_PCT)" == "59.0" ]]'
assert "own read reports SOURCE=own"                   '[[ "$(field SOURCE)" == "own" ]]'
run sess-ours "$CHECK_USAGE" --window 7d
assert "check-usage as ours reads own 7d (49), NOT foreign 4" '[[ "$(field USED_PCT)" == "49.0" ]]'
assert "own 7d read also reports SOURCE=own"           '[[ "$(field SOURCE)" == "own" ]]'

# --- A set-but-EMPTY QUEUE_STATE_FILE is treated as unset (not a pin to "") ---
# Bracketed in set +e/-e so a future regression (non-zero exit) still prints FAIL
# rather than tripping the script's `set -e` before the assert runs.
set +e
STDOUT="$(env QUEUE_STATE_FILE="" QUEUE_STATE_DIR="$DIR" CLAUDE_CODE_SESSION_ID=sess-ours \
  PATH="$PATH" HOME="$HOME" bash "$CHECK_USAGE" 2>/dev/null)"; RC=$?
set -e
assert "empty QUEUE_STATE_FILE falls to per-session (own 59, not pin to '')" '[[ $RC -eq 0 && "$(field USED_PCT)" == "59.0" && "$(field SOURCE)" == "own" ]]'

# --- Own file's window null => exit 2, NEVER fall through to a foreign number ---
# A foreign session that DOES carry a numeric 5h.
produce "{\"session_id\":\"sess-f2\",\"rate_limits\":{\"five_hour\":{\"resets_at\":$F5,\"used_percentage\":7}}}"
# Our own next render legitimately lacks five_hour (nulls our 5h on disk).
produce "{\"session_id\":\"sess-ours\",\"rate_limits\":{\"seven_day\":{\"resets_at\":$F7,\"used_percentage\":49}}}"
assert "own 5h now null on disk" '[[ "$(jq -r .used_percentage "$DIR/state.d/sess-ours.json")" == "null" ]]'
run sess-ours "$CHECK_USAGE"
assert "own null 5h -> exit 2 (not foreign 7)" '[[ $RC -eq 2 ]]'

# --- No own file -> freshest state.d file with a numeric reading for the window ---
run sess-unknown "$CHECK_USAGE"
assert "unknown session falls back to a numeric 5h file (exit 0)" '[[ $RC -eq 0 ]]'
assert "fallback 5h is a real numeric reading (7 from sess-f2)"   '[[ "$(field USED_PCT)" == "7.0" ]]'
assert "fallback read reports SOURCE=fallback"                    '[[ "$(field SOURCE)" == "fallback" ]]'
# 7d fallback selects the freshest state.d file with a NUMERIC 7d value. sess-f2
# has no 7d (skipped); sess-ours (7d 49) was written after sess-foreign (7d 4).
run sess-unknown "$CHECK_USAGE" --window 7d
assert "7d fallback picks freshest numeric 7d file (49, not 4)"   '[[ $RC -eq 0 && "$(field USED_PCT)" == "49.0" ]]'
assert "7d fallback reports SOURCE=fallback"                      '[[ "$(field SOURCE)" == "fallback" ]]'
# compute-fire's fallback predicate is resets_at (not used_percentage): sess-ours
# has a null 5h resets_at, so the 5h fallback must skip it and pick sess-f2 (F5).
run sess-unknown "$COMPUTE_FIRE"
assert "compute-fire fallback selects by resets_at (exit 0)"      '[[ $RC -eq 0 && "$(field SOURCE)" == "fallback" ]]'
assert "compute-fire fallback targets sess-f2's 5h reset (F5)"    "[[ \"\$(field FIRE_EPOCH)\" -ge $F5 ]]"

# --- Legacy fallback: no state.d at all, but a legacy state.json exists ---
rm -rf "$DIR/state.d"
printf '{"resets_at":%s,"used_percentage":33,"captured_at":%s}\n' "$F5" "$now" > "$DIR/state.json"
run sess-unknown "$CHECK_USAGE"
assert "legacy state.json read when no state.d (exit 0, 33)" '[[ $RC -eq 0 && "$(field USED_PCT)" == "33.0" ]]'
assert "legacy read reports SOURCE=legacy"                   '[[ "$(field SOURCE)" == "legacy" ]]'
rm -f "$DIR/state.json"

# --- No state at all -> exit 1 (no-state) ---
run sess-unknown "$CHECK_USAGE"
assert "no state anywhere -> exit 1" '[[ $RC -eq 1 ]]'

# --- Prune: per-session files untouched >24h are dropped on the next write ---
mkdir -p "$DIR/state.d"
printf '{}' > "$DIR/state.d/sess-stale.json"
touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DIR/state.d/sess-stale.json"
produce "$ours_blob"
assert "stale (>24h) per-session file pruned"     '[[ ! -f "$DIR/state.d/sess-stale.json" ]]'
assert "fresh own file kept after prune"          '[[ -f "$DIR/state.d/sess-ours.json" ]]'
# The active session's OWN file must never be pruned — even if it is >24h old AND
# this render carries no window to rewrite it (else good data drops to fallback).
touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DIR/state.d/sess-ours.json"
produce '{"session_id":"sess-ours"}'
assert "own file survives prune when >24h old and render has no window" '[[ -f "$DIR/state.d/sess-ours.json" ]]'

# --- Defensive: a session_id with path traversal is rejected -> legacy file ---
rm -rf "$DIR/state.d" "$DIR/state.json"
produce "{\"session_id\":\"../evil\",\"rate_limits\":{\"five_hour\":{\"resets_at\":$F5,\"used_percentage\":10}}}"
assert "traversal session_id -> no escape file written" '[[ ! -e "$DIR/evil.json" && ! -e "$DIR/../evil.json" ]]'
assert "traversal session_id -> legacy state.json used" '[[ -f "$DIR/state.json" ]]'

# --- compute-fire is session-aware too ---
rm -rf "$DIR/state.d" "$DIR/state.json"
produce "$ours_blob"
produce "$foreign_blob"
run sess-ours "$COMPUTE_FIRE"
assert "compute-fire as ours consumes own file (exit 0)" '[[ $RC -eq 0 ]]'
assert "compute-fire as ours targets our 5h reset"       "[[ \"\$(field FIRE_EPOCH)\" -ge $F5 ]]"
run sess-ours "$COMPUTE_FIRE" --window 7d
assert "compute-fire as ours --window 7d (exit 0)"       '[[ $RC -eq 0 ]]'

echo "----"
echo "state-selection: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
