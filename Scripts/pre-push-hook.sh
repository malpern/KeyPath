#!/bin/bash
# Pre-push hook for KeyPath
# Runs all automated tests and blocks push if any fail.

cd "$(git rev-parse --show-toplevel)"

echo "🧪 Running all tests before push..."

# Run tests, stream output to a temp file to avoid null byte issues
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

KEYPATH_SNAPSHOTS=1 swift test > "$TMPFILE" 2>&1
TEST_EXIT=$?

# Show summary (last 5 lines)
tail -5 "$TMPFILE"

if [ $TEST_EXIT -ne 0 ]; then
    echo ""
    echo "❌ Tests failed (exit code $TEST_EXIT). Push blocked."
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 swift test' to see full output."
    exit 1
fi

# Check for XCTest failures
if grep -q "Test Case.*failed" "$TMPFILE"; then
    echo ""
    echo "❌ Test failures detected. Push blocked."
    grep "Test Case.*failed" "$TMPFILE"
    echo ""
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 swift test' to see full output."
    exit 1
fi

echo "✅ All tests passed. Pushing..."
