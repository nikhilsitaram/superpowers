# Design: Worktree Dependency Bootstrap

## Problem

Worktree dependency bootstrapping in the orchestrate skill has four gaps that cause silent failures or misconfigured environments:

1. **No monorepo support** — detection only checks the worktree root. Repos with manifests in subdirectories (e.g., `backend/pyproject.toml` + `frontend/package.json`) or workspace managers hit the symlink fallback and get no deps installed.
2. **No tool availability check** — Python install commands assume `uv` is available. The parenthetical fallback to `python3 -m venv` is prose, not conditional logic the agent would execute.
3. **No install failure handling** — if an install command exits non-zero, the bootstrap continues silently. Tasks then fail with cryptic import/module errors instead of a clear "deps failed" message.
4. **Design skill skips bootstrap entirely** — the design skill creates the integration worktree and runs tests as a baseline, but never installs dependencies. Tests fail immediately in any repo that needs deps.

These affect every repo that uses the orchestrate or design skills with worktrees.

## Goal

Make worktree dependency bootstrapping reliable across single-root repos, workspace-based monorepos, and multi-manifest repos, with clear failure reporting and tool availability fallbacks.

## Success Criteria

1. An agent following the bootstrap procedure in a repo with only `backend/requirements.txt` (no root manifest) correctly detects and installs dependencies in the subdirectory.
2. An agent on a machine without `uv` falls back to `python3 -m venv + pip` without error.
3. When `npm ci` exits non-zero, the agent stops and escalates to the user instead of continuing with broken deps.
4. The design skill bootstraps dependencies before running baseline tests, using the same procedure as orchestrate.
5. The bootstrap reference file stays under 400 words (token budget for a conditional-read reference).

## Architecture

Extract the bootstrap procedure to `skills/design/dependency-bootstrap.md` — a shared reference file read on-demand by both skills. The design skill is the natural owner because it creates the first worktree where bootstrap runs.

```text
skills/design/dependency-bootstrap.md  ← authoritative procedure (new)
skills/design/SKILL.md step 6          ← adds bootstrap before test run
skills/orchestrate/SKILL.md step 3     ← replaces inline table with reference
```

### Detection Order

1. **Root manifests** — check worktree root for known lockfiles/manifests (existing behavior)
2. **Workspace indicators** — if no root manifest, check for `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`; if found, run the workspace-level install at root
3. **Subdirectory scan** — if neither root manifest nor workspace indicator, scan immediate child directories for manifests; install in each that has one
4. **Symlink fallback** — if nothing detected, symlink `.venv`/`node_modules` from main repo root (existing behavior)

### Python Tool Fallback

```text
if command -v uv: uv-based commands
else: python3 -m venv + pip
```

### Failure Handling

Check exit code of every install command. Non-zero → log the error output and escalate to the user. Do not continue with a broken environment — tasks will fail with misleading errors.

## Key Decisions

- **Reference file lives under `skills/design/`** — design creates the first worktree, making it the natural owner. Orchestrate references it cross-skill.
- **Exit code check, not import validation** — if `npm ci` exits 0, deps are installed. No need for `python -c "import pkg"` which requires knowing package names and is fragile.
- **Subdirectory scan is one level deep** — deeply nested manifests are an edge case not worth the complexity. One level covers `backend/`, `frontend/`, `services/api/` patterns.
- **Workspace managers get root-level install** — `pnpm install`, `npm ci`, `yarn install` at root handle all packages in a workspace. No need to install per-package.

## Non-Goals

- Auto-detecting the correct Python version (pyenv, asdf) — out of scope
- Supporting Gradle, Maven, or other JVM build tools — can be added later to the table
- Nested monorepo structures (workspaces within workspaces)
- Caching or sharing deps across phase worktrees (symlink fallback partially covers this)

## Implementation Approach

Single phase — three tightly coupled files:

1. Create `skills/design/dependency-bootstrap.md` with the full procedure
2. Edit `skills/design/SKILL.md` step 6 to add bootstrap + reference
3. Edit `skills/orchestrate/SKILL.md` step 3 to replace inline table with reference
