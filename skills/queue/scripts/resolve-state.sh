#!/usr/bin/env bash
# resolve-state.sh — shared state-file selector, sourced by the two consumers
# (check-usage.sh, compute-fire.sh). NOT executable on its own.
#
# Usage-window state is keyed per session: statusline-wrapper.sh writes
# $QUEUE_STATE_DIR/state.d/<session_id>.json, so a session signed into a
# DIFFERENT account/plan (whose payload may lack the five_hour window, or carry
# a different weekly percentage under the same Monday reset epoch) writes its
# OWN file and can never poison ours. This function picks which file a consumer
# should read.
#
# resolve_state_file <window:5h|7d>
#   echoes the path to read and returns 0; echoes nothing and returns 1 when no
#   candidate exists at all (caller maps that to its "no state file" exit).
#
# Selection order:
#   0. QUEUE_STATE_FILE explicitly set -> that exact file (legacy single-file
#      pin: tests, and users who relocated state before per-session keying).
#   1. Our own session's file ($CLAUDE_CODE_SESSION_ID) -> authoritative. Read it
#      even if the requested window is null: a null there means "our window is
#      genuinely unavailable" (caller -> exit 2), which must NEVER silently fall
#      through to another session's number.
#   2. No own file -> the freshest state.d file (newest mtime) that carries a
#      NUMERIC reading for the requested window. mtime == captured_at here (the
#      wrapper stamps at write time), so `ls -t` and captured_at agree.
#   3. Legacy shared $QUEUE_STATE_DIR/state.json, if present.
#
# Config (env): QUEUE_STATE_DIR (default ~/.claude/queue); QUEUE_STATE_FILE
# (unset by default; set to pin a single legacy file).

resolve_state_file() {
  local window="$1"

  # 0. Explicit single-file pin.
  if [ -n "${QUEUE_STATE_FILE+set}" ]; then
    printf '%s\n' "$QUEUE_STATE_FILE"
    return 0
  fi

  local dir="${QUEUE_STATE_DIR:-$HOME/.claude/queue}"
  local sd="$dir/state.d"

  # 1. Own session's file is authoritative.
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$sid" ] && [ -f "$sd/$sid.json" ]; then
    printf '%s\n' "$sd/$sid.json"
    return 0
  fi

  # 2. Freshest state.d file with a numeric value for this window.
  local upath
  if [ "$window" = "7d" ]; then upath='.seven_day.used_percentage'; else upath='.used_percentage'; fi
  if [ -d "$sd" ]; then
    local f
    for f in $(ls -t "$sd"/*.json 2>/dev/null); do
      if jq -e "($upath) | type == \"number\"" "$f" >/dev/null 2>&1; then
        printf '%s\n' "$f"
        return 0
      fi
    done
  fi

  # 3. Legacy shared file.
  if [ -f "$dir/state.json" ]; then
    printf '%s\n' "$dir/state.json"
    return 0
  fi

  return 1
}
