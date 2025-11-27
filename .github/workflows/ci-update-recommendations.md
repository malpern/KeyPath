# CI Configuration Update Recommendations

## Issue: Mixed Test Frameworks

The test suite now contains both XCTest and Swift Testing tests, but CI only runs XCTest.

### Current Setup
- **CI Runner:** `xcrun xctest` (line 53 in ci.yml)
- **Supports:** XCTest only
- **Missing:** Swift Testing tests (4 new test files)

### New Test Files (Swift Testing)
1. `Tests/KeyPathTests/Core/KeyPathErrorTests.swift` - 23 tests
2. `Tests/KeyPathTests/Services/PermissionOracleTests.swift` - 16 tests
3. `Tests/KeyPathTests/Services/UserNotificationServiceTests.swift` - 8 tests
4. `Tests/KeyPathTests/MainAppStateControllerTests.swift` - 9 tests

**Total: 56 new tests not running in CI**

## Recommended Solutions

### Option 1: Use `swift test` (Recommended)
Replace the test runner to use Swift's built-in test command:

```yaml
- name: Run All Tests (Safe Runner)
  run: |
    echo "🧪 Running KeyPath tests via swift test"
    export CI_ENVIRONMENT=true
    export SKIP_EVENT_TAP_TESTS=1

    # Run tests with timeout
    timeout 240 swift test || TEST_EXIT=$?

    if [ "${TEST_EXIT:-0}" -eq 0 ]; then
      echo "✅ All tests passed"
      echo "TEST_STATUS=passed" >> $GITHUB_ENV
    elif [ "${TEST_EXIT:-0}" -eq 124 ]; then
      echo "⏰ Tests timed out after 240s"
      echo "TEST_STATUS=timeout" >> $GITHUB_ENV
      exit 1
    else
      echo "❌ Tests failed"
      echo "TEST_STATUS=failed" >> $GITHUB_ENV
      exit 1
    fi
```

**Pros:**
- Runs both XCTest and Swift Testing tests
- Native Swift toolchain support
- Simpler configuration

**Cons:**
- May still hit Swift 6 concurrency errors in pre-existing tests

### Option 2: Update run-tests-safe.sh Script
Enhance the existing script to support both test frameworks:

```bash
#!/bin/bash
set -euo pipefail

TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-240}

echo "🧪 Running tests with dual framework support..."

export SWIFT_TEST=1
export SKIP_EVENT_TAP_TESTS=1
export CI_ENVIRONMENT=${CI_ENVIRONMENT:-false}
export NSUnbufferedIO=YES

# Try swift test first (supports both frameworks)
LOG=./test_output.safe.txt
rm -f "$LOG"

echo "🚀 Running swift test..."
timeout ${TIMEOUT_SECONDS}s swift test 2>&1 | tee "$LOG" || EXIT_CODE=$?

if [ "${EXIT_CODE:-0}" -eq 0 ]; then
  echo "✅ All tests passed"
  exit 0
elif [ "${EXIT_CODE:-0}" -eq 124 ]; then
  echo "⏰ Tests timed out"
  exit 124
else
  # Check if any tests passed
  if grep -q "Test Suite.*passed" "$LOG"; then
    echo "⚠️ Some tests passed but suite failed"
  fi
  echo "❌ Test run failed (exit ${EXIT_CODE:-1})"
  exit ${EXIT_CODE:-1}
fi
```

### Option 3: Separate Test Jobs (Most Robust)
Run XCTest and Swift Testing separately:

```yaml
jobs:
  test-xctest:
    runs-on: macos-latest
    steps:
      # ... existing setup ...
      - name: Run XCTest Suite
        run: bash Scripts/run-tests-safe.sh

  test-swift-testing:
    runs-on: macos-latest
    steps:
      # ... existing setup ...
      - name: Run Swift Testing Suite
        run: |
          swift test --filter KeyPathErrorTests
          swift test --filter PermissionOracleTests
          swift test --filter UserNotificationServiceTests
          swift test --filter MainAppStateControllerTests
```

## Expected CI Behavior After Update

### ✅ Tests That Should Pass
- `KeyPathErrorTests` (23 tests) - New, no dependencies
- `PermissionOracleTests` (16 tests) - New, no dependencies
- `UserNotificationServiceTests` (8 tests) - New, no dependencies
- `MainAppStateControllerTests` (9 tests) - New, no dependencies

### ⚠️ Tests With Known Issues (Pre-existing)
- `KeyboardCaptureTests` - Swift 6 actor isolation errors
- `ErrorHandlingTests` - Swift 6 actor isolation errors
- `ProcessLifecycleIntegrationTests` - Actor isolation errors
- Other integration tests requiring sudo/permissions

## Immediate Action Required

**Minimum change to capture new tests:**

Update `.github/workflows/ci.yml` line 39-51 from:
```yaml
- name: Run All Tests (Safe Runner)
  run: |
    echo "🧪 Running KeyPath tests via safe runner"
    export CI_ENVIRONMENT=true
    export SWIFT_TEST=1
    export SKIP_EVENT_TAP_TESTS=1
    bash Scripts/run-tests-safe.sh || true
```

To:
```yaml
- name: Run All Tests (Swift Test + XCTest)
  run: |
    echo "🧪 Running KeyPath tests with swift test"
    export CI_ENVIRONMENT=true
    export SKIP_EVENT_TAP_TESTS=1

    # Run swift test (supports both frameworks)
    if timeout 240 swift test; then
      echo "TEST_STATUS=passed" >> $GITHUB_ENV
    else
      echo "TEST_STATUS=failed" >> $GITHUB_ENV
      echo "⚠️ Some tests failed - continuing build verification"
      exit 0  # Don't fail CI on test failures (matches current behavior)
    fi
```

## Test Coverage Impact

**Before:** ~50 XCTest tests running in CI
**After:** ~106 tests (50 XCTest + 56 Swift Testing) running in CI

This represents a **112% increase in test coverage** for CI builds.

## New: Signing + Installer Smoke (added)

The CI workflow now runs two fast smoke suites after the build:
- `swift test --filter SigningPipelineTests` with `KP_SIGN_DRY_RUN=1` to ensure the codesign/notary wrappers surface failures even when tools are overridden.
- `swift test --filter InstallerEngineEndToEndTests` to verify the InstallerEngine executes a plan and stops on the first broker failure using an injectable coordinator.

These add <1s each and catch the highest-risk regression areas (distribution + system setup) without needing Apple notary services or root operations in CI.

## Optional Pre-Release on Real Mac
- Run `KEYPATH_E2E_DEVICE=1 swift test --filter InstallerDeviceTests` (non-destructive installer smoke against real permissions/launchd surfaces).
- Or `KEYPATH_E2E_DEVICE=1 ./Scripts/test-installer-device.sh` (wrapper script).
- Keep `KEYPATH_ALLOW_PRIV=1` unset unless you explicitly want privileged repair/install (not run by default).
