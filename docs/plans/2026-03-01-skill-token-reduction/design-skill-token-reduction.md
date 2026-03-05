# Skill Token Reduction — Design Doc

**GitHub Issue:** #26 — "Skills are much too verbose"

## Problem

SKILL.md files are 2-4x over target word counts. When skills are invoked, their full SKILL.md is injected into context. Every excess word displaces working memory the agent could use for the actual task.

| Target | Guidance | Actual Range |
|--------|----------|-------------|
| Frequently-loaded (using-superpowers) | <200 words | 611 words (3.1x) |
| Discipline skills (TDD, debugging) | <600 words | 1,504–1,655 words |
| Other skills | <500 words | 366–3,204 words |

Only 1 of 17 skills (requesting-code-review at 366 words) meets its target. The 16 others collectively burn ~18,000+ excess words of context per full skill load.

The most-loaded skills (using-superpowers, brainstorming, TDD) impose the highest tax because they fire on nearly every conversation.

## Guiding Principles

Based on Anthropic's official skill-creator best practices (`anthropics/skills/skill-creator`):

### Progressive Disclosure (Three-Level Loading)

Skills use a three-level system. Each level loads only when needed:

1. **Metadata** (name + description) — Always in context. ~100 words. This is the primary triggering mechanism.
2. **SKILL.md body** — Loaded when skill triggers. Target: <500 lines, <500 words (general) / <600 words (discipline).
3. **Bundled resources** (references/, scripts/, agents/) — Loaded on-demand when the agent reads them. Unlimited size. Scripts can execute without loading into context.

**Key rule:** SKILL.md should contain only what the agent needs to decide how to proceed. Reference material, detailed examples, templates, and checklists belong in Level 3.

### Explain the Why, Not Heavy-Handed MUSTs

> "Try hard to explain the **why** behind everything you're asking the model to do. Today's LLMs are smart. They have good theory of mind and when given a good harness can go beyond rote instructions. If you find yourself writing ALWAYS or NEVER in all caps, or using super rigid structures, that's a yellow flag — reframe and explain the reasoning so that the model understands why the thing you're asking for is important."
> — Anthropic skill-creator

This means:
- Replace `MUST`, `NEVER`, `ALWAYS` patterns with reasoning that explains *why* the behavior matters
- Replace rationalization/Red Flags tables with concise explanations of the underlying principle
- Trust the model's understanding once it knows the reasoning

### Keep the Prompt Lean

> "Remove things that aren't pulling their weight. Read the transcripts — if the skill is making the model waste time doing unproductive things, try getting rid of those parts."

### Reference Files with Clear Pointers

- Reference files should be clearly mentioned from SKILL.md with guidance on **when** to read them
- For large reference files (>300 lines), include a table of contents
- Use `**See:** filename.md` for optional reference, `**REQUIRED:** Read filename.md` for mandatory

## Current State

Measured 2026-03-02 across all 17 skills in `skills/`:

| Skill | SKILL.md Words | Target | Over By |
|-------|---------------:|-------:|--------:|
| ~~writing-skills~~ | ~~3,204~~ | — | ~~retired~~ |
| subagent-driven-development | 1,868 | 500 | 1,368 |
| test-driven-development | 1,655 | 600 | 1,055 |
| writing-plans | 1,577 | 500 | 1,077 |
| systematic-debugging | 1,504 | 600 | 904 |
| ship | 1,381 | 500 | 881 |
| brainstorming | 1,245 | 500 | 745 |
| merge-pr | 1,201 | 500 | 701 |
| codebase-review | 1,148 | 500 | 648 |
| dispatching-parallel-agents | 975 | 500 | 475 |
| implementation-review | 974 | 500 | 474 |
| receiving-code-review | 917 | 500 | 417 |
| using-git-worktrees | 775 | 500 | 275 |
| plan-review | 653 | 500 | 153 |
| verification-before-completion | 651 | 500 | 151 |
| using-superpowers | 611 | 300 | 311 |
| requesting-code-review | 366 | 500 | -134 (OK) |

**Note:** Some skills also have supporting files loaded on-demand (not injected automatically). These are lower priority since they only load when the agent explicitly reads them. Notably, `systematic-debugging` has 5,462 across 7 files. (writing-skills was the largest at 11,837 words across 5 files, but has been retired.)

## Resolved Decisions

These were open questions in the original design. Now resolved based on GH Issue #26 feedback and usage experience:

1. **Word targets:** <600 for discipline skills (TDD, systematic-debugging), <500 for all others, <300 for using-superpowers. Discipline skills need more text for their core patterns, but not for examples and rationalization tables.

2. **Red Flags and rationalization tables: remove entirely.** Issue #26 explicitly flags these as "based on old LLM logic and outdated now." After months of use, Claude has internalized the compliance patterns. These tables are pure context tax. Remove from all SKILL.md files — do not move to supporting files.

3. **No `_shared/` directory.** No cross-skill shared content has materialized. Each skill keeps its own supporting files in its own directory. Drop this convention.

4. **`@`-references in SKILL.md force-load files and should be replaced.** Replace with `**See:** filename.md` cross-references. (writing-skills, which had the worst `@`-reference violations, has been retired.)

## Reduction Techniques

Five techniques, ordered by expected impact:

### Technique 1: Remove Red Flags, rationalization tables, and anti-pattern lists

These were written when skills were new and Claude needed explicit compliance training. They're now internalized. Remove entirely — not moved to supporting files, deleted.

**Applies to:**
- **using-superpowers** — Red Flags table (~200 words, 12 rows)
- ~~**writing-skills**~~ — retired
- **test-driven-development** — rationalization table + Red Flags list (verify actual content)
- **codebase-review** — Red Flags section (~80 words)

### Technique 2: Move details to supporting files

Content the agent only needs when actively performing a subtask (not when deciding whether/how to follow the skill). SKILL.md keeps a one-line `**See:** filename.md` reference.

**Candidates:**
- ~~**writing-skills**~~ — retired
- **subagent-driven-development** — Deviation rules and plan doc update instructions; move to `deviation-rules.md` and `plan-doc-updates.md`.
- **writing-plans** — Full task structure template (~250 words); move to `task-template.md`.
- **systematic-debugging** — Multi-component evidence gathering example (~150 words) and "Human Partner's Signals" section (~80 words); move to supporting file. (Note: this skill already has 6 supporting files, so the pattern is established.)
- **ship** — CLAUDE.md Guidelines section (~150 words) is generic guidance; move to `docs-review-guide.md`.
- **codebase-review** — Report format template (~150 words); move to `report-template.md`.

### Technique 3: Compress examples and remove redundancy

Replace verbose multi-line examples with minimal ones. One good example, not three. Remove content that duplicates other skills or restates the obvious.

**Candidates:**
- **receiving-code-review** — Four "Real Examples" when one suffices (~90 words saved)
- **brainstorming** — "Challenging Product Assumptions" example compressible to 2-3 lines; "Anti-Pattern: This Is Too Simple" section compressible to 1 line; "Native Task Integration" section is generic TaskCreate/TaskUpdate usage any skill can figure out (remove entirely)
- **using-git-worktrees** — Creation Steps section repeats what bash examples already show
- **ship** — Common Mistakes table (8 rows) and Examples section are redundant with workflow steps
- **merge-pr** — Common Mistakes table (8 rows), Examples section, and duplicate test runner table (cross-reference ship instead)
- **implementation-review** — Integration Test Verification section restates what subagent-driven-development already describes; compress to 1 line
- ~~**writing-skills**~~ — retired
- **test-driven-development** — "Why Order Matters" prose (~300 words) is persuasion material; move to supporting file or delete

### Technique 4: Cross-reference instead of repeat

Use `**REQUIRED SUB-SKILL:** Use superpowers:X` or `**See:** filename.md` to point agents at other skills/files rather than embedding their content. Replace `@` force-load references with non-loading cross-references.

**Already done well by:** plan-review, implementation-review.

**Needs improvement:**
- ~~**writing-skills**~~ — retired
- **subagent-driven-development** — Embeds deviation rules that belong in a supporting file

### Technique 5: Tighten bash code blocks

Many skills embed multi-line bash scripts that are 50-100 words each. These are instructional — telling the agent what commands to run. Claude already knows these commands; a 1-line description is sufficient.

**Candidates:**
- **ship** — Steps 2 (branch detection, ~100 words of bash), 6 (rebase), 7 (push) can each be 1 line
- **merge-pr** — Steps 1 (identify PR), 2 (detect environment), 3 (read reviews) are verbose bash
- **codebase-review** — Phase 1 bash example is unnecessary

### Technique 6: Style migration — explain-the-why

Rewrite imperative MUST/NEVER/ALWAYS patterns into reasoning-based guidance. This is not just trimming — it's a style change that makes skills more effective per Anthropic's research.

**Before (heavy-handed):**
```markdown
**NEVER** skip the cross-scope reconciliation pass.
**ALWAYS** write the report before starting any fixes.
```

**After (reasoning-based):**
```markdown
Run the cross-scope reconciliation pass after individual reviews — without it, cross-directory DRY violations and naming drift go undetected.

Write the report before starting fixes so the user can triage complexity and decide which items become GitHub issues vs inline fixes.
```

**Applies to all skills**, but most heavily to:
- **using-superpowers** — `EXTREMELY-IMPORTANT` blocks, `MUST` directives
- ~~**writing-skills**~~ — retired
- **test-driven-development** — Iron Law, "Violating the letter" directives
- **codebase-review** — "Never/Always" Red Flags list
- **brainstorming** — `HARD-GATE` blocks

## Evaluation Methodology

Uses Anthropic's skill-creator eval framework (`anthropics/skills/skill-creator`), pulled into our repo as tooling. Each phase of skills gets verified before moving to the next.

### Setup: Pull in Anthropic Eval Framework

Clone or vendor `anthropics/skills/skill-creator/` into the repo under `tools/skill-eval/`. Key components:

| Component | Purpose |
|-----------|---------|
| **Scripts** | |
| `scripts/run_eval.py` | Runs test prompts via `claude -p` with/without skill, captures outputs |
| `scripts/run_loop.py` | Full improvement loop: eval → improve → re-eval (up to N iterations) |
| `scripts/aggregate_benchmark.py` | Aggregates pass rates, timing, token usage into `benchmark.json`/`benchmark.md` |
| `scripts/generate_report.py` | Generates human-readable report from benchmark data |
| `scripts/improve_description.py` | Optimizes skill description for triggering accuracy |
| `scripts/quick_validate.py` | Fast sanity check — validates skill structure and runs a single prompt |
| `scripts/package_skill.py` | Packages a skill directory into a `.skill` file for distribution |
| `scripts/utils.py` | Shared utilities used by other scripts |
| **Eval Viewer** | |
| `eval-viewer/generate_review.py` | Generates HTML viewer for side-by-side output comparison + benchmark tab |
| `eval-viewer/viewer.html` | Template for the interactive eval review viewer (Outputs tab + Benchmark tab) |
| **Assets** | |
| `assets/eval_review.html` | Template for description triggering eval review (user edits trigger queries) |
| **Agents** | |
| `agents/grader.md` | Subagent prompt for evaluating assertions against outputs |
| `agents/comparator.md` | Subagent prompt for blind A/B comparison between two outputs |
| `agents/analyzer.md` | Subagent prompt for analyzing benchmark results and surfacing patterns |
| **References** | |
| `references/schemas.md` | JSON schemas for evals.json, grading.json, benchmark.json, history.json |

### Per-Skill Eval Process

For each skill reduction:

1. **Write 2-3 realistic test prompts** — save to `evals/evals.json` per skill. Make them concrete and specific (file paths, personal context, abbreviations) — not abstract requests. Each prompt should be something a real user would actually type.

2. **Write assertions** — verifiable behavioral expectations for each prompt. Focus on workflow steps, not output wording:
   - "Agent creates feature branch before committing" (workflow)
   - "Agent runs tests before pushing" (safety check)
   - "Agent asks user before force-pushing" (decision point)

3. **Run baseline and reduced in parallel** — use `run_eval.py` to spawn subagents:
   - **Baseline:** original (unreduced) SKILL.md
   - **Reduced:** new SKILL.md
   - Both get the same test prompts, outputs saved to `iteration-N/eval-ID/{with_skill,old_skill}/outputs/`

4. **Grade** — use grader subagent (`agents/grader.md`) to evaluate assertions. For assertions that can be checked programmatically (e.g., "file exists", "git log shows commit"), write a script instead.

5. **Aggregate and review** — run `aggregate_benchmark.py` to produce `benchmark.json`, then `generate_review.py` to open the HTML viewer for human review of qualitative differences.

6. **Iterate** — if the reduced skill misses assertions, add back the minimum text needed and re-eval. Use `run_loop.py` for automated iteration if needed.

### What "Same Behavior" Means

The reduced skill doesn't need to produce *identical* output — it needs to produce *equivalent* behavior. The agent should:
- Follow the same workflow steps in the same order
- Make the same key decisions (e.g., when to branch, when to ask the user)
- Not skip safety checks or important validations
- Not introduce new failure modes

Style differences (different wording in commit messages, slightly different phrasing in questions) are fine. Workflow deviations are not.

### Eval Scaling by Change Size

| Change Size | Eval Approach |
|-------------|--------------|
| Major restructure (>200w removed, style migration) | Full 3-prompt eval with assertions + HTML viewer |
| Moderate trim (100-200w removed) | 2-prompt eval with key assertions |
| Minor trim (<100w, e.g., plan-review) | 1-prompt spot check, manual verification |

### Description Optimization (Post-Reduction)

After reducing all skills, optionally run `improve_description.py` on each skill's description field. This uses `claude -p` to test triggering accuracy against realistic prompts and iteratively improves the description. Useful since reduced skills may need updated descriptions to maintain triggering reliability.

## Approach

### Plan 1: SUPERSEDED (2026-03-02)

Plan 1 (vendor Anthropic eval framework + rewrite writing-skills) is superseded:

- **writing-skills retired.** The skill and all its supporting files have been deleted. Skill conventions now live in `.claude/CLAUDE.md` as project-level instructions — always in context, no skill triggering needed.
- **Vendored eval framework replaced by skill-creator plugin.** Instead of vendoring `anthropics/skills/skill-creator/` into `tools/skill-eval/`, we use the Anthropic `skill-creator` plugin directly (`claude skill create` / `claude skill improve`). This gives us eval-driven skill development without maintaining vendored scripts.
- **PR #30 closed** with explanation. No code was merged from Plan 1.

The guiding principles, reduction techniques, and current-state measurements in this document remain valid and inform Plan 2.

### Plan 2: Reduce all remaining skills

Applies the reduction techniques documented above to all 15 remaining over-target skills. Uses the `skill-creator` plugin for eval-driven regression testing. Could ship as multiple PRs (one per phase). Skill conventions are now in `.claude/CLAUDE.md`.

**Phase 2a: High-frequency skills** — load on nearly every conversation. Highest ROI per word saved.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| using-superpowers | 611 | T1: Remove Red Flags table (~200w). T3: Compress Skill Priority section. T6: Rewrite EXTREMELY-IMPORTANT block to reasoning. | <300 |
| brainstorming | 1,245 | T3: Remove Native Task Integration; compress Anti-Pattern to 1 line; compress Challenging Product Assumptions example; compress Process section. T6: Rewrite HARD-GATE to reasoning. | <500 |
| test-driven-development | 1,655 | T1: Remove rationalization table + Red Flags. T2: Move "Why Order Matters" to supporting file. T3: Compress Good/Bad examples. T6: Rewrite Iron Law block to reasoning-based. | <600 |

**Phase 2b: Execution pipeline skills** — load during plan execution.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| subagent-driven-development | 1,868 | T2: Move deviation rules + plan doc updates to supporting files. T3: Move example workflow to supporting file. | <500 |
| writing-plans | 1,577 | T2: Move task template to supporting file. T3: Compress header template. | <500 |
| systematic-debugging | 1,504 | T2: Move multi-component example + Human Partner's Signals to supporting file. T3: Compress Phase 2-4 (keep Phase 1 detailed). | <600 |

**Phase 2c: Shipping and review skills** — all remaining skills over target.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| ship | 1,381 | T2: Move CLAUDE.md guidelines to supporting file. T3: Remove Common Mistakes + Examples. T5: Compress bash in Steps 2/6/7. | <500 |
| merge-pr | 1,201 | T3: Remove Common Mistakes + Examples; cross-ref ship for test runner table. T5: Compress bash in Steps 1-3. | <500 |
| codebase-review | 1,148 | T1: Remove Red Flags. T2: Move report template to supporting file. T3: Remove Common Mistakes. T5: Remove Phase 1 bash. | <500 |
| dispatching-parallel-agents | 975 | T3: Remove session example (redundant). | <500 |
| implementation-review | 974 | T3: Compress integration test verification to 1 line. | <500 |
| receiving-code-review | 917 | T3: Remove 3 of 4 real examples. | <500 |
| using-git-worktrees | 775 | T3: Compress Creation Steps. | <500 |
| plan-review | 653 | T3: Compress "What It Catches" table. | <500 |
| verification-before-completion | 651 | T3: Compress Key Patterns section. | <500 |

### Summary

| Phase | Skills | Current | Target | Savings |
|-------|-------:|--------:|-------:|--------:|
| ~~1a (eval setup)~~ | — | — | — | ~~superseded~~ |
| ~~1b (writing-skills)~~ | ~~1~~ | ~~3,204~~ | — | ~~retired~~ |
| 2a (high-freq) | 3 | 3,511 | ~1,400 | ~2,100 |
| 2b (execution) | 3 | 4,949 | ~1,600 | ~3,350 |
| 2c (shipping/review) | 9 | 9,675 | ~4,100 | ~5,575 |
| **Total (Plan 2)** | **15** | **18,135** | **~7,100** | **~11,035 (~61%)** |

(requesting-code-review already under target; excluded. writing-skills retired entirely.)

## Constraints

- **No workflow changes.** Reduced skills must produce equivalent agent workflow behavior — same steps, same decision points, same safety checks. Style changes (MUST → reasoning, verbose → concise) are encouraged per Anthropic best practices. See "What Same Behavior Means" in Evaluation Methodology.
- **Eval before merge.** Use `skill-creator` plugin evals to verify each phase before moving to the next.
- **Supporting files inherit existing patterns.** Several skills (systematic-debugging, subagent-driven-development, test-driven-development) already use supporting files. Follow the same conventions.
- **Progressive disclosure.** When moving content to supporting files, include clear pointers in SKILL.md about *when* to read them. For files >300 lines, include a table of contents.
- **Skill conventions in `.claude/CLAUDE.md`.** Project-level instructions (Iron Law, token targets, cross-referencing syntax) replace the retired writing-skills.

## Success Criteria

### Plan 1: SUPERSEDED

See "Plan 1: SUPERSEDED" section above.

### Plan 2

- All 15 remaining over-target skills under their respective targets (<600 discipline, <500 general, <300 using-superpowers)
- All SKILL.md files under 500 lines
- No skill workflow regressions in `skill-creator` evals
- Total SKILL.md context budget reduced by ~60% across all skills
- All Red Flags / rationalization tables removed
- MUST/NEVER/ALWAYS patterns replaced with reasoning-based guidance
