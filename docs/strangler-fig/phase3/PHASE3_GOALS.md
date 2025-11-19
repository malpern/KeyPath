# Phase 3 Goals: Implement `makePlan()`

**Status:** 🚀 STARTING

**Date:** 2025-11-17

---

## 🎯 What We'll Accomplish by End of Phase 3

By the end of Phase 3, we will have:

### ✅ **Working `makePlan()` Method**
- Takes `InstallIntent` (`.install`, `.repair`, `.uninstall`, `.inspectOnly`) and `SystemContext`
- Returns `InstallPlan` with ordered `ServiceRecipe`s
- Marks plan as `.blocked` if requirements unmet (with blocking requirement details)

### ✅ **Requirement Checking**
- Checks admin rights availability
- Checks writable directories (LaunchDaemons, config, logs)
- Checks SMAppService approval status
- Checks helper registration status
- Blocks plan if critical requirements unmet

### ✅ **Intent → Action Mapping**
- Maps `.install` intent to installation actions (install services, components, helper)
- Maps `.repair` intent to repair actions (restart services, fix conflicts, reinstall broken components)
- Maps `.uninstall` intent to cleanup actions (remove services, components)
- Maps `.inspectOnly` intent to empty plan (no actions)

### ✅ **Service Recipe Generation**
- Generates `ServiceRecipe`s for:
  - LaunchDaemon services (Kanata, VHID daemon, VHID manager)
  - Component installation (Kanata binary, drivers)
  - Helper installation/repair
  - Service restarts/repairs
- Respects service dependency order
- Includes health check criteria

### ✅ **Integration with Existing Logic**
- Wires up `WizardAutoFixer` action determination logic
- Wires up `LaunchDaemonInstaller` service creation logic
- Wires up `PackageManager` / `BundledKanataManager` component logic
- Wires up version upgrade detection

### ✅ **Tests**
- Tests for each intent type (`.install`, `.repair`, `.uninstall`, `.inspectOnly`)
- Tests for requirement blocking
- Tests for recipe generation and ordering
- Tests verifying plan matches existing behavior

---

## 📋 Deliverables

1. **`makePlan()` implementation** - Real planning logic (not stubbed)
2. **Requirement checking** - Validates prerequisites before planning
3. **Recipe generation** - Converts intents + context → ordered recipes
4. **Tests** - Comprehensive test coverage for planning logic
5. **Documentation** - Phase 3 summary document

---

## 🔄 Current State vs. End State

### Current State (Phase 2 Complete)
```swift
public func makePlan(for intent: InstallIntent, context: SystemContext) async -> InstallPlan {
    // TODO: Phase 3 - Wire up WizardAutoFixer, LaunchDaemonInstaller, etc.
    // Returns stub plan with empty recipes
}
```

### End State (Phase 3 Complete)
```swift
public func makePlan(for intent: InstallIntent, context: SystemContext) async -> InstallPlan {
    // 1. Check requirements → block if unmet
    // 2. Determine actions needed based on intent + context
    // 3. Generate ServiceRecipes from actions
    // 4. Order recipes respecting dependencies
    // 5. Return InstallPlan with recipes and status
}
```

---

## 🎯 Success Criteria

Phase 3 is complete when:

- [x] `makePlan()` returns real plans (not stubs)
- [ ] Plans contain ordered `ServiceRecipe`s
- [ ] Plans are blocked when requirements unmet
- [ ] All 4 intents (`.install`, `.repair`, `.uninstall`, `.inspectOnly`) work correctly
- [ ] Tests verify plan generation for all scenarios
- [ ] Build succeeds, no compilation errors
- [ ] Code follows "boring API" principle

---

## 📊 Estimated Scope

- **Files to modify:** 1 (`InstallerEngine.swift`)
- **Files to create:** 0 (reuse existing types)
- **Tests to add:** ~10-15 test methods
- **Estimated time:** 4-6 hours
- **Complexity:** Medium (requires understanding existing planning logic)

---

## 🚀 Next Steps

1. Understand how `SystemSnapshotAdapter` determines auto-fix actions
2. Understand how `WizardAutoFixer` maps issues to actions
3. Implement requirement checking logic
4. Implement intent → action mapping
5. Implement recipe generation
6. Add tests
7. Verify against existing behavior


