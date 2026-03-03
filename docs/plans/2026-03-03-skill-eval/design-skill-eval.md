# Design: skill-eval — Output Quality Evaluation for Skills

## Goal

Standardize skill output quality evaluation with assertion-based grading, blind comparison, and variance analysis. Adapted from [Anthropic's skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) eval pattern, trimmed for this repo's conventions.

## Problem

No standardized way to evaluate skill output quality. The TDD v1→v2 replacement required ad-hoc scripts, binary regex assertions that couldn't differentiate quality (7/7 tie), and manual side-by-side reading. This doesn't scale across 10+ skills.

## Architecture

### Skill Structure

```text
skills/skill-eval/
├── SKILL.md                      # Workflow orchestration (<1,000w)
├── agents/
│   ├── grader.md                 # Assertion grading + eval critique
│   ├── comparator.md             # Blind comparison (2D rubric)
│   └── analyzer.md               # Post-hoc analysis + benchmark patterns
├── scripts/
│   ├── run_eval.py               # Execute eval prompts via claude -p (behavioral)
│   └── aggregate_benchmark.py    # Aggregate pass rates + timing (ported from skill-creator)
└── references/
    └── schemas.md                # JSON schemas for all data files
```

### Data Directory

All eval data lives in `.skill-evals/` (gitignored):

```text
.skill-evals/
└── {skill-name}/
    ├── evals.json                    # eval prompts + assertions
    ├── iteration-1/
    │   ├── config.json               # what before/after represent
    │   ├── eval-{id}-{name}/
    │   │   ├── before/
    │   │   │   ├── run-1.txt         # claude -p stdout
    │   │   │   ├── run-2.txt
    │   │   │   ├── run-3.txt
    │   │   │   ├── timing.json       # per-run tokens + duration
    │   │   │   └── grading.json      # assertion results
    │   │   ├── after/
    │   │   │   └── ...
    │   │   └── eval_metadata.json    # prompt + assertions for this eval
    │   ├── comparison.json           # blind comparator output
    │   ├── analysis.json             # analyzer output
    │   ├── benchmark.json            # aggregated stats
    │   └── benchmark.md             # human-readable summary
```

### config.json

Tracks what each variant represents:

```json
{
  "before": {
    "label": "v1-authority",
    "type": "skill",
    "skill_path": ".skill-evals/tdd/snapshot-v1/SKILL.md"
  },
  "after": {
    "label": "v2-reasoning",
    "type": "skill",
    "skill_path": "skills/test-driven-development/SKILL.md"
  }
}
```

When `type` is `"none"`, no skill is loaded (no-skill baseline). Every eval always has both before and after — when evaluating a new skill with no prior version, before is `"none"`.

## Components

### From skill-creator (adapted)

| Component | Source | Adaptation |
|-----------|--------|------------|
| `aggregate_benchmark.py` | `scripts/aggregate_benchmark.py` | Port with path updates for `.skill-evals/` structure and before/after naming. Dynamic config discovery confirmed — doesn't hardcode variant names. |
| `grader.md` | `agents/grader.md` | Trim to assertion grading + eval self-critique. Core: PASS requires cited evidence of substantial completion, not surface-level compliance. |
| `comparator.md` | `agents/comparator.md` | Blind 2D rubric: Content (1-5) + Structure (1-5) → Overall (1-10). 7-step evaluation methodology. |
| `analyzer.md` | `agents/analyzer.md` | Both modes: post-comparison "why winner won" (instruction-following scores, prioritized improvements) + benchmark pattern surfacing (non-discriminating assertions, variance, time/token tradeoffs). |
| `schemas.md` | `references/schemas.md` | Update for before/after naming, `.skill-evals/` paths, 3-run structure. Key schemas: evals.json, grading.json, timing.json, benchmark.json, comparison.json, analysis.json. |

### Purpose-built (not ported)

| Component | Rationale |
|-----------|-----------|
| `run_eval.py` | Anthropic's `run_eval.py` tests description triggering (uses `--output-format stream-json` to detect tool invocations). Our version tests behavioral output quality (uses `--output-format text` to capture pure text responses). Different purpose → different implementation. |
| `SKILL.md` | Workflow orchestration tailored to this repo's conventions (<1,000w). |

### Dropped from skill-creator

| Component | Reason |
|-----------|--------|
| `eval-viewer/` | CLI summary + benchmark.md sufficient |
| `run_loop.py` | Manual invocation; automate later if needed |
| `improve_description.py` | Description optimization out of scope |
| `generate_report.py` | `benchmark.md` from aggregate script covers this |
| `assets/eval_review.html` | No browser reviewer needed |
| `package_skill.py` | Not relevant to this repo |
| Claude.ai / Cowork sections | Not applicable |

## SKILL.md Workflow

Triggers on `/skill-eval`, "evaluate this skill", "compare skill versions", "benchmark this skill".

### Step 1: Identify Target and Set Up

1. Identify the target skill and whether a previous version exists.
2. If comparing against a previous version, snapshot it before any edits:
   ```bash
   cp -r skills/{name} .skill-evals/{name}/snapshot-before/
   ```
3. Check for `evals.json` in `.skill-evals/{name}/`. If none exists, create interactively — draft 2-3 realistic test prompts that a real user would actually say. Include edge cases and adversarial prompts (deadline pressure, "skip this step", ambiguous requirements).
4. Write `config.json` for this iteration describing what before/after represent.

### Step 2: Spawn All Runs in the Same Turn

For each eval prompt, spawn both before AND after variants simultaneously. Don't do before first then after — launch everything at once so it finishes around the same time.

Each variant runs 3 times (for variance analysis). Uses `run_eval.py`:

```bash
python skills/skill-eval/scripts/run_eval.py \
  --skill-path skills/{name}/SKILL.md \
  --evals-path .skill-evals/{name}/evals.json \
  --output-dir .skill-evals/{name}/iteration-N/ \
  --variant after \
  --runs 3
```

Under the hood, `run_eval.py` invokes:

```bash
env -u CLAUDECODE CLAUDE_SKIP_MEMORY=1 claude -p \
  --system-prompt "$(cat path/to/SKILL.md)" \
  --output-format text \
  --allowedTools "" \
  <<< "$PROMPT"
```

For no-skill baseline (`type: "none"`), omits `--system-prompt`.

Each eval gets a descriptive directory name based on what it tests (e.g., `eval-1-deadline-pressure`, not just `eval-1`).

### Step 3: Draft Assertions While Runs Are In Progress

Don't wait for runs to finish — draft quantitative assertions while they execute. Good assertions:

- Are objectively verifiable
- Have descriptive names that read clearly in benchmark output
- Are not trivially satisfied (the grader flags these)
- Test behavioral outcomes, not surface-level compliance

Update `eval_metadata.json` and `evals.json` with drafted assertions. For assertions that can be checked programmatically, prefer scripts over eyeballing — faster, more reliable, reusable across iterations.

### Step 4: Grade Each Run

Spawn a grader subagent per eval (reads `agents/grader.md`):

1. Reads each run's output text
2. Evaluates each assertion — PASS requires cited evidence of substantial completion, not surface-level compliance
3. Extracts factual/process/quality claims beyond predefined assertions and verifies each
4. Self-critiques the eval set — flags assertions that always pass (no signal) or pass despite wrong outputs (false positives)
5. Saves `grading.json` per variant

The `grading.json` expectations array uses fields `text`, `passed`, and `evidence` (not `name`/`met`/`details` — the downstream tooling depends on these exact field names).

### Step 5: Aggregate and Analyze

1. **Aggregate** — Run `aggregate_benchmark.py`:
   ```bash
   python skills/skill-eval/scripts/aggregate_benchmark.py \
     .skill-evals/{name}/iteration-N \
     --skill-name {name}
   ```
   Produces `benchmark.json` (pass_rate, time, tokens with mean ± stddev per variant, delta) and `benchmark.md`.

2. **Benchmark analysis** — Spawn analyzer subagent reading benchmark data (reads `agents/analyzer.md`, "Analyzing Benchmark Results" section). Surfaces patterns aggregates hide:
   - Assertions that always pass regardless of variant (non-discriminating)
   - High-variance evals (possibly flaky)
   - Time/token tradeoffs
   - Surprising results that contradict expectations

### Step 6: Blind Comparison

Spawn comparator subagent (reads `agents/comparator.md`):

1. Receives both outputs WITHOUT knowing which is before/after
2. Generates evaluation rubric adapted to the specific task
3. Scores each on two dimensions:
   - **Content Quality** (correctness, completeness, accuracy): 1-5
   - **Structural Quality** (organization, formatting, usability): 1-5
   - **Overall**: average → 1-10
4. Determines winner with cited reasoning
5. Saves `comparison.json`

### Step 7: Post-Hoc Analysis

Spawn analyzer subagent (reads `agents/analyzer.md`) with comparison results + both skill files:

1. "Unblinds" the results — maps winner/loser to before/after
2. Reads both SKILL.md files and execution outputs
3. Identifies what made the winner better (clearer instructions? better examples? fewer unnecessary steps?)
4. Identifies what held the loser back
5. Scores instruction-following adherence (1-10) for each variant
6. Generates prioritized improvement suggestions (High/Medium/Low) categorized as: instructions, tools, examples, error_handling, structure, references
7. Saves `analysis.json`

### Step 8: Report Results

Present to user:
- Pass rates per variant with variance (mean ± stddev)
- Blind comparison winner + reasoning
- Key strengths of winner, weaknesses of loser
- Improvement suggestions (prioritized)
- Assertion quality feedback (which to strengthen/drop)

### Iterating

If improving: edit the skill based on analysis, then:
1. Snapshot current state as new "before"
2. Apply improvements as new "after"
3. Rerun into `iteration-N+1/`
4. Repeat until satisfied

## Model Choices

| Role | Model | Rationale |
|------|-------|-----------|
| Eval subjects | haiku via `claude -p` | Cheap, fast. Behavioral assertions don't need strong reasoning. |
| Grader | Session model via Agent tool | Needs strong reasoning for qualitative grading |
| Comparator | Session model via Agent tool | Blind comparison needs objectivity |
| Analyzer | Session model via Agent tool | Pattern analysis benefits from deep reasoning |

## Key Decisions

- **Always compare**: Every eval has before/after. Even new skills run a no-skill baseline.
- **3 runs per scenario**: Balances cost vs confidence. Surfaces flaky assertions via variance.
- **Centralized + gitignored**: All eval data in `.skill-evals/`, not committed. Evals are moment-in-time artifacts.
- **`run_eval.py` purpose-built**: Anthropic's version tests description triggering; ours tests behavioral output quality. Different purpose → different implementation.
- **`aggregate_benchmark.py` ported**: Dynamic config discovery works with any variant names. Minimal changes needed.
- **Analyzer kept**: Automated "why winner won" analysis saves re-reading transcripts.

## Non-Goals

- **Description optimization** — skill descriptions are well-behaved in this repo
- **Browser eval viewer** — CLI output + benchmark.md sufficient
- **Automated improvement loop** — manual iteration first
- **Cross-skill benchmarking** — each skill evaluated independently

## Key Technical Gotchas

Validated against Anthropic's skill-creator source and TDD eval proof-of-concept:

| Gotcha | Source | Detail |
|--------|--------|--------|
| `env -u CLAUDECODE` | Anthropic confirmed | `CLAUDECODE` env var blocks nested `claude -p` sessions. Anthropic filters it: `{k: v for k, v in os.environ.items() if k != "CLAUDECODE"}` |
| `--output-format text` | Repo-specific | Anthropic uses `stream-json` (trigger detection). We need `text` for behavioral output capture. Without it, output goes to stderr. |
| `CLAUDE_SKIP_MEMORY=1` | Repo-specific | Suppresses memory injection in subprocesses. Not in Anthropic's code (they don't have a memory system). |
| `--allowedTools ""` | Repo-specific | Prevents tool use for pure text behavioral responses. Anthropic doesn't use this (they need tools for trigger detection). |
| `set -eo pipefail` | General best practice | `tee` silently masks pipeline failures without `pipefail`. TDD eval proof-of-concept caught this. |

## Implementation Approach

Single phase — no dependency layers. The skill, scripts, agents, and schemas can be built and tested together. The skill is self-contained with no prerequisites from other skills.
