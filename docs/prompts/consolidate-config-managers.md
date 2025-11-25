# Task: Consolidate Configuration Manager Classes

## Objective
Consolidate overlapping configuration management classes into a single, coherent service layer.

## Current State (Overlapping Classes)

1. **ConfigurationService** (`Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift`)
   - File I/O, parsing, validation
   - Main config service used by RuntimeCoordinator

2. **ConfigurationManager** (`Sources/KeyPathAppKit/Managers/Configuration/ConfigurationManager.swift`)
   - Protocol-based wrapper
   - Used by RuntimeCoordinator.configurationManager

3. **KanataConfigManager** (`Sources/KeyPathAppKit/Managers/KanataConfigManager.swift`)
   - Another config manager
   - May have overlapping functionality

## Analysis Steps

1. Read each file to understand its responsibilities
2. Identify which methods are actually used
3. Determine the canonical service to keep
4. Migrate callers to the canonical service
5. Delete or deprecate unused classes

## Expected Outcome

- One clear `ConfigurationService` as the source of truth
- `ConfigurationManager` protocol if needed for testing/mocking
- Remove `KanataConfigManager` if redundant
- Clear documentation of the config service API

## Git Workflow

```bash
git checkout master
git pull
git checkout -b refactor/consolidate-config-managers
# Analysis and consolidation
swift build
swift test
git add -A
git commit -m "refactor: consolidate configuration manager classes"
git push -u origin refactor/consolidate-config-managers
```

## Validation

1. `swift build` passes
2. `swift test` passes (60 tests)
3. Config reading/writing still works
4. No orphaned/unused manager classes

## Estimated Effort
~2-3 hours (analysis + consolidation)

