---
status: Not Yet Started
---

# Optimize validate-plan schema validation by batching jq calls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Optimize validate-plan schema validation by batching jq calls
**Architecture:** Replace ~100 individual jq subprocess forks in do_schema() and do_consistency() with 5-10 bulk extractions using JSON-per-line and TSV patterns. Bash iterates extracted data without further jq calls. All error strings, exit codes, and CLI behavior remain identical.
**Tech Stack:** Bash, jq

---

## Phase A — Batch jq calls in do_schema and do_consistency
**Status:** Not Started | **Rationale:** Single phase because the three tasks are independent: A1 refactors do_schema, A2 refactors do_consistency, A3 runs the full benchmark. A1 and A2 modify disjoint line ranges of the same file, but since both modify scripts/validate-plan, A2 depends on A1 to avoid merge conflicts.

- [ ] A1: Batch jq calls in do_schema() — *do_schema() uses 4-5 bulk jq calls instead of ~75 individual ones. All 7 test files that exercise --schema pass with zero modifications.*
- [ ] A2: Batch jq calls in do_consistency() — *do_consistency() uses 1-2 bulk jq calls instead of ~20 individual ones. Also passes the loaded $json from do_schema() instead of re-reading plan.json from disk. Both consistency test files pass with zero modifications.*
- [ ] A3: Run full test suite and benchmark — *All 18 test files pass. test_schema.sh completes in under 3 seconds (baseline 10.2s).*
