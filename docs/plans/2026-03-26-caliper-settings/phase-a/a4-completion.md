# A4 Completion: Create caliper-settings skill SKILL.md

## What was done
- Created `skills/caliper-settings/SKILL.md` with frontmatter (name, description with trigger phrases)
- Documented all four subcommands: list, get, set, reset
- Included available settings table with key, type, default, and consuming skills
- Explained 3-tier precedence model (CLI flag > user setting > shipped default)

## Metrics
- Word count: 305 (budget: 1,500, hard cap: 2,000)
- No `@filename` references used
- Description is trigger-condition-only per conventions

## Verification
- `grep -q 'caliper-settings' skills/caliper-settings/SKILL.md` — PASS
- `head -5 | grep -q 'name: caliper-settings'` — PASS
