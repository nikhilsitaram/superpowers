# Skill Eval Framework

Vendored from [anthropics/skills/skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) on 2026-03-02.

## Usage

Run from within `tools/skill-eval/`:

    cd tools/skill-eval
    python3 -m scripts.run_eval --help

Note: `python3 -m tools.skill-eval.scripts.run_eval` does NOT work — Python module paths cannot contain hyphens. Always `cd` into the directory first.

## Key scripts

- `scripts/run_eval.py` — Run test prompts with/without a skill via `claude -p`
- `scripts/aggregate_benchmark.py` — Aggregate pass rates and timing into benchmark.json
- `scripts/run_loop.py` — Full eval-improve-re-eval iteration loop
- `scripts/generate_report.py` — Human-readable report from benchmark data
- `eval-viewer/generate_review.py` — HTML viewer for side-by-side comparison

## Dependencies

Requires `claude` CLI (`claude -p` headless mode).

Non-stdlib Python dependencies found in vendored scripts (not all are needed for our eval use case):
- `anthropic` — Anthropic Python SDK (used by some scripts)
- `yaml` — PyYAML (`pip install pyyaml`)
