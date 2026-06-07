#!/bin/bash
# Pre-push hook for KeyPath
# Runs all automated tests and blocks push if any fail.

cd "$(git rev-parse --show-toplevel)"

if [ -t 0 ]; then
    PUSH_UPDATES=""
else
    PUSH_UPDATES=$(cat)
fi
if [ -n "$PUSH_UPDATES" ]; then
    NON_DELETE_UPDATES=$(printf '%s\n' "$PUSH_UPDATES" | awk '$2 !~ /^0+$/ { print; found=1 } END { exit found ? 0 : 1 }' || true)
    if [ -z "$NON_DELETE_UPDATES" ]; then
        echo "🧹 Branch deletion push detected; skipping pre-push tests."
        exit 0
    fi
fi

echo "🧪 Running all tests before push..."

TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

if KEYPATH_SNAPSHOTS=1 ./Scripts/run-tests-safe.sh > "$TMPFILE" 2>&1; then
    tail -5 "$TMPFILE"
    echo "✅ All tests passed. Pushing..."
    exit 0
fi

# Show summary
tail -5 "$TMPFILE"

# Check for actual test failures (not skipped tests or SPM warnings)
if grep -q "Test Case.*failed" "$TMPFILE"; then
    echo ""
    echo "❌ Test failures detected. Push blocked."
    grep "Test Case.*failed" "$TMPFILE"
    echo ""
    echo "💡 Run 'KEYPATH_SNAPSHOTS=1 ./Scripts/run-tests-safe.sh' to see full output."
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

echo ""
echo "❌ Test command failed. Push blocked."
echo "💡 Run 'KEYPATH_SNAPSHOTS=1 ./Scripts/run-tests-safe.sh' to see full output."
exit 1
