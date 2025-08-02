# Installation Wizard Tests

Tests real system behavior over mocks - system state detection, auto-fixing, and navigation logic.

Run: `swift test --filter InstallationWizardTests`

## Test Approach

### SystemStateDetectorTests
- **Real system integration** - Tests against actual running processes, permissions, components
- **Validates detection logic** - Ensures we correctly identify real system conflicts and states
- **Performance testing** - Measures actual detection speed and concurrent operation handling
- **Consistency validation** - Verifies detection results match KanataManager state

### WizardAutoFixerTests  
- **Safe operations only** - Tests non-destructive auto-fix actions (directory creation, daemon management)
- **Capability validation** - Confirms what auto-fix actions are actually supported
- **Real workflow testing** - Tests complete auto-fix workflows with actual system state
- **Careful with destructive operations** - Process termination and component installation tested for capability only

### WizardNavigationEngineTests
- **Pure function testing** - Navigation logic doesn't touch system, so traditional unit testing works well
- **Logic validation** - Tests page determination, button states, progress calculation
- **Integration with real states** - Uses real system states from detector to test navigation

## Why This Approach?

### Problems with Heavy Mocking
```swift
// ❌ Mock testing often creates false confidence:
mockKanataManager.mockProcessOutput = "12345 /usr/local/bin/kanata"
// This doesn't test if we can actually parse real pgrep output

// ✅ Integration testing finds real issues:  
let conflicts = await detector.detectConflicts() // Real pgrep call
// This tests our parsing with actual system data
```

### Benefits of Real System Testing
1. **Finds real parsing bugs** - Our process detection logic is tested with actual pgrep output
2. **Validates system integration** - Tests that our logic works with real permissions, paths, etc.
3. **Catches environment issues** - Finds problems specific to macOS versions, system configurations
4. **Tests performance** - Real system calls reveal actual performance characteristics
5. **Builds confidence** - If tests pass, the wizard will work in the real environment

## Test Safety

### Safe Operations (Always Tested)
- Directory creation (`createConfigDirectories`)
- Daemon status checking
- Permission checking  
- Process detection
- VirtualHID daemon restart

### Dangerous Operations (Capability-Only Testing)
- Process termination - Only test capability, don't kill running processes
- Component installation - Would require admin privileges and brew
- Major system changes - Test logic but not execution

## Expected Results

Tests will vary based on actual system state:
- If Kanata is running → Conflict detection tests will find real processes
- If permissions missing → Permission tests will identify actual missing permissions  
- If components installed → Component tests will reflect real installation state

This variability is **expected and valuable** - it means our tests work with real system conditions.

## Running Tests

```bash
swift test --filter InstallationWizardTests
```

Tests will output detailed information about detected system state, making them useful for debugging actual system issues during development.

## Future Improvements

While this integration approach is more realistic, we could enhance it with:

1. **Test environment containers** - Isolated test environments for destructive operations
2. **Selective mocking** - Mock only truly dangerous operations (system shutdown, etc.)
3. **CI environment handling** - Different test behavior in CI vs development
4. **System state fixtures** - Prepared test scenarios for edge cases

The current approach successfully validates that our wizard works with real system state while being safe for development use.