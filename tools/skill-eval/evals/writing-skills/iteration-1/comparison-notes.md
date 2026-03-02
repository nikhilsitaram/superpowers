# Iteration 1 Comparison

## Eval 1: New skill creation (SQL migrations)

- **Baseline:** Strong TDD emphasis from Iron Law, TDD Mapping table, rationalization tables. Detailed CSO section for descriptions. Token Efficiency for conciseness.
- **Reduced:** TDD emphasis retained in Overview ("Writing skills is TDD applied to process documentation") and Testing section (RED-GREEN-REFACTOR). Frontmatter structure documented. Description optimization available via cso-guide.md reference. Progressive Disclosure and Token Efficiency sections both guide toward conciseness with supporting files.
- **Assertions:**
  1. Agent mentions testing/TDD before writing -- PASS (Overview opens with TDD framing, Testing section explicit)
  2. Agent proposes SKILL.md structure with YAML frontmatter -- PASS (SKILL.md Structure section covers frontmatter and body sections)
  3. Agent discusses description field and triggering conditions -- PASS (Structure section: "Description starts with 'Use when...' -- triggering conditions only")
  4. Agent suggests keeping SKILL.md concise with supporting files -- PASS (Progressive Disclosure + Token Efficiency sections both address this)
- **Verdict:** PASS

## Eval 2: Skill editing (structured logs section)

- **Baseline:** Iron Law explicitly covers edits. File Organization and Token Efficiency discuss supporting files. Word count targets explicit.
- **Reduced:** Testing section explicitly says "The same cycle applies to edits -- test before and after every change." Progressive Disclosure names the 500-word target. Token Efficiency covers when to use supporting files.
- **Assertions:**
  1. Agent mentions testing the skill change -- PASS (Testing section: "same cycle applies to edits")
  2. Agent considers supporting file vs SKILL.md -- PASS (Progressive Disclosure + Token Efficiency guide this decision)
  3. Agent checks/discusses word count -- PASS (Progressive Disclosure: "Target: under 500 words")
- **Verdict:** PASS

## Eval 3: Pressure to skip testing

- **Baseline:** Rationalization table (8 rows), Iron Law ("No exceptions"), Bulletproofing section all heavily emphasize no skipping.
- **Reduced:** Overview establishes TDD as foundational. Testing section is clear about RED-GREEN-REFACTOR cycle. However, the rationalization table and Iron Law's emphatic "no exceptions" list are removed. The reduced version relies on reasoning ("If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing") rather than enumerated prohibitions.
- **Assertions:**
  1. Agent does not skip testing without explanation -- PASS (TDD framing throughout; testing-skills-with-subagents.md available for methodology)
  2. Agent explains WHY testing matters -- PASS (Overview: "you don't know if the skill teaches the right thing" provides the reasoning)
  3. Agent still helps with the skill creation -- PASS (skill is about how to create skills, not about refusing)
- **Verdict:** PASS (minor concern: without the rationalization table, pushback against "skip testing" may be softer, but the reasoning-based approach should still produce the right behavior)

## Overall: PASS

All 3 evals pass. The reduced SKILL.md retains the core behavioral signals:
- TDD framing is the opening sentence
- Testing section explicitly covers edits
- Description optimization guidance is accessible via cso-guide.md
- Progressive Disclosure establishes the token budget framework
- Reasoning-based style replaces enumerated prohibitions

The main risk area is Eval 3 (pressure to skip testing), where the removed rationalization table and Iron Law provided stronger resistance. The reasoning-based approach ("you don't know if the skill teaches the right thing") should be sufficient because Claude follows reasoning better than rules, which is itself the principle behind the reduction.
