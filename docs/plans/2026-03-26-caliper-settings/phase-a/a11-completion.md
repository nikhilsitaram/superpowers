# A11: Register skill and bump plugin version

## Changes Made

- Bumped version from `1.18.2` to `1.19.0` in all three plugin entries
- Added `./skills/caliper-settings` to `claude-caliper` (bundle) skills array
- Added `./skills/caliper-settings` to `claude-caliper-workflow` skills array
- Did NOT add to `claude-caliper-tooling` (standalone tools only)

## Verification

- All three plugins report version `1.19.0`
- `caliper-settings` present in plugins[0] and plugins[1]
- `caliper-settings` absent from plugins[2] (tooling)
