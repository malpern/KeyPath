# Future Cleanup Tasks

## Kanata Binary Path Logic Simplification

**Context**: With the implementation of automatic kanata binary replacement (signed version), some of the old bundled kanata path logic is now redundant.

**Current State**: 
- `WizardSystemPaths.kanataActiveBinary` prefers bundled kanata, then falls back to system paths
- `WizardSystemPaths.allKnownKanataPaths()` includes bundled path for process detection
- KanataManager uses `kanataActiveBinary` throughout for binary path resolution

**New Approach**: 
- We now automatically replace system kanata at `/usr/local/bin/kanata` with Developer ID signed version
- LaunchDaemon always points to system location, not bundled location
- The bundled kanata preference logic is defensive but potentially unnecessary

**Cleanup Tasks**:

1. **Simplify `kanataActiveBinary`** - Since we ensure system kanata is signed, this could just return the standard system path instead of preferring bundled
   
2. **Update KanataManager references** - All uses of `WizardSystemPaths.kanataActiveBinary` could potentially be simplified to use standard system paths

3. **Clean up comments** - Remove references to "prefer bundled kanata" approach in comments and documentation

4. **Evaluate bundled path necessity** - Determine if bundled kanata path is still needed for any fallback scenarios

**Files to Review**:
- `Sources/KeyPath/InstallationWizard/Core/WizardSystemPaths.swift` (lines 23-42)
- `Sources/KeyPath/Managers/KanataManager.swift` (multiple references to `kanataActiveBinary`)
- `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift`
- `Sources/KeyPath/InstallationWizard/Core/SystemStatusChecker.swift`
- `Sources/KeyPath/Services/SystemRequirementsChecker.swift`

**Benefits of Cleanup**:
- Reduced code complexity
- Clearer logic flow (one canonical kanata path)
- Easier to reason about binary location
- Remove potential confusion between bundled vs system paths

**Risks**:
- Could break fallback scenarios if replacement fails
- May need thorough testing to ensure no edge cases are missed
- LaunchDaemon configuration might need updates

**Recommendation**: Defer until the signed binary replacement approach has been thoroughly tested in production.