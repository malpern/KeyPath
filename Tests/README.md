# KeyPath Test Architecture

**Simplified and CI-Optimized Test Suite**

## Overview

The KeyPath test suite has been reorganized from **67 test files** with **15,673 lines** into a streamlined, maintainable architecture focused on CI reliability and developer productivity.

## Test Structure

### Core Test Suites (Active)

#### 1. **UnitTestSuite.swift**
- **Purpose:** Fast unit tests for individual components
- **Dependencies:** None (pure unit tests)
- **Runtime:** ~30-60 seconds
- **Coverage:** Key mappings, configuration generation, state machines, utilities

#### 2. **CoreTestSuite.swift** 
- **Purpose:** Essential functionality tests with mocked dependencies
- **Dependencies:** MockSystemEnvironment
- **Runtime:** ~60-90 seconds  
- **Coverage:** Manager integration, wizard logic, error handling, TCP basics

#### 3. **BasicIntegrationTestSuite.swift**
- **Purpose:** Component integration without admin privileges
- **Dependencies:** Mock environment, disabled by default in CI
- **Runtime:** ~90-120 seconds
- **Coverage:** Cross-component workflows, end-to-end scenarios

### Legacy Tests (Deprecated)

Moved to `Tests/Deprecated/` folder:
- **TCP Tests:** 6 files (KanataManagerTCPTests, KanataTCPClientTests, etc.)
- **UI Automation:** 7 files (FlexibleUIAutomationTests, KeyPathUIAutomationTests, etc.) 
- **Complex Integration:** 2 files (RaceConditionIntegrationTests, AutonomousInstallationTests)

**Total Deprecated:** 15 files (~8,000 lines of test code)

## Running Tests

### Quick Test Run (CI Default)
```bash
./Scripts/test-fast.sh --changed
```
Selects the supported test lane for the files changed from the base branch.

### Full Test Run (Local Development)
```bash
./Scripts/test-full.sh
```
Runs the full safe SwiftPM test suite.

### Legacy Tests (Manual)
```bash
swift test --filter "IntegrationTests|TCPTests|UIAutomationTests"
```

## CI Integration

GitHub Actions uses the supported scripts under `Scripts/`; workflow files are
the source of truth for the current lane selection and artifact retention.

## Development Workflow

### Adding New Tests
1. **Simple logic/utilities** → Add to `UnitTestSuite.swift`
2. **Component integration** → Add to `CoreTestSuite.swift`  
3. **Complex workflows** → Add to `BasicIntegrationTestSuite.swift`
4. **Admin/manual tests** → Use separate test files (not in CI)
   - Example: `InstallerDeviceTests` (opt-in, gated by `KEYPATH_E2E_DEVICE=1`; non-destructive real-surface installer smoke)

### Test Environment
All core tests use `MockSystemEnvironment` for:
- File system operations
- Process management
- Permission checking
- Network connections
- System service interactions

## Benefits of New Architecture

### Performance Improvements
- **CI Runtime:** Reduced from ~10-15 minutes to ~3-5 minutes
- **Local Testing:** Quick feedback with focused test suites
- **Parallelization:** Tests run in parallel where safe

### Maintainability
- **Consolidated Logic:** Related tests grouped in single files
- **Clear Boundaries:** Unit vs Core vs Integration separation
- **Mock Strategy:** Consistent mocking approach across all tests

### CI Reliability  
- **No Admin Privileges:** All CI tests run in standard environment
- **No External Dependencies:** Self-contained test execution
- **Graceful Failures:** Test failures don't block build verification

## Migration Notes

### Deprecated Test Coverage
The deprecated tests provided extensive coverage for:
- TCP server edge cases
- UI automation scenarios  
- Race condition testing
- Complex installation flows

**These scenarios are now covered by:**
- Core tests with mocked implementations
- Manual testing procedures
- Integration test suite (when enabled)

### Future Considerations
- Consider re-enabling select deprecated tests as CI infrastructure improves
- Add performance benchmarking tests
- Implement code coverage reporting with core test suite

---
*Test suite reorganization completed as part of codebase simplification initiative*
