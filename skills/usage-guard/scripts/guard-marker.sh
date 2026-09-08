#!/usr/bin/env bash
# guard-marker.sh set|clear   — manage the "active --queue run" marker.
#
# The marker (active-guard.json, beside the queue state file) is the single gate
# the StopFailure backstop keys on: a rate-limit hook does work ONLY while this
# marker is present, and no-ops otherwise. A `/usage-guard --queue` run writes it
# at start and refreshes it after each ledger update (so the backstop always has
# the latest continuation payload), and clears it the moment the run stops, the
# task completes, or it queues its own continuation at the threshold — i.e. once
# there is nothing left for the backstop to rescue.
#
#   set     reads the CONTINUATION PAYLOAD on stdin; writes {updated_at, cwd,
#           payload} atomically.
#   clear   removes the marker (idempotent — fine if already gone).
#
# Config (env): QUEUE_STATE_DIR (default ~/.claude/queue), or QUEUE_STATE_FILE
# whose dirname is used when QUEUE_STATE_DIR is unset. The marker lives beside the
# usage state, so it must resolve the same directory the wrapper/consumers use.
set -u

STATE_DIR="${QUEUE_STATE_DIR:-$(dirname "${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}")}"
MARKER="$STATE_DIR/active-guard.json"

case "${1:-}" in
  set)
    mkdir -p "$STATE_DIR"
    payload="$(cat)"
    tmp="$MARKER.tmp.$$"
    # jq builds the JSON so the payload is escaped correctly regardless of content.
    if jq -n --argjson now "$(date +%s)" --arg cwd "$PWD" --arg p "$payload" \
        '{updated_at:$now, cwd:$cwd, payload:$p}' > "$tmp" 2>/dev/null; then
      mv "$tmp" "$MARKER"
    else
      rm -f "$tmp"
      echo "ERROR: failed to write marker $MARKER." >&2
      exit 1
    fi
    ;;
  clear)
    rm -f "$MARKER"
    ;;
  *)
    echo "usage: guard-marker.sh set|clear   (set reads payload on stdin)" >&2
    exit 64
    ;;
esac
