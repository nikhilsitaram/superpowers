---
status: In Development
---

# skill-eval Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development

**Goal:** Create a skill-eval skill that standardizes output quality evaluation with assertion-based grading, blind before/after comparison, and variance analysis.

**Architecture:** SKILL.md orchestrates the workflow (<1,000w). Python scripts handle deterministic work (running claude -p, aggregating stats). Agent prompts (grader, comparator, analyzer) handle qualitative evaluation via subagents. All eval data lives in `.skill-evals/` (gitignored).

**Tech Stack:** Python 3, `claude` CLI (`claude -p`), JSON, Claude Code Agent tool for subagents

**Design divergences:**
- Directory structure uses per-run subdirectories (`before/run-1/output.txt`, `before/run-1/timing.json`, `before/run-1/grading.json`) instead of the design doc's flat layout (`before/run-1.txt`). Per-run directories are needed because each run has its own timing.json and grading.json alongside the output.
- `--output-format json` replaces design doc's `--output-format text` — json provides timing metadata (duration_ms, cost_usd) and resolves the stderr output issue.
- Subdirectory layout (`agents/`, `scripts/`, `references/`) is a new convention for this repo (existing skills put all files flat alongside SKILL.md). Justified because this skill has 8 supporting files — flat would be unwieldy. The `**See:**` pattern works with relative subdirectory paths since the agent resolves them from the skill directory.

**Task 0 skip justification:** No broad integration test because the cross-task data flow (run_eval.py → grading.json → aggregate_benchmark.py) is validated by the inline smoke tests in Tasks 2 and 3. Task 2's functional smoke test with mock data exercises the full aggregate pipeline. The real integration test is running the skill on an existing skill (dogfooding) after all tasks complete.

---

## Phase 1 — Core Implementation
**Status:** Complete (2026-03-03)
**Rationale:** All components are independent with shared schemas as the only interface contract. Interface-first ordering: schemas → scripts → agent prompts → SKILL.md.

- [x] Task 1: Project scaffolding — schemas, directory structure, repo integration
- [x] Task 2: Port aggregate_benchmark.py from Anthropic's skill-creator
- [x] Task 3: Create run_eval.py for behavioral output evaluation
- [x] Task 4: Adapt grader agent prompt for text-only evaluation
- [x] Task 5: Adapt comparator agent prompt for blind A/B comparison
- [x] Task 6: Adapt analyzer agent prompt for post-hoc and benchmark analysis
- [x] Task 7: Create SKILL.md workflow orchestration

---

## Task Details

### Task 1: Project Scaffolding — Schemas, Directory Structure, Repo Integration

**Files:**
- Create: `skills/skill-eval/references/schemas.md`
- Create: `skills/skill-eval/scripts/__init__.py`
- Modify: `.gitignore` — add `.skill-evals/`
- Modify: `README.md` — add skill-eval to skills list

**Verification:** `test -f skills/skill-eval/references/schemas.md && grep -q ".skill-evals" .gitignore && grep -q "skill-eval" README.md && echo "PASS"`

**Done when:** schemas.md contains all 8 JSON schema definitions (evals.json, config.json, eval_metadata.json, timing.json, grading.json, benchmark.json, comparison.json, analysis.json); .gitignore includes `.skill-evals/`; README lists skill-eval.

**Avoid:** Don't include schemas for dropped components (history.json, metrics.json) — these are from Anthropic's executor workflow which we don't use. Our eval subjects produce text output only, not tool-use transcripts.

**Step 1: Create directory structure**

Note: `agents/` directory is NOT created here — Tasks 4-6 create it when they write agent prompt files. Only `references/` and `scripts/` are needed for Task 1.

```bash
mkdir -p skills/skill-eval/references skills/skill-eval/scripts
touch skills/skill-eval/scripts/__init__.py
```

**Step 2: Write schemas.md**

Create `skills/skill-eval/references/schemas.md` with the following content:

````markdown
# JSON Schemas

Data schemas for skill-eval. All files live under `.skill-evals/{skill-name}/`.

---

## evals.json

Eval prompts and assertions. Located at `.skill-evals/{skill-name}/evals.json`.

```json
{
  "skill_name": "test-driven-development",
  "evals": [
    {
      "id": 1,
      "name": "deadline-pressure",
      "prompt": "I have a tight deadline, can we skip tests?",
      "expectations": [
        "Refuses to skip TDD",
        "Explains why deadline pressure increases TDD value",
        "Does not propose writing tests after implementation"
      ]
    }
  ]
}
```

**Fields:**
- `skill_name`: Name matching the skill directory
- `evals[].id`: Unique integer identifier
- `evals[].name`: Descriptive name (used in directory naming)
- `evals[].prompt`: The task prompt sent to `claude -p`
- `evals[].expectations`: Verifiable behavioral assertions

---

## config.json

Variant definitions for an iteration. Located at `.skill-evals/{skill-name}/iteration-N/config.json`.

```json
{
  "before": {
    "label": "v1-authority",
    "type": "skill",
    "skill_path": ".skill-evals/tdd/snapshot-before/SKILL.md"
  },
  "after": {
    "label": "v2-reasoning",
    "type": "skill",
    "skill_path": "skills/test-driven-development/SKILL.md"
  }
}
```

**Fields:**
- `before`/`after`: Variant definitions
- `label`: Human-readable version name
- `type`: `"skill"` (load SKILL.md as system prompt) or `"none"` (no skill baseline)
- `skill_path`: Path to SKILL.md (omit when type is "none")

---

## eval_metadata.json

Per-eval metadata. Located at `.skill-evals/{skill-name}/iteration-N/eval-{id}-{slug}/eval_metadata.json`.

```json
{
  "eval_id": 1,
  "eval_name": "deadline-pressure",
  "prompt": "I have a tight deadline, can we skip tests?",
  "expectations": [
    "Refuses to skip TDD",
    "Explains why deadline pressure increases TDD value"
  ]
}
```

---

## timing.json

Per-run timing. Located at `.../run-{n}/timing.json`.

```json
{
  "duration_ms": 2341,
  "wall_time_seconds": 2.5,
  "cost_usd": 0.003,
  "num_turns": 1,
  "is_error": false,
  "total_duration_seconds": 2.5
}
```

**Fields:**
- `duration_ms`: From `claude -p --output-format json` response
- `wall_time_seconds`: Python-measured wall clock time
- `cost_usd`: From claude response (if available)
- `total_duration_seconds`: Same as wall_time_seconds (compatibility with aggregate script)
- `is_error`: Whether the run errored

---

## grading.json

Per-run grading results. Located at `.../run-{n}/grading.json`.

```json
{
  "expectations": [
    {
      "text": "Refuses to skip TDD",
      "passed": true,
      "evidence": "Response states: 'Skipping tests under deadline pressure is exactly when bugs slip through...'"
    }
  ],
  "summary": {
    "passed": 2,
    "failed": 1,
    "total": 3,
    "pass_rate": 0.67
  },
  "timing": {
    "total_duration_seconds": 2.5
  },
  "claims": [
    {
      "claim": "Response suggests writing tests first",
      "type": "process",
      "verified": true,
      "evidence": "Step 1 in response explicitly says 'write the failing test first'"
    }
  ],
  "eval_feedback": {
    "suggestions": [
      {
        "assertion": "Refuses to skip TDD",
        "reason": "Too easy to satisfy — any mention of tests would pass. Consider: 'Explicitly refuses the request to skip, not just redirects to testing'"
      }
    ],
    "overall": "Assertions check presence but not reasoning quality."
  }
}
```

**Required fields in expectations array:** `text`, `passed`, `evidence` — the aggregate script depends on these exact names.

---

## benchmark.json

Aggregated statistics. Located at `.skill-evals/{skill-name}/iteration-N/benchmark.json`.

```json
{
  "metadata": {
    "skill_name": "test-driven-development",
    "skill_path": "skills/test-driven-development/SKILL.md",
    "timestamp": "2026-03-03T21:00:00Z",
    "evals_run": [1, 2, 3],
    "runs_per_configuration": 3
  },
  "runs": [
    {
      "eval_id": 1,
      "configuration": "after",
      "run_number": 1,
      "result": {
        "pass_rate": 0.85,
        "passed": 6,
        "failed": 1,
        "total": 7,
        "time_seconds": 2.5,
        "tokens": 0,
        "tool_calls": 0,
        "errors": 0
      },
      "expectations": [
        {"text": "...", "passed": true, "evidence": "..."}
      ],
      "notes": []
    }
  ],
  "run_summary": {
    "after": {
      "pass_rate": {"mean": 0.85, "stddev": 0.05, "min": 0.80, "max": 0.90},
      "time_seconds": {"mean": 2.5, "stddev": 0.3, "min": 2.1, "max": 2.8},
      "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0}
    },
    "before": {
      "pass_rate": {"mean": 0.35, "stddev": 0.08, "min": 0.28, "max": 0.45},
      "time_seconds": {"mean": 1.8, "stddev": 0.2, "min": 1.5, "max": 2.0},
      "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0}
    },
    "delta": {
      "pass_rate": "+0.50",
      "time_seconds": "+0.7",
      "tokens": "+0"
    }
  },
  "notes": []
}
```

---

## comparison.json

Blind comparator output. Located at `.skill-evals/{skill-name}/iteration-N/comparison.json`.

```json
{
  "winner": "A",
  "reasoning": "Output A provides a nuanced explanation of why TDD matters under deadline pressure. Output B simply states tests should be written without addressing the deadline concern.",
  "rubric": {
    "A": {
      "content": {"correctness": 5, "completeness": 5, "accuracy": 4},
      "structure": {"organization": 4, "formatting": 4, "usability": 4},
      "content_score": 4.7,
      "structure_score": 4.0,
      "overall_score": 8.7
    },
    "B": {
      "content": {"correctness": 3, "completeness": 2, "accuracy": 3},
      "structure": {"organization": 3, "formatting": 3, "usability": 3},
      "content_score": 2.7,
      "structure_score": 3.0,
      "overall_score": 5.7
    }
  },
  "output_quality": {
    "A": {
      "score": 9,
      "strengths": ["Addresses deadline concern directly", "Explains TDD value proposition"],
      "weaknesses": ["Slightly verbose"]
    },
    "B": {
      "score": 6,
      "strengths": ["Mentions testing"],
      "weaknesses": ["Does not address deadline pressure", "Generic response"]
    }
  }
}
```

---

## analysis.json

Post-hoc analyzer output. Located at `.skill-evals/{skill-name}/iteration-N/analysis.json`.

```json
{
  "comparison_summary": {
    "winner": "A",
    "winner_skill": "skills/test-driven-development/SKILL.md",
    "loser_skill": ".skill-evals/tdd/snapshot-before/SKILL.md",
    "comparator_reasoning": "Output A provides nuanced explanation under deadline pressure"
  },
  "winner_strengths": [
    "Reasoning-based framing ('you optimize for coherence, not correctness') led to persuasive response",
    "Addressed the emotional context (deadline pressure) directly"
  ],
  "loser_weaknesses": [
    "Authority-based framing ('Iron Law', 'NO EXCEPTIONS') produced defensive rather than persuasive response",
    "Did not acknowledge the deadline concern"
  ],
  "instruction_following": {
    "winner": {"score": 9, "issues": ["Minor: could have included a concrete example"]},
    "loser": {"score": 7, "issues": ["Repeated 'never skip' verbatim instead of reasoning about it"]}
  },
  "improvement_suggestions": [
    {
      "priority": "high",
      "category": "instructions",
      "suggestion": "Replace authority framing with reasoning about why TDD saves time under pressure",
      "expected_impact": "Would produce persuasive rather than defensive responses"
    }
  ],
  "output_insights": {
    "winner_execution_pattern": "Acknowledged concern -> Explained reasoning -> Proposed TDD approach",
    "loser_execution_pattern": "Cited rules -> Refused request -> Offered no alternative"
  }
}
```
````

**Step 3: Add .skill-evals/ to .gitignore**

Append to `.gitignore`:
```text
.skill-evals/
```

**Step 4: Add skill-eval to README.md**

In the skills list section of README.md, add an entry for skill-eval under the "Quality" section (between `plan-review` and the Infrastructure section).

**Step 5: Commit**
```bash
git add skills/skill-eval/references/schemas.md skills/skill-eval/scripts/__init__.py .gitignore README.md
git commit -m "feat(skill-eval): add project scaffolding and JSON schemas"
```

---

### Task 2: Port aggregate_benchmark.py from Anthropic's skill-creator

**Files:**
- Create: `skills/skill-eval/scripts/aggregate_benchmark.py`

**Verification:** `python skills/skill-eval/scripts/aggregate_benchmark.py --help` — should print usage without error

**Done when:** Script accepts a benchmark directory, discovers grading.json files under `eval-*/before|after/run-*/`, computes mean ± stddev for pass_rate/time/tokens, writes benchmark.json and benchmark.md.

**Avoid:** Don't hardcode variant names ("with_skill"/"without_skill") — use dynamic config directory discovery so before/after (or any variant name) works. Anthropic's version already does this, keep that behavior.

**Step 1: Write aggregate_benchmark.py**

Create `skills/skill-eval/scripts/aggregate_benchmark.py` — this is a direct port from Anthropic's `scripts/aggregate_benchmark.py` with updated docstring paths. The core logic (calculate_stats, load_run_results, aggregate_results, generate_benchmark, generate_markdown, main) is unchanged because dynamic config discovery already handles our before/after naming.

```python
#!/usr/bin/env python3
"""
Aggregate individual run results into benchmark summary statistics.

Reads grading.json files from run directories and produces:
- benchmark.json with mean, stddev, min, max for each metric
- benchmark.md with human-readable summary table
- delta between before and after configurations

Usage:
    python aggregate_benchmark.py <iteration_dir> --skill-name <name>

Example:
    python aggregate_benchmark.py .skill-evals/tdd/iteration-1/ --skill-name test-driven-development

Directory layout:
    <iteration_dir>/
    └── eval-{id}-{name}/
        ├── before/
        │   ├── run-1/grading.json
        │   ├── run-2/grading.json
        │   └── run-3/grading.json
        └── after/
            ├── run-1/grading.json
            ├── run-2/grading.json
            └── run-3/grading.json
"""

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path


def calculate_stats(values: list[float]) -> dict:
    """Calculate mean, stddev, min, max for a list of values."""
    if not values:
        return {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0}

    n = len(values)
    mean = sum(values) / n

    if n > 1:
        variance = sum((x - mean) ** 2 for x in values) / (n - 1)
        stddev = math.sqrt(variance)
    else:
        stddev = 0.0

    return {
        "mean": round(mean, 4),
        "stddev": round(stddev, 4),
        "min": round(min(values), 4),
        "max": round(max(values), 4),
    }


def load_run_results(benchmark_dir: Path) -> dict:
    """
    Load all run results from a benchmark directory.

    Returns dict keyed by config name (e.g. "before"/"after"),
    each containing a list of run results.
    """
    # Support both layouts: eval dirs directly under benchmark_dir, or under runs/
    runs_dir = benchmark_dir / "runs"
    if runs_dir.exists():
        search_dir = runs_dir
    elif list(benchmark_dir.glob("eval-*")):
        search_dir = benchmark_dir
    else:
        print(f"No eval directories found in {benchmark_dir} or {benchmark_dir / 'runs'}")
        return {}

    results: dict[str, list] = {}

    for eval_idx, eval_dir in enumerate(sorted(search_dir.glob("eval-*"))):
        metadata_path = eval_dir / "eval_metadata.json"
        if metadata_path.exists():
            try:
                with open(metadata_path) as mf:
                    eval_id = json.load(mf).get("eval_id", eval_idx)
            except (json.JSONDecodeError, OSError):
                eval_id = eval_idx
        else:
            try:
                eval_id = int(eval_dir.name.split("-")[1])
            except (ValueError, IndexError):
                eval_id = eval_idx

        # Discover config directories dynamically
        for config_dir in sorted(eval_dir.iterdir()):
            if not config_dir.is_dir():
                continue
            if not list(config_dir.glob("run-*")):
                continue
            config = config_dir.name
            if config not in results:
                results[config] = []

            for run_dir in sorted(config_dir.glob("run-*")):
                try:
                    run_number = int(run_dir.name.split("-")[1])
                except (ValueError, IndexError):
                    continue
                grading_file = run_dir / "grading.json"

                if not grading_file.exists():
                    print(f"Warning: grading.json not found in {run_dir}")
                    continue

                try:
                    with open(grading_file) as f:
                        grading = json.load(f)
                except json.JSONDecodeError as e:
                    print(f"Warning: Invalid JSON in {grading_file}: {e}")
                    continue

                result = {
                    "eval_id": eval_id,
                    "run_number": run_number,
                    "pass_rate": grading.get("summary", {}).get("pass_rate", 0.0),
                    "passed": grading.get("summary", {}).get("passed", 0),
                    "failed": grading.get("summary", {}).get("failed", 0),
                    "total": grading.get("summary", {}).get("total", 0),
                }

                # Extract timing from grading.json or sibling timing.json
                timing = grading.get("timing", {})
                result["time_seconds"] = timing.get("total_duration_seconds", 0.0)
                timing_file = run_dir / "timing.json"
                if result["time_seconds"] == 0.0 and timing_file.exists():
                    try:
                        with open(timing_file) as tf:
                            timing_data = json.load(tf)
                        result["time_seconds"] = timing_data.get(
                            "total_duration_seconds", 0.0
                        )
                        result["tokens"] = timing_data.get("total_tokens", 0)
                    except json.JSONDecodeError:
                        pass

                # Extract metrics if available
                metrics = grading.get("execution_metrics", {})
                result["tool_calls"] = metrics.get("total_tool_calls", 0)
                if not result.get("tokens"):
                    result["tokens"] = metrics.get("output_chars", 0)
                result["errors"] = metrics.get("errors_encountered", 0)

                # Extract expectations
                raw_expectations = grading.get("expectations", [])
                for exp in raw_expectations:
                    if "text" not in exp or "passed" not in exp:
                        print(
                            f"Warning: expectation in {grading_file} missing "
                            f"required fields (text, passed, evidence): {exp}"
                        )
                result["expectations"] = raw_expectations

                # Extract notes
                notes_summary = grading.get("user_notes_summary", {})
                notes = []
                notes.extend(notes_summary.get("uncertainties", []))
                notes.extend(notes_summary.get("needs_review", []))
                notes.extend(notes_summary.get("workarounds", []))
                result["notes"] = notes

                results[config].append(result)

    return results


def aggregate_results(results: dict) -> dict:
    """Aggregate run results into summary statistics per configuration."""
    run_summary = {}
    configs = list(results.keys())

    for config in configs:
        runs = results.get(config, [])
        if not runs:
            run_summary[config] = {
                "pass_rate": {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0},
                "time_seconds": {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0},
                "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0},
            }
            continue

        pass_rates = [r["pass_rate"] for r in runs]
        times = [r["time_seconds"] for r in runs]
        tokens = [r.get("tokens", 0) for r in runs]

        run_summary[config] = {
            "pass_rate": calculate_stats(pass_rates),
            "time_seconds": calculate_stats(times),
            "tokens": calculate_stats(tokens),
        }

    # Delta between first two configs
    if len(configs) >= 2:
        primary = run_summary.get(configs[0], {})
        baseline = run_summary.get(configs[1], {})
    else:
        primary = run_summary.get(configs[0], {}) if configs else {}
        baseline = {}

    delta_pass = primary.get("pass_rate", {}).get("mean", 0) - baseline.get(
        "pass_rate", {}
    ).get("mean", 0)
    delta_time = primary.get("time_seconds", {}).get("mean", 0) - baseline.get(
        "time_seconds", {}
    ).get("mean", 0)
    delta_tokens = primary.get("tokens", {}).get("mean", 0) - baseline.get(
        "tokens", {}
    ).get("mean", 0)

    run_summary["delta"] = {
        "pass_rate": f"{delta_pass:+.2f}",
        "time_seconds": f"{delta_time:+.1f}",
        "tokens": f"{delta_tokens:+.0f}",
    }

    return run_summary


def generate_benchmark(
    benchmark_dir: Path, skill_name: str = "", skill_path: str = ""
) -> dict:
    """Generate complete benchmark.json from run results."""
    results = load_run_results(benchmark_dir)
    run_summary = aggregate_results(results)

    runs = []
    for config in results:
        for result in results[config]:
            runs.append(
                {
                    "eval_id": result["eval_id"],
                    "configuration": config,
                    "run_number": result["run_number"],
                    "result": {
                        "pass_rate": result["pass_rate"],
                        "passed": result["passed"],
                        "failed": result["failed"],
                        "total": result["total"],
                        "time_seconds": result["time_seconds"],
                        "tokens": result.get("tokens", 0),
                        "tool_calls": result.get("tool_calls", 0),
                        "errors": result.get("errors", 0),
                    },
                    "expectations": result["expectations"],
                    "notes": result["notes"],
                }
            )

    eval_ids = sorted(
        set(r["eval_id"] for config in results.values() for r in config)
    )

    return {
        "metadata": {
            "skill_name": skill_name or "<skill-name>",
            "skill_path": skill_path or "<path/to/skill>",
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "evals_run": eval_ids,
            "runs_per_configuration": 3,
        },
        "runs": runs,
        "run_summary": run_summary,
        "notes": [],
    }


def generate_markdown(benchmark: dict) -> str:
    """Generate human-readable benchmark.md."""
    metadata = benchmark["metadata"]
    run_summary = benchmark["run_summary"]

    configs = [k for k in run_summary if k != "delta"]
    config_a = configs[0] if len(configs) >= 1 else "config_a"
    config_b = configs[1] if len(configs) >= 2 else "config_b"
    label_a = config_a.replace("_", " ").title()
    label_b = config_b.replace("_", " ").title()

    lines = [
        f"# Skill Benchmark: {metadata['skill_name']}",
        "",
        f"**Date**: {metadata['timestamp']}",
        f"**Evals**: {', '.join(map(str, metadata['evals_run']))} "
        f"({metadata['runs_per_configuration']} runs each per configuration)",
        "",
        "## Summary",
        "",
        f"| Metric | {label_a} | {label_b} | Delta |",
        "|--------|------------|---------------|-------|",
    ]

    a_summary = run_summary.get(config_a, {})
    b_summary = run_summary.get(config_b, {})
    delta = run_summary.get("delta", {})

    a_pr = a_summary.get("pass_rate", {})
    b_pr = b_summary.get("pass_rate", {})
    lines.append(
        f"| Pass Rate | {a_pr.get('mean', 0)*100:.0f}% ± "
        f"{a_pr.get('stddev', 0)*100:.0f}% | "
        f"{b_pr.get('mean', 0)*100:.0f}% ± "
        f"{b_pr.get('stddev', 0)*100:.0f}% | "
        f"{delta.get('pass_rate', '—')} |"
    )

    a_time = a_summary.get("time_seconds", {})
    b_time = b_summary.get("time_seconds", {})
    lines.append(
        f"| Time | {a_time.get('mean', 0):.1f}s ± "
        f"{a_time.get('stddev', 0):.1f}s | "
        f"{b_time.get('mean', 0):.1f}s ± "
        f"{b_time.get('stddev', 0):.1f}s | "
        f"{delta.get('time_seconds', '—')}s |"
    )

    a_tok = a_summary.get("tokens", {})
    b_tok = b_summary.get("tokens", {})
    lines.append(
        f"| Tokens | {a_tok.get('mean', 0):.0f} ± "
        f"{a_tok.get('stddev', 0):.0f} | "
        f"{b_tok.get('mean', 0):.0f} ± "
        f"{b_tok.get('stddev', 0):.0f} | "
        f"{delta.get('tokens', '—')} |"
    )

    if benchmark.get("notes"):
        lines.extend(["", "## Notes", ""])
        for note in benchmark["notes"]:
            lines.append(f"- {note}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate benchmark run results into summary statistics"
    )
    parser.add_argument(
        "benchmark_dir", type=Path, help="Path to the iteration directory"
    )
    parser.add_argument("--skill-name", default="", help="Name of the skill")
    parser.add_argument("--skill-path", default="", help="Path to the skill")
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Output path for benchmark.json (default: <benchmark_dir>/benchmark.json)",
    )

    args = parser.parse_args()

    if not args.benchmark_dir.exists():
        print(f"Directory not found: {args.benchmark_dir}")
        sys.exit(1)

    benchmark = generate_benchmark(args.benchmark_dir, args.skill_name, args.skill_path)

    output_json = args.output or (args.benchmark_dir / "benchmark.json")
    output_md = output_json.with_suffix(".md")

    with open(output_json, "w") as f:
        json.dump(benchmark, f, indent=2)
    print(f"Generated: {output_json}")

    markdown = generate_markdown(benchmark)
    with open(output_md, "w") as f:
        f.write(markdown)
    print(f"Generated: {output_md}")

    run_summary = benchmark["run_summary"]
    configs = [k for k in run_summary if k != "delta"]
    delta = run_summary.get("delta", {})

    print("\nSummary:")
    for config in configs:
        pr = run_summary[config]["pass_rate"]["mean"]
        label = config.replace("_", " ").title()
        print(f"  {label}: {pr*100:.1f}% pass rate")
    print(f"  Delta:  {delta.get('pass_rate', '—')}")


if __name__ == "__main__":
    main()
```

**Step 2: Verify script loads and --help works**
```bash
python skills/skill-eval/scripts/aggregate_benchmark.py --help
```
Expect: argparse usage output, no errors.

**Step 3: Functional smoke test with mock data**

Create a temporary mock directory structure, run the script, verify output:

```bash
# Create mock grading data
MOCK_DIR=$(mktemp -d)
mkdir -p "$MOCK_DIR/eval-1-test/after/run-1" "$MOCK_DIR/eval-1-test/before/run-1"

# Mock grading.json for after variant
cat > "$MOCK_DIR/eval-1-test/after/run-1/grading.json" << 'GRADE'
{
  "expectations": [{"text": "Test assertion", "passed": true, "evidence": "Found"}],
  "summary": {"passed": 1, "failed": 0, "total": 1, "pass_rate": 1.0},
  "timing": {"total_duration_seconds": 2.5}
}
GRADE

# Mock grading.json for before variant
cat > "$MOCK_DIR/eval-1-test/before/run-1/grading.json" << 'GRADE'
{
  "expectations": [{"text": "Test assertion", "passed": false, "evidence": "Not found"}],
  "summary": {"passed": 0, "failed": 1, "total": 1, "pass_rate": 0.0},
  "timing": {"total_duration_seconds": 1.8}
}
GRADE

python skills/skill-eval/scripts/aggregate_benchmark.py "$MOCK_DIR" --skill-name test
cat "$MOCK_DIR/benchmark.json" | python -m json.tool | head -20
cat "$MOCK_DIR/benchmark.md"
rm -rf "$MOCK_DIR"
```

Expect: benchmark.json with after pass_rate 1.0, before pass_rate 0.0, delta +1.00.

**Step 4: Commit**
```bash
git add skills/skill-eval/scripts/aggregate_benchmark.py
git commit -m "feat(skill-eval): port aggregate_benchmark.py from skill-creator"
```

---

### Task 3: Create run_eval.py for Behavioral Output Evaluation

**Files:**
- Create: `skills/skill-eval/scripts/run_eval.py`

**Verification:** `python skills/skill-eval/scripts/run_eval.py --help` — should print usage without error

**Done when:** Script accepts `--evals-path`, `--output-dir`, `--variant`, `--skill-path` (optional), `--runs`, `--model`; creates directory structure; invokes `claude -p` with correct env vars; captures output text and timing.

**Avoid:** Don't use `--output-format text` — use `--output-format json` instead, because the JSON response includes timing metadata (duration_ms, cost_usd) that `text` mode doesn't provide. This also resolves the design doc's stderr gotcha: `json` mode returns structured JSON to stdout (which the code parses via `result.stdout`), unlike `text` mode where output goes to stderr. Design improvement over the original specification.

**Step 1: Write run_eval.py**

Create `skills/skill-eval/scripts/run_eval.py`:

```python
#!/usr/bin/env python3
"""
Run skill evaluation prompts via claude -p.

For each eval in evals.json, spawns claude -p with the skill loaded as
system prompt. Captures output text and timing data per run.

Usage:
    python run_eval.py \\
      --evals-path .skill-evals/tdd/evals.json \\
      --output-dir .skill-evals/tdd/iteration-1/ \\
      --variant after \\
      --skill-path skills/test-driven-development/SKILL.md \\
      --runs 3

Subprocess environment:
    - CLAUDECODE env var removed (allows nested claude -p)
    - CLAUDE_SKIP_MEMORY=1 (suppresses memory injection)
    - --output-format json (captures timing in response)
    - --allowedTools "" (pure text, no tool use)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


def build_claude_command(
    skill_path: str | None = None, model: str | None = None
) -> list[str]:
    """Build the claude -p command with appropriate flags."""
    cmd = ["claude", "-p", "--output-format", "json", "--allowedTools", ""]
    if skill_path:
        content = Path(skill_path).read_text()
        cmd.extend(["--system-prompt", content])
    if model:
        cmd.extend(["--model", model])
    return cmd


def build_env() -> dict:
    """Build environment for claude -p subprocess.

    Removes CLAUDECODE to allow nested sessions.
    Sets CLAUDE_SKIP_MEMORY to suppress memory injection.
    """
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    env["CLAUDE_SKIP_MEMORY"] = "1"
    return env


def slugify(text: str) -> str:
    """Convert text to URL-safe slug for directory naming."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text[:50]


def run_single(cmd: list[str], prompt: str, env: dict, timeout: int = 120) -> dict:
    """Run a single claude -p invocation and return parsed result."""
    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {
            "result": "",
            "is_error": True,
            "duration_ms": timeout * 1000,
            "cost_usd": 0,
            "num_turns": 0,
            "error": f"Timeout after {timeout}s",
        }

    if result.returncode != 0:
        return {
            "result": result.stdout or "",
            "is_error": True,
            "duration_ms": 0,
            "cost_usd": 0,
            "num_turns": 0,
            "error": result.stderr[:1000] if result.stderr else "Non-zero exit code",
        }

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        # If JSON parsing fails, treat raw stdout as the result
        return {
            "result": result.stdout,
            "is_error": False,
            "duration_ms": 0,
            "cost_usd": 0,
            "num_turns": 0,
        }


def run_eval(
    evals_path: Path,
    output_dir: Path,
    variant: str,
    skill_path: str | None = None,
    runs: int = 3,
    model: str | None = None,
    timeout: int = 120,
):
    """Run all evals for a single variant."""
    with open(evals_path) as f:
        evals_data = json.load(f)

    cmd = build_claude_command(skill_path, model)
    env = build_env()

    skill_label = Path(skill_path).parent.name if skill_path else "no-skill"
    print(f"\nRunning {len(evals_data['evals'])} evals x {runs} runs [{variant}: {skill_label}]")

    for eval_item in evals_data["evals"]:
        eval_id = eval_item["id"]
        eval_name = eval_item.get("name", f"eval-{eval_id}")
        slug = slugify(eval_name)
        eval_dir_name = f"eval-{eval_id}-{slug}"

        variant_dir = output_dir / eval_dir_name / variant
        variant_dir.mkdir(parents=True, exist_ok=True)

        # Write eval_metadata.json (once per eval, shared across variants)
        metadata_path = output_dir / eval_dir_name / "eval_metadata.json"
        if not metadata_path.exists():
            metadata = {
                "eval_id": eval_id,
                "eval_name": eval_name,
                "prompt": eval_item["prompt"],
                "expectations": eval_item.get("expectations", []),
            }
            with open(metadata_path, "w") as f:
                json.dump(metadata, f, indent=2)

        prompt = eval_item["prompt"]

        for run_num in range(1, runs + 1):
            run_dir = variant_dir / f"run-{run_num}"
            run_dir.mkdir(parents=True, exist_ok=True)

            print(f"  [{variant}] {eval_name} run-{run_num}...", end=" ", flush=True)

            start = time.time()
            response = run_single(cmd, prompt, env, timeout)
            wall_time = time.time() - start

            # Write output text
            output_text = response.get("result", "")
            with open(run_dir / "output.txt", "w") as f:
                f.write(output_text)

            # Write timing
            timing = {
                "duration_ms": response.get("duration_ms", 0),
                "wall_time_seconds": round(wall_time, 2),
                "cost_usd": response.get("cost_usd", 0),
                "num_turns": response.get("num_turns", 0),
                "is_error": response.get("is_error", False),
                "total_duration_seconds": round(wall_time, 2),
            }
            if response.get("error"):
                timing["error"] = response["error"]

            with open(run_dir / "timing.json", "w") as f:
                json.dump(timing, f, indent=2)

            status = "ERROR" if response.get("is_error") else "OK"
            print(f"{status} ({wall_time:.1f}s)")

    print(f"\nResults: {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Run skill evaluations via claude -p"
    )
    parser.add_argument(
        "--evals-path", type=Path, required=True, help="Path to evals.json"
    )
    parser.add_argument(
        "--output-dir", type=Path, required=True, help="Output iteration directory"
    )
    parser.add_argument(
        "--variant", required=True, help="Variant name (before/after)"
    )
    parser.add_argument(
        "--skill-path", help="Path to SKILL.md (omit for no-skill baseline)"
    )
    parser.add_argument(
        "--runs", type=int, default=3, help="Runs per eval (default: 3)"
    )
    parser.add_argument(
        "--model", help="Model for eval subject (default: system default)"
    )
    parser.add_argument(
        "--timeout", type=int, default=120, help="Timeout per run in seconds"
    )

    args = parser.parse_args()

    if not args.evals_path.exists():
        print(f"Error: evals file not found: {args.evals_path}")
        sys.exit(1)

    if args.skill_path and not Path(args.skill_path).exists():
        print(f"Error: skill file not found: {args.skill_path}")
        sys.exit(1)

    run_eval(
        evals_path=args.evals_path,
        output_dir=args.output_dir,
        variant=args.variant,
        skill_path=args.skill_path,
        runs=args.runs,
        model=args.model,
        timeout=args.timeout,
    )


if __name__ == "__main__":
    main()
```

**Step 2: Verify script loads and --help works**
```bash
python skills/skill-eval/scripts/run_eval.py --help
```
Expect: argparse usage with all flags documented.

**Step 3: Verify build_env and build_claude_command logic**

Quick inline test (no pytest needed):
```bash
python -c "
import sys; sys.path.insert(0, 'skills/skill-eval/scripts')
from run_eval import build_env, build_claude_command, slugify

env = build_env()
assert 'CLAUDECODE' not in env, 'CLAUDECODE should be removed'
assert env.get('CLAUDE_SKIP_MEMORY') == '1', 'CLAUDE_SKIP_MEMORY should be set'

cmd = build_claude_command(None, None)
assert '--system-prompt' not in cmd, 'No skill = no system prompt'
assert '--allowedTools' in cmd

assert slugify('Deadline Pressure!') == 'deadline-pressure'
assert slugify('Test  with   spaces') == 'test-with-spaces'

print('All checks passed')
"
```

**Step 4: Commit**
```bash
git add skills/skill-eval/scripts/run_eval.py
git commit -m "feat(skill-eval): create run_eval.py for behavioral output evaluation"
```

---

### Task 4: Adapt Grader Agent Prompt for Text-Only Evaluation

**Files:**
- Create: `skills/skill-eval/agents/grader.md`

**Verification:** `wc -w skills/skill-eval/agents/grader.md` — file exists and has content

**Done when:** Grader prompt handles text output (output.txt files), evaluates assertions with cited evidence, self-critiques assertion quality, outputs grading.json matching the schema.

**Avoid:** Don't include executor-specific sections (transcript reading, user_notes.md, execution_metrics) — our eval subjects produce pure text via `claude -p --allowedTools ""`, not tool-use transcripts. The grader reads `output.txt` files, not file trees.

**Step 1: Write grader.md**

Create `skills/skill-eval/agents/grader.md`:

````markdown
# Grader Agent

Evaluate behavioral assertions against skill evaluation outputs.

## Role

Grade each run's text output against predefined expectations. Provide cited evidence for every verdict. Simultaneously critique the assertions themselves — a passing grade on a weak assertion creates false confidence.

## Inputs

- **expectations**: List of assertion strings to evaluate
- **run_dir**: Directory containing `output.txt` (the claude -p response)
- **output_path**: Where to write `grading.json`

## Process

### Step 1: Read the Output

Read `{run_dir}/output.txt` completely. Note the response's tone, structure, key claims, and behavioral patterns.

### Step 2: Evaluate Each Assertion

For each expectation:

1. **Search for evidence** in the output text
2. **Determine verdict**:
   - **PASS**: Clear evidence the expectation is true AND the evidence reflects genuine behavioral compliance, not surface-level keyword matching
   - **FAIL**: No evidence, contradictory evidence, or only superficial compliance
3. **Cite the evidence**: Quote the specific text supporting your verdict

### Step 3: Extract and Verify Claims

Beyond predefined expectations, extract implicit claims from the output:

- **Factual claims**: "TDD reduces bug rates by 40%" — verify if substantiated
- **Process claims**: "Start by writing the test" — verify the recommended workflow
- **Quality claims**: "This approach is more maintainable" — evaluate justification

Flag unverifiable claims.

### Step 4: Critique the Assertions

After grading, assess whether the assertions themselves are effective. Only surface suggestions when there is a clear gap. Good suggestions test meaningful outcomes — assertions that are hard to satisfy without genuinely doing the work.

Worth raising:
- An assertion that passed but would also pass for a clearly wrong output
- An important outcome with no assertion covering it
- An assertion that cannot actually be verified from text output

### Step 5: Write Grading Results

Save to `{output_path}`:

```json
{
  "expectations": [
    {
      "text": "Refuses to skip TDD",
      "passed": true,
      "evidence": "Response states: 'Skipping tests under deadline pressure is exactly when...'"
    }
  ],
  "summary": {
    "passed": 2,
    "failed": 1,
    "total": 3,
    "pass_rate": 0.67
  },
  "timing": {
    "total_duration_seconds": 0
  },
  "claims": [
    {
      "claim": "Response recommends writing tests first",
      "type": "process",
      "verified": true,
      "evidence": "Step 1 in response explicitly says 'write the failing test first'"
    }
  ],
  "eval_feedback": {
    "suggestions": [
      {
        "assertion": "Refuses to skip TDD",
        "reason": "Too broad — any mention of testing would pass. Consider checking that the refusal addresses the specific reason given (deadline pressure)."
      }
    ],
    "overall": "Assertions check presence but not reasoning quality."
  }
}
```

**Required fields in expectations array:** `text`, `passed`, `evidence` — the aggregate script depends on these exact field names.

If `{run_dir}/timing.json` exists, read it and include timing data in the output.

## Grading Criteria

**PASS when:**
- Output clearly demonstrates the expectation is true
- Specific text can be cited as evidence
- The evidence reflects genuine behavioral compliance, not just keyword presence

**FAIL when:**
- No evidence found
- Evidence contradicts the expectation
- Evidence is superficial (technically matches keywords but misses the behavioral intent)
- The output appears to satisfy the assertion by coincidence rather than understanding

**When uncertain:** Burden of proof is on the expectation.

## Guidelines

- **Be objective**: Base verdicts on evidence, not assumptions
- **Be specific**: Quote exact text supporting your verdict
- **Be consistent**: Same standard for each expectation
- **No partial credit**: Each expectation is pass or fail
- **Keep eval feedback bar high**: Flag things the eval author would say "good catch" about, not nitpicks
````

**Step 2: Verify file exists and structure**
```bash
test -f skills/skill-eval/agents/grader.md && grep -c "## " skills/skill-eval/agents/grader.md
```
Expect: file exists, has multiple sections.

**Step 3: Commit**
```bash
git add skills/skill-eval/agents/grader.md
git commit -m "feat(skill-eval): add grader agent prompt for assertion-based evaluation"
```

---

### Task 5: Adapt Comparator Agent Prompt for Blind A/B Comparison

**Files:**
- Create: `skills/skill-eval/agents/comparator.md`

**Verification:** `wc -w skills/skill-eval/agents/comparator.md` — file exists and has content

**Done when:** Comparator prompt receives two text outputs as A/B without labels, scores on Content (1-5) + Structure (1-5) → Overall (1-10), determines winner with cited reasoning, outputs comparison.json matching the schema.

**Avoid:** Don't reference file trees or directories — our outputs are single text files (output.txt), not multi-file output directories. Adapt all "examine files" language to "read text output."

**Step 1: Write comparator.md**

Create `skills/skill-eval/agents/comparator.md`:

````markdown
# Blind Comparator Agent

Compare two skill outputs WITHOUT knowing which version produced them.

## Role

Judge which output better accomplishes the eval task. You receive outputs labeled A and B but do NOT know which skill version produced which. This prevents bias. Your judgment is based purely on output quality.

## Inputs

- **output_a**: Text content of the first output
- **output_b**: Text content of the second output
- **eval_prompt**: The original task prompt
- **expectations**: List of assertions to check (optional)
- **output_path**: Where to write comparison.json

## Process

### Step 1: Read Both Outputs

Read output A and output B completely. Note tone, structure, depth, and behavioral patterns of each.

### Step 2: Understand the Task

Read the eval_prompt. Identify what the task requires and what would distinguish a good response from a poor one for this specific scenario.

### Step 3: Generate Evaluation Rubric

Based on the task, generate a rubric with two dimensions:

**Content Rubric** (what the output says):
| Criterion | 1 (Poor) | 3 (Acceptable) | 5 (Excellent) |
|-----------|----------|----------------|---------------|
| Correctness | Major errors or wrong advice | Minor inaccuracies | Fully correct |
| Completeness | Missing key elements | Mostly complete | All elements addressed |
| Accuracy | Significant inaccuracies | Minor issues | Accurate throughout |

**Structure Rubric** (how the output is organized):
| Criterion | 1 (Poor) | 3 (Acceptable) | 5 (Excellent) |
|-----------|----------|----------------|---------------|
| Organization | Disorganized, hard to follow | Reasonably structured | Clear, logical flow |
| Formatting | Inconsistent | Mostly consistent | Professional, polished |
| Usability | Difficult to act on | Usable with effort | Easy to follow and apply |

Adapt criteria to the specific task type (behavioral skill advice, code guidance, workflow instruction, etc.).

### Step 4: Evaluate Each Output Against the Rubric

For each output (A and B):
1. Score each criterion (1-5)
2. Calculate Content score (average of content criteria)
3. Calculate Structure score (average of structure criteria)
4. Calculate Overall score: Content + Structure sum (1-10 range)

### Step 5: Check Assertions (if provided)

If expectations are provided, check each against both outputs. Use as secondary evidence, not the primary decision factor.

### Step 6: Determine the Winner

Compare based on (priority order):
1. **Primary**: Overall rubric score
2. **Secondary**: Assertion pass rates (if applicable)
3. **Tiebreaker**: If truly equal, declare TIE

Be decisive — ties should be rare.

### Step 7: Write Comparison Results

Save to `{output_path}`:

```json
{
  "winner": "A",
  "reasoning": "Output A provides nuanced explanation addressing the specific scenario. Output B gives generic advice without engaging with the context.",
  "rubric": {
    "A": {
      "content": {"correctness": 5, "completeness": 5, "accuracy": 4},
      "structure": {"organization": 4, "formatting": 4, "usability": 4},
      "content_score": 4.7,
      "structure_score": 4.0,
      "overall_score": 8.7
    },
    "B": {
      "content": {"correctness": 3, "completeness": 2, "accuracy": 3},
      "structure": {"organization": 3, "formatting": 3, "usability": 3},
      "content_score": 2.7,
      "structure_score": 3.0,
      "overall_score": 5.7
    }
  },
  "output_quality": {
    "A": {
      "score": 9,
      "strengths": ["Addresses scenario directly", "Provides reasoning"],
      "weaknesses": ["Slightly verbose"]
    },
    "B": {
      "score": 6,
      "strengths": ["Mentions the topic"],
      "weaknesses": ["Generic", "Does not engage with context"]
    }
  }
}
```

Include `expectation_results` only if expectations were provided.

## Guidelines

- **Stay blind**: Do NOT try to infer which version produced which output
- **Be specific**: Cite examples when explaining strengths and weaknesses
- **Be decisive**: Choose a winner unless outputs are genuinely equivalent
- **Output quality first**: Assertions are secondary to overall task completion
- **Handle edge cases**: If both fail, pick the one that fails less badly
````

**Step 2: Verify file exists**
```bash
test -f skills/skill-eval/agents/comparator.md && echo "PASS"
```

**Step 3: Commit**
```bash
git add skills/skill-eval/agents/comparator.md
git commit -m "feat(skill-eval): add blind comparator agent for A/B evaluation"
```

---

### Task 6: Adapt Analyzer Agent Prompt for Post-Hoc and Benchmark Analysis

**Files:**
- Create: `skills/skill-eval/agents/analyzer.md`

**Verification:** `wc -w skills/skill-eval/agents/analyzer.md` — file exists and has content

**Done when:** Analyzer has both modes: (1) post-comparison analysis with instruction-following scores and improvement suggestions, (2) benchmark pattern analysis surfacing non-discriminating assertions and variance. Outputs analysis.json matching schema.

**Avoid:** Don't reference "transcripts" — our eval outputs are text responses, not tool-use transcripts. Replace all transcript-reading instructions with output-reading.

**Step 1: Write analyzer.md**

Create `skills/skill-eval/agents/analyzer.md`:

````markdown
# Analyzer Agent

Two modes: post-hoc comparison analysis, and benchmark pattern analysis.

---

## Mode 1: Post-Hoc Comparison Analysis

Analyze blind comparison results to understand WHY the winner won and generate improvement suggestions.

### Inputs

- **winner**: "A" or "B" (from blind comparison)
- **winner_skill_path**: Path to the SKILL.md that produced the winning output
- **winner_output**: The winning output text (or path to output.txt)
- **loser_skill_path**: Path to the SKILL.md that produced the losing output
- **loser_output**: The losing output text (or path to output.txt)
- **comparison_result_path**: Path to comparison.json
- **output_path**: Where to save analysis.json

### Process

#### Step 1: Read Comparison Result
Read comparison.json. Note the winner, reasoning, and scores.

#### Step 2: Read Both Skills
Read both SKILL.md files. Identify structural differences:
- Instruction clarity and specificity
- Framing approach (reasoning-based vs. authority-based)
- Example coverage
- Edge case handling

#### Step 3: Read Both Outputs
Read the winning and losing outputs. Compare:
- How closely did each follow their skill's instructions?
- What behavioral patterns emerged?
- Where did the loser diverge from effective behavior?

#### Step 4: Analyze Instruction Following
For each output, evaluate:
- Did the response follow the skill's explicit guidance?
- Were there missed opportunities to leverage skill content?
- Did the response add unnecessary elements not in the skill?

Score instruction following 1-10 with specific issues noted.

#### Step 5: Identify Winner Strengths
What made the winner better? Be specific — quote from skills and outputs.

#### Step 6: Identify Loser Weaknesses
What held the loser back? Focus on skill-level issues (ambiguous instructions, missing guidance), not model-level issues.

#### Step 7: Generate Improvement Suggestions
Produce actionable suggestions for improving the losing skill. Prioritize by impact — which changes would most likely have changed the outcome?

Categories: `instructions`, `tools`, `examples`, `error_handling`, `structure`, `references`
Priority: `high` (would change outcome), `medium` (improves quality), `low` (marginal)

#### Step 8: Write Analysis

Save to `{output_path}`:

```json
{
  "comparison_summary": {
    "winner": "A",
    "winner_skill": "path/to/winner/SKILL.md",
    "loser_skill": "path/to/loser/SKILL.md",
    "comparator_reasoning": "Brief summary"
  },
  "winner_strengths": [
    "Reasoning-based framing led to persuasive response"
  ],
  "loser_weaknesses": [
    "Authority-based framing produced defensive rather than persuasive response"
  ],
  "instruction_following": {
    "winner": {"score": 9, "issues": ["Minor: could include concrete example"]},
    "loser": {"score": 6, "issues": ["Repeated rules verbatim instead of reasoning"]}
  },
  "improvement_suggestions": [
    {
      "priority": "high",
      "category": "instructions",
      "suggestion": "Replace authority framing with reasoning about why the practice matters",
      "expected_impact": "Would produce persuasive rather than defensive responses"
    }
  ],
  "output_insights": {
    "winner_execution_pattern": "Acknowledged concern -> Explained reasoning -> Proposed approach",
    "loser_execution_pattern": "Cited rules -> Refused -> No alternative offered"
  }
}
```

### Guidelines
- **Be specific**: Quote from skills and outputs
- **Be actionable**: Concrete changes, not vague advice
- **Focus on skill improvements**: Goal is improving the losing skill, not critiquing the model
- **Consider causation**: Did the skill weakness actually cause the worse output?
- **Think about generalization**: Would this improvement help on other evals too?

---

## Mode 2: Benchmark Pattern Analysis

Surface patterns that aggregate metrics hide.

### Inputs

- **benchmark_data_path**: Path to benchmark.json
- **skill_path**: Path to the skill being evaluated
- **output_path**: Where to save notes (JSON array of strings)

### Process

#### Step 1: Read Benchmark Data
Read benchmark.json. Note configurations, run counts, and aggregate summaries.

#### Step 2: Analyze Per-Assertion Patterns
For each expectation across all runs:
- **Always passes both configs**: May not differentiate skill value (non-discriminating)
- **Always fails both configs**: May be broken or beyond capability
- **Always passes after, fails before**: Skill clearly adds value here
- **Always fails after, passes before**: Skill may be hurting
- **High variance**: Flaky expectation or non-deterministic behavior

#### Step 3: Analyze Cross-Eval Patterns
- Are certain eval types consistently harder/easier?
- Do some evals show high variance while others are stable?
- Surprising results that contradict expectations?

#### Step 4: Analyze Timing Patterns
- Does the skill significantly change execution time?
- High variance in resource usage?
- Outlier runs that skew aggregates?

#### Step 5: Write Notes
Save to `{output_path}` as JSON array:

```json
[
  "Assertion 'Refuses to skip' passes 100% in both configs - non-discriminating",
  "Eval 3 shows high variance (50% +/- 40%) - run 2 had unusual failure",
  "After variant adds 0.7s average but improves pass rate by 50%",
  "All before runs for eval 1 produced generic responses ignoring the scenario"
]
```

### Guidelines
- Report what you observe in the data
- Be specific about which evals, assertions, or runs
- Note patterns that aggregates would hide
- Do NOT suggest skill improvements (that is for post-hoc analysis mode)
````

**Step 2: Verify file exists with both modes**
```bash
test -f skills/skill-eval/agents/analyzer.md && grep -c "## Mode" skills/skill-eval/agents/analyzer.md
```
Expect: file exists, 2 mode sections.

**Step 3: Commit**
```bash
git add skills/skill-eval/agents/analyzer.md
git commit -m "feat(skill-eval): add analyzer agent for post-hoc and benchmark analysis"
```

---

### Task 7: Create SKILL.md Workflow Orchestration

**Files:**
- Create: `skills/skill-eval/SKILL.md`

**Verification:** `wc -w skills/skill-eval/SKILL.md | awk '{print ($1 <= 1000) ? "PASS: "$1"w" : "FAIL: "$1"w (over 1000)"}'`

**Done when:** SKILL.md under 1,000 words with complete 8-step workflow, proper frontmatter description (trigger-condition-only), references to agent prompts via `**See:**`, and correct script invocation commands.

**Avoid:** Don't include agent prompt content inline in SKILL.md — reference via `**See:** agents/grader.md`. Don't include workflow summaries in the description — trigger condition only. Don't exceed 1,000 words — the entire value is in concise orchestration.

**Step 1: Write SKILL.md**

Create `skills/skill-eval/SKILL.md`:

````markdown
---
name: skill-eval
description: Use when evaluating skill output quality, comparing skill versions, running behavioral evals, benchmarking a skill, or when triggered by /skill-eval
---

# Skill Evaluation

Evaluate skill output quality with assertion-based grading, blind before/after comparison, and variance analysis across 3 runs per scenario.

## Setup

1. **Identify target** and what "before" represents:
   - New skill: before = no skill (`type: "none"`)
   - Improvement: before = snapshot of previous version
   - Snapshot before editing: `cp -r skills/{name} .skill-evals/{name}/snapshot-before/`

2. **Check for evals.json** at `.skill-evals/{name}/evals.json`. If none, create interactively — 2-3 realistic prompts including adversarial scenarios (deadline pressure, "skip this step", ambiguous requirements). Each eval needs `id`, `name`, `prompt`, and `expectations`.

3. **Write config.json** for this iteration at `.skill-evals/{name}/iteration-N/config.json`:
   ```json
   {
     "before": {"label": "v1", "type": "skill", "skill_path": ".skill-evals/{name}/snapshot-before/SKILL.md"},
     "after": {"label": "v2", "type": "skill", "skill_path": "skills/{name}/SKILL.md"}
   }
   ```

**See:** references/schemas.md for all JSON formats.

## Run Evals

Spawn both variants simultaneously — don't run before first then after:

```bash
# After variant
python skills/skill-eval/scripts/run_eval.py \
  --evals-path .skill-evals/{name}/evals.json \
  --output-dir .skill-evals/{name}/iteration-N/ \
  --variant after \
  --skill-path skills/{name}/SKILL.md \
  --runs 3

# Before variant
python skills/skill-eval/scripts/run_eval.py \
  --evals-path .skill-evals/{name}/evals.json \
  --output-dir .skill-evals/{name}/iteration-N/ \
  --variant before \
  --skill-path .skill-evals/{name}/snapshot-before/SKILL.md \
  --runs 3
```

For no-skill baseline, omit `--skill-path`.

Each eval creates: `.skill-evals/{name}/iteration-N/eval-{id}-{slug}/{variant}/run-{n}/output.txt` and `timing.json`.

## Draft Assertions

While runs execute, draft or refine assertions in evals.json. Good assertions are objectively verifiable, descriptively named, and test behavioral outcomes (not surface compliance). The grader flags trivially-satisfied assertions.

## Grade

**See:** agents/grader.md

Spawn a grader subagent per eval. For each run, the grader reads `output.txt`, evaluates each assertion with cited evidence, self-critiques assertion quality, and writes `grading.json` per run directory.

PASS requires genuine task completion with cited evidence, not keyword matching.

## Aggregate

```bash
python skills/skill-eval/scripts/aggregate_benchmark.py \
  .skill-evals/{name}/iteration-N \
  --skill-name {name}
```

Produces `benchmark.json` (pass_rate, time with mean ± stddev, delta) and `benchmark.md`.

## Analyze Benchmark

**See:** agents/analyzer.md (Mode 2: Benchmark Pattern Analysis)

Spawn analyzer subagent to surface patterns aggregates hide: non-discriminating assertions (always pass), high-variance evals (flaky), time tradeoffs.

## Blind Comparison

**See:** agents/comparator.md

Spawn comparator subagent with representative outputs from before and after WITHOUT revealing which is which. Scores Content (1-5) + Structure (1-5) → Overall (1-10). Saves `comparison.json`.

## Post-Hoc Analysis

**See:** agents/analyzer.md (Mode 1: Post-Hoc Comparison Analysis)

Spawn analyzer with comparison results + both SKILL.md files. Unblinds results, identifies why winner won, scores instruction-following (1-10), generates prioritized improvement suggestions. Saves `analysis.json`.

## Report

Present to user:
- Pass rates per variant with variance (mean ± stddev)
- Blind comparison winner + reasoning
- Improvement suggestions (prioritized High/Medium/Low)
- Assertion quality feedback (strengthen/drop recommendations)

## Iterating

Edit skill → snapshot as new "before" → rerun into `iteration-N+1/` → repeat until satisfied.
````

**Step 2: Verify word count under 1,000**
```bash
wc -w skills/skill-eval/SKILL.md
```
Expect: under 1,000 words.

**Step 3: Verify all referenced files exist**
```bash
test -f skills/skill-eval/agents/grader.md && \
test -f skills/skill-eval/agents/comparator.md && \
test -f skills/skill-eval/agents/analyzer.md && \
test -f skills/skill-eval/scripts/run_eval.py && \
test -f skills/skill-eval/scripts/aggregate_benchmark.py && \
test -f skills/skill-eval/references/schemas.md && \
echo "All referenced files exist"
```

**Step 4: Commit**
```bash
git add skills/skill-eval/SKILL.md
git commit -m "feat(skill-eval): add SKILL.md workflow orchestration"
```

---

## Completion Report

**Date:** 2026-03-03
**All 7 tasks completed successfully.**

### Summary

Created the skill-eval skill with the following components:

| Component | File | Purpose |
|-----------|------|---------|
| Schemas | `references/schemas.md` | 8 JSON schema definitions (evals, config, eval_metadata, timing, grading, benchmark, comparison, analysis) |
| Aggregator | `scripts/aggregate_benchmark.py` | Discovers grading.json files, computes mean/stddev/min/max stats, writes benchmark.json + benchmark.md |
| Runner | `scripts/run_eval.py` | Runs claude -p with skill system prompts, captures output text + timing per run |
| Grader | `agents/grader.md` | Assertion-based grading with cited evidence, claim extraction, assertion self-critique |
| Comparator | `agents/comparator.md` | Blind A/B comparison with Content + Structure rubric (1-10 scale) |
| Analyzer | `agents/analyzer.md` | Two modes: post-hoc comparison analysis + benchmark pattern analysis |
| Orchestrator | `SKILL.md` | 448-word workflow orchestration (well under 1,000w cap) |

### Verification Results

- `aggregate_benchmark.py --help`: Passes, shows all CLI args
- Functional smoke test with mock data: after=100% pass rate, before=0%, delta=+1.00
- `run_eval.py --help`: Passes, shows all CLI args
- `build_env()` / `build_claude_command()` / `slugify()` unit checks: All pass
- All referenced files exist check: Passes
- SKILL.md word count: 448 words (under 1,000 cap)

### Deviations

None. All tasks followed the plan exactly.
