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
#   Returns 0 and sets RESOLVED_STATE_FILE (the path to read) +
#   RESOLVED_SOURCE=pinned|own|fallback|legacy (so the caller can surface WHICH
#   file it read — see the fallback caveat below). Returns 1 when no candidate
#   exists at all (caller maps that to its "no state file" exit).
#
#   Results come back in globals, NOT stdout: the caller must invoke this
#   directly (`resolve_state_file 5h`), never in a `$(...)` — a command
#   substitution runs in a subshell, so RESOLVED_SOURCE would be lost.
#
# Selection order:
#   0. QUEUE_STATE_FILE non-empty -> that exact file (legacy single-file pin:
#      tests, and users who relocated state before per-session keying).
#   1. Our own session's file ($CLAUDE_CODE_SESSION_ID) -> authoritative. Read it
#      even if the requested window is null: a null there means "our window is
#      genuinely unavailable" (caller -> exit 2), which must NEVER silently fall
#      through to another session's number.
#   2. No own file -> the freshest state.d file (newest mtime) that carries a
#      NUMERIC reading for the requested window. mtime == captured_at here (the
#      wrapper stamps at write time), so `ls -t` and captured_at agree.
#   3. Legacy shared $QUEUE_STATE_DIR/state.json, if present.
#
# LOAD-BEARING ASSUMPTION: step 1 only fires when the statusline payload's
# `.session_id` (what the wrapper keys the write on) equals this process's
# $CLAUDE_CODE_SESSION_ID (what we key the read on). Claude Code populates both
# from the same session UUID (the transcript file is named by it), so they match
# for a consumer running in the SAME session that renders the statusline — which
# is where queue/usage-guard invoke these scripts. They do NOT match for a
# consumer run inside a dispatched subagent (its own CLAUDE_CODE_SESSION_ID), so
# such a caller falls to step 2. That fallback picks the freshest numeric file,
# which on a multi-account machine may be ANOTHER account's session — the very
# thing per-session keying prevents for step 1. RESOLVED_SOURCE!=own is the
# signal that this weaker guarantee is in play; callers surface it.
#
# Config (env): QUEUE_STATE_DIR (default ~/.claude/queue); QUEUE_STATE_FILE
# (unset by default; set non-empty to pin a single legacy file).

resolve_state_file() {
  local window="$1"
  RESOLVED_STATE_FILE=""
  RESOLVED_SOURCE=""

  # 0. Explicit single-file pin (empty is treated as unset).
  if [ -n "${QUEUE_STATE_FILE:+set}" ]; then
    RESOLVED_SOURCE="pinned"
    RESOLVED_STATE_FILE="$QUEUE_STATE_FILE"
    return 0
  fi

  local dir="${QUEUE_STATE_DIR:-$HOME/.claude/queue}"
  local sd="$dir/state.d"

  # 1. Own session's file is authoritative.
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$sid" ] && [ -f "$sd/$sid.json" ]; then
    RESOLVED_SOURCE="own"
    RESOLVED_STATE_FILE="$sd/$sid.json"
    return 0
  fi

  # 2. Freshest state.d file with a numeric value for this window.
  local upath
  if [ "$window" = "7d" ]; then upath='.seven_day.used_percentage'; else upath='.used_percentage'; fi
  if [ -d "$sd" ]; then
    local f
    for f in $(ls -t "$sd"/*.json 2>/dev/null); do
      if jq -e "($upath) | type == \"number\"" "$f" >/dev/null 2>&1; then
        RESOLVED_SOURCE="fallback"
        RESOLVED_STATE_FILE="$f"
        return 0
      fi
    done
  fi

  # 3. Legacy shared file.
  if [ -f "$dir/state.json" ]; then
    RESOLVED_SOURCE="legacy"
    RESOLVED_STATE_FILE="$dir/state.json"
    return 0
  fi

  return 1
}
