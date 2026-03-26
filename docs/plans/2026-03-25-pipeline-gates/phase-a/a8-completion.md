# A8: Bump plugin version — Completion Notes

## What was done
Bumped `version` field in all three plugin entries in `.claude-plugin/marketplace.json` from `1.17.0` to `1.18.0`.

## Verification
- `jq -r '.plugins[].version'` outputs `1.18.0` three times
- Plan verification command passes

## Commit
`e9e4085` — `chore: bump plugin version to 1.18.0`
