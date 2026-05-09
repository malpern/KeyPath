#!/bin/bash
# Pre-push hook for KeyPath
# Runs all automated tests and blocks push if any fail.

cd "$(git rev-parse --show-toplevel)"

echo "🧪 Running all tests before push..."

TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

KEYPATH_SNAPSHOTS=1 swift test > "$TMPFILE" 2>&1

# Show summary
tail -5 "$TMPFILE"

# Check for actual test failures (not skipped tests or SPM warnings)
if grep -q "Test Case.*failed" "$TMPFILE"; then
    echo ""
    echo "❌ Test failures detected. Push blocked."
    grep "Test Case.*failed" "$TMPFILE"
    echo ""
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 swift test' to see full output."
    exit 1
fi

# Check swift-testing failures
if grep -q "Test run with.*failed" "$TMPFILE"; then
    echo ""
    echo "❌ Swift Testing failures detected. Push blocked."
    grep "Test run with.*failed" "$TMPFILE"
    exit 1
fi

# Verify tests actually ran (guard against broken test infrastructure)
if ! grep -q "Test run with" "$TMPFILE" && ! grep -q "Executed" "$TMPFILE"; then
    echo ""
    echo "❌ No test output found — tests may not have run. Push blocked."
    exit 1
fi

echo "✅ All tests passed. Pushing..."
