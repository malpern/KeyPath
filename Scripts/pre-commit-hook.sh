#!/bin/bash
# Pre-commit hook for KeyPath
# Blocks commit if tests fail. Runs all automated tests including snapshots.

set -e
cd "$(git rev-parse --show-toplevel)"

# Check if any Swift source, test, or package files are staged
STAGED_SWIFT=$(git diff --cached --name-only --diff-filter=ACM | grep "\.swift$" || true)
STAGED_PACKAGE=$(git diff --cached --name-only --diff-filter=ACM | grep "Package.swift" || true)

if [ -z "$STAGED_SWIFT" ] && [ -z "$STAGED_PACKAGE" ]; then
    exit 0
fi

# --- Accessibility check (warning only) ---
STAGED_UI_FILES=$(echo "$STAGED_SWIFT" | grep "^Sources/KeyPathAppKit/UI/" || true)
if [ -n "$STAGED_UI_FILES" ]; then
    echo "♿ Checking accessibility identifiers in staged UI files..."
    if python3 Scripts/check-accessibility.py 2>&1 | grep -q "Found.*issue"; then
        echo ""
        echo "⚠️  WARNING: Some UI elements are missing accessibility identifiers"
        echo "💡 This won't block your commit, but please add identifiers for automation"
        echo "💡 See ACCESSIBILITY_COVERAGE.md for examples"
        echo ""
    fi
fi

# --- Run all tests in one pass (blocking) ---
echo "🧪 Running unit, integration, and snapshot tests..."

TEST_OUTPUT=$(KEYPATH_SNAPSHOTS=1 swift test 2>&1)
TEST_EXIT=$?

# Show summary
echo "$TEST_OUTPUT" | tail -5

if [ $TEST_EXIT -ne 0 ]; then
    echo ""
    echo "❌ Tests failed (exit code $TEST_EXIT). Commit blocked."
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 swift test' to see full output."
    exit 1
fi

# Check for XCTest failures (swift test can exit 0 with XCTest failures)
if echo "$TEST_OUTPUT" | grep -q "Test Case.*failed"; then
    FAILURE_COUNT=$(echo "$TEST_OUTPUT" | grep -c "Test Case.*failed" || true)
    echo ""
    echo "❌ $FAILURE_COUNT test(s) failed. Commit blocked."
    echo "$TEST_OUTPUT" | grep "Test Case.*failed"
    echo ""
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 swift test' to see full output."
    echo "💡 To update snapshots: SNAPSHOT_RECORD=1 swift test --filter SnapshotTests"
    exit 1
fi

echo "✅ All tests passed."
