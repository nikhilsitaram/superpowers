---
name: writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
---

# Writing Skills

## Overview

Writing skills is TDD applied to process documentation. Write test cases (pressure scenarios), watch them fail (baseline), write the skill, watch tests pass (compliance), refactor (close loopholes).

If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing.

**Personal skills live in agent-specific directories (`~/.claude/skills` for Claude Code, `~/.agents/skills/` for Codex).**

## Progressive Disclosure

Skills load in three levels:

1. **Metadata** (name + description) -- always in context. Primary triggering mechanism.
2. **SKILL.md body** -- loaded when skill triggers. Target: under 500 words.
3. **Bundled resources** -- loaded on-demand when agent reads them. Unlimited size.

SKILL.md contains only what the agent needs to decide how to proceed. Reference material, examples, and checklists go in supporting files.

## When to Create

**Create when:** technique wasn't intuitively obvious, you'd reference it across projects, pattern applies broadly, others would benefit.

**Don't create for:** one-off solutions, standard practices well-documented elsewhere, project-specific conventions (put in CLAUDE.md), mechanical constraints enforceable with regex/validation.

## SKILL.md Structure

**Frontmatter (YAML):** Only `name` and `description`. Max 1024 chars. Name: letters, numbers, hyphens. Description starts with "Use when..." -- triggering conditions only. Never summarize workflow in the description (Claude may follow it instead of reading the skill body). **See:** cso-guide.md for description optimization.

**Body sections:** Overview, When to Use, Core Pattern, Quick Reference, Common Mistakes. Scale each to its complexity.

## Writing Style

Explain the *why* behind instructions -- Claude follows reasoning better than rigid rules. If you're writing ALL CAPS directives, reframe as reasoning instead.

Prefer imperative form. One excellent example beats many mediocre ones.

## Token Efficiency

Every word in SKILL.md displaces working memory:
- Move heavy reference to supporting files with `**See:** filename.md` pointers
- Cross-reference skills with `**REQUIRED SUB-SKILL:** Use superpowers:X` instead of embedding content
- One good example, not three
- Never use `@` file references (force-loads entire file into context)

## Testing

Follow RED-GREEN-REFACTOR: run pressure scenarios without the skill (baseline), write the skill, re-run with the skill (verify compliance), close loopholes found in testing.

The same cycle applies to edits -- test before and after every change.

**See:** testing-skills-with-subagents.md for the complete testing methodology, pressure scenario design, and meta-testing techniques.

**See:** checklist.md for the step-by-step RED-GREEN-REFACTOR checklist.

## Cross-Referencing

Reference other skills without embedding their content:
- `**REQUIRED SUB-SKILL:** Use superpowers:skill-name` -- agent invokes during execution
- `**REQUIRED BACKGROUND:** Read superpowers:skill-name first` -- prerequisite knowledge
- `**See:** filename.md` -- optional supporting reference

## Flowcharts

Use small inline dot flowcharts only for non-obvious decision points or process loops where the agent might stop too early. Not for reference material, code examples, or linear instructions.

**See:** graphviz-conventions.dot for flowchart style rules.
