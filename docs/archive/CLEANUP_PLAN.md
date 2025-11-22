# KeyPath Codebase Cleanup Plan

## 📊 Current State
- **Root Directory**: 117 files (target: ~20)
- **Test Scripts in Root**: 34 files (should be 0)
- **Debug Scripts in Root**: 10 files (should be 0)
- **Documentation Files**: 20 files (target: ~8)
- **Obsolete Test Directory**: `Tests/InstallationWizardTests.disabled/`

## 🎯 Cleanup Goals
1. **Reduce root directory clutter by 70%**
2. **Organize test files properly**  
3. **Remove obsolete documentation**
4. **Consolidate build scripts**
5. **Remove dead test code**

## 📋 PHASE 1: Root Directory Cleanup

### A. Test Files to Move (34 files)
**Target: `Tests/scripts/` or delete if obsolete**

#### Oracle Test Files (Keep - Recently Created)
```
test-oracle-system.swift           -> Tests/scripts/oracle/
test-oracle-comprehensive.swift   -> Tests/scripts/oracle/
test-oracle-validation.swift      -> Tests/scripts/oracle/
test-oracle-live.swift           -> Tests/scripts/oracle/
```

#### Permission Test Files (Evaluate - May be obsolete after Oracle)
```
test-permission-apis.swift        -> Evaluate for Oracle migration
test-permission-flow.swift        -> Evaluate for Oracle migration  
test-fresh-permissions.swift      -> Likely obsolete
```

#### Service/System Test Files (Some useful, some obsolete)
```
test-service-health.swift         -> Tests/scripts/system/ or delete
test-service-diagnosis.swift      -> Tests/scripts/system/ or delete
test-kanata-system.sh             -> Tests/scripts/system/
test-hot-reload.sh                -> Tests/scripts/system/
test-installer.sh                 -> Tests/scripts/system/
test-service-status.sh            -> Tests/scripts/system/
```

#### Config Test Files (Some useful)
```
test-config-*.swift               -> Tests/scripts/config/
test-tcp-*.swift                  -> Tests/scripts/tcp/
```

#### Debug Test Files (Move to dev-tools)
```
test-admin-*.swift                -> dev-tools/
test-wizard-*.swift               -> dev-tools/ or delete
test-ui-*.swift                   -> dev-tools/
```

#### Obsolete Test Files (DELETE)
```
test-fresh-install.swift          -> Delete (obsolete)
test-enhanced-error-handling.swift -> Delete (obsolete) 
test-improved-*.swift              -> Delete (obsolete)
test-actual-*.swift                -> Delete (duplicates)
test-real-*.swift                  -> Delete (duplicates)
```

### B. Debug Files to Move (10 files)
**Target: `dev-tools/debug/`**
```
debug-*.swift                     -> dev-tools/debug/
```

### C. Documentation Files Cleanup (20 -> 8 files)

#### Keep (Core Documentation)
```
README.md                         -> Keep
CLAUDE.md                         -> Keep  
ARCHITECTURE.md                   -> Keep
INPUT_MONITORING_FIX.md          -> Keep
CONSOLIDATE.md                    -> Archive after cleanup
```

#### Archive (Outdated but Historical)
```
advice.md                         -> docs/archive/
ASSESSMENT.md                     -> docs/archive/
BACKUPFIX.md                      -> docs/archive/
DEPLOYMENT_PASSWORD_FIX.md       -> docs/archive/
BUILD_PERFORMANCE_ANALYSIS.md    -> docs/archive/
```

#### Delete (Obsolete)
```
dual-process-hot-reload-analysis.md -> Delete
INSTALLER-IMPROVEMENT.md          -> Delete
KANATA_WATCH_BUG_REPORT.md        -> Delete
kanata-*.md                       -> Delete (multiple bug reports)
UIFEEDBACK.md                     -> Delete
WATCHBUG.md                       -> Delete
WIZARD_PERFORMANCE_IMPLEMENTATION.md -> Delete
```

### D. Build Script Consolidation (22 -> 8 files)

#### Keep (Essential)
```
build-and-sign.sh                 -> Keep
build.sh                          -> Keep
Scripts/build.sh                  -> Keep (different from root)
dev-deploy.sh                     -> Keep
dev-rebuild.sh                    -> Keep
```

#### Delete (Redundant)
```
build-fixed.sh                    -> Delete
build-fix.sh                      -> Delete  
compile.sh                        -> Delete
build-and-sign.sh                 -> Delete (duplicate)
install-*.sh                      -> Evaluate/Delete
reinstall-*.swift                 -> Delete
reload-*.swift                    -> Delete
restart-*.swift                   -> Delete
update-*.swift                    -> Delete
```

## 📋 PHASE 2: Test Directory Cleanup

### A. Remove Dead Test Code
```
Tests/InstallationWizardTests.disabled/  -> Delete entire directory
Tests/KeyPathTests/SystemStateDetectorDebounceTests.swift -> Delete
```

### B. Audit Test Files for Obsolete Code
**Files to Review:**
```
PermissionServiceTests.swift      -> Update for Oracle or simplify
MockSystemEnvironment.swift       -> Check if still needed
WizardAutoFixerTests.swift        -> Update for Oracle integration
```

### C. Consolidate Mock Files
**Current Mocks:**
```
MockTCPServer.swift               -> Keep (TCP testing)
MockSystemEnvironment.swift       -> Evaluate necessity
```

## 📋 PHASE 3: Wizard Organization Analysis

### ✅ Current Wizard Structure (GOOD)
```
InstallationWizard/
├── Components/           (3 files)
│   ├── HelpSheets.swift
│   ├── PermissionCard.swift
│   └── StatusIndicators.swift
├── Core/                (13 files) 
│   ├── SystemStatusChecker.swift    (Oracle integrated ✅)
│   ├── WizardAsyncOperationManager.swift (Oracle integrated ✅)
│   ├── WizardAutoFixer.swift        (Oracle integrated ✅)
│   └── ... (other core logic)
└── UI/                  (20 files)
    ├── InstallationWizardView.swift
    ├── Components/      (7 files)
    └── Pages/          (10 files)
```

### 📊 Wizard Quality Assessment
- **Architecture**: A- (Clean separation, Oracle integrated)
- **File Count**: Appropriate (35 files for complex wizard)
- **Organization**: Good (logical grouping)
- **Dead Code**: Minimal (already cleaned up)

**Minor Improvements Needed:**
- Some wizard pages still have legacy PermissionService remnants
- Could consolidate some similar components
- Documentation could be clearer

## 📋 PHASE 4: Services & Managers Cleanup

### Services Directory Analysis (7 files)
```
PermissionOracle.swift            -> ✅ New, core system
PermissionService.swift           -> ✅ Slimmed down to safe APIs  
KanataTCPClient.swift            -> ✅ Oracle integrated
KeyboardCapture.swift            -> Keep (core functionality)
PreferencesService.swift         -> Keep (core functionality)
PIDFileManager.swift             -> Keep (core functionality)
SystemRequirementsChecker.swift  -> Evaluate (may overlap with Oracle)
```

**Potential Cleanup:**
- `SystemRequirementsChecker.swift` - May overlap with Oracle functionality

### Managers Directory Analysis (8 files)
```
SimpleKanataManager.swift        -> ✅ Oracle integrated
KanataManager.swift              -> ✅ Oracle integrated  
KanataLifecycleManager.swift     -> Keep
ProcessLifecycleManager.swift    -> Keep
LaunchAgentManager.swift         -> Removed (legacy launch agent path retired)
...
```

**Status: Clean** - Oracle integration complete

## 🎯 Expected Results After Cleanup

### File Count Reduction
```
Root Directory:    117 -> ~25 files (-78%)
Documentation:      20 -> ~8 files (-60%)  
Test Scripts:       34 -> 0 files (organized)
Debug Scripts:      10 -> 0 files (organized)
```

### Improved Organization
```
Tests/scripts/
├── oracle/          (Oracle test scripts)
├── system/          (System integration tests)
├── config/          (Configuration tests)
└── tcp/            (TCP functionality tests)

dev-tools/debug/     (Debug scripts)
docs/archive/        (Historical documentation)
```

### Benefits
1. **Developer Experience**: Easier to find files
2. **Maintenance**: Less confusion about what's active
3. **New Contributors**: Clearer project structure  
4. **Build Performance**: Fewer files to scan
5. **Git Performance**: Faster operations

## 🚀 Implementation Approach

### Phase 1 (Immediate - 30 min)
1. Create target directory structure
2. Move test scripts to appropriate locations
3. Move debug scripts to dev-tools

### Phase 2 (Quick - 15 min)  
1. Archive outdated documentation
2. Delete clearly obsolete files
3. Consolidate build scripts

### Phase 3 (Careful - 45 min)
1. Remove disabled test directory
2. Update imports/references
3. Test that everything still works

### Phase 4 (Optional - Later)
1. Further wizard component consolidation
2. Additional test file optimization
3. Documentation improvements

## ⚠️ Safety Measures

1. **Git Commit First**: Commit current state
2. **Branch for Cleanup**: Create cleanup branch
3. **Test After Each Phase**: Ensure builds still work
4. **Keep Git History**: Use `git mv` for moves
5. **Document Changes**: Update references

## 🎯 Success Criteria

- [ ] Root directory has <30 files
- [ ] All test scripts organized in Tests/scripts/
- [ ] Documentation reduced to essential files
- [ ] Build scripts consolidated
- [ ] No broken imports/references
- [ ] Project still builds and runs
- [ ] Git history preserved for moved files
