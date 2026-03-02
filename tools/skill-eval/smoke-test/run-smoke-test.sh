#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_DIR="$SCRIPT_DIR"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"  # repo root (superpowers/)
OUTPUT_DIR="/tmp/skill-eval-smoke-test/$(date +%s)"

mkdir -p "$OUTPUT_DIR"

echo "=== Skill Eval Smoke Test ==="
echo "Plugin dir: $PLUGIN_DIR"
echo "Output dir: $OUTPUT_DIR"
echo ""

# Read prompt from evals.json
PROMPT=$(python3 -c "import json; d=json.load(open('$EVAL_DIR/evals.json')); print(d['evals'][0]['prompt'])")

echo "Prompt: $PROMPT"
echo ""
echo "Running claude -p with verification-before-completion skill..."

timeout 120 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_DIR" \
    --dangerously-skip-permissions \
    --max-turns 3 \
    --output-format stream-json \
    > "$OUTPUT_DIR/claude-output.json" 2>&1 || true

echo ""

# Check output file exists and has content
if [ -s "$OUTPUT_DIR/claude-output.json" ]; then
    echo "[PASS] claude-output.json exists and is non-empty"
else
    echo "[FAIL] claude-output.json is empty or missing"
    exit 1
fi

# Check if any Skill tool was invoked
if grep -q '"name":"Skill"' "$OUTPUT_DIR/claude-output.json" 2>/dev/null; then
    echo "[PASS] Skill tool was invoked"
else
    echo "[WARN] Skill tool was NOT invoked (may be OK for smoke test)"
fi

# Check if verification skill specifically was triggered
if grep -q 'verification-before-completion' "$OUTPUT_DIR/claude-output.json" 2>/dev/null; then
    echo "[PASS] verification-before-completion was triggered"
else
    echo "[WARN] verification-before-completion was NOT triggered"
fi

echo ""
echo "=== Smoke test complete ==="
echo "Output: $OUTPUT_DIR/claude-output.json"
echo "Size: $(wc -c < "$OUTPUT_DIR/claude-output.json") bytes"
