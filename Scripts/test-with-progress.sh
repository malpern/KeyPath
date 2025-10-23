#!/bin/bash
LOGFILE="/tmp/test-output-$$.log"

# Get total test count
echo "Counting tests..."
TOTAL=$(swift test --list-tests 2>/dev/null | grep -c "KeyPathTests\.")
echo "Found $TOTAL tests"
echo ""

# Run tests in background, logging to file
swift test > "$LOGFILE" 2>&1 &
TEST_PID=$!

# Monitor progress
echo "Running tests..."
LAST_COUNT=0
while kill -0 $TEST_PID 2>/dev/null; do
    if [ -f "$LOGFILE" ]; then
        COUNT=$(grep -c "passed\|failed" "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$COUNT" -gt "$LAST_COUNT" ]; then
            PERCENT=$((COUNT * 100 / TOTAL))
            printf "\r[%3d%%] %d/%d tests" "$PERCENT" "$COUNT" "$TOTAL"
            LAST_COUNT=$COUNT
        fi
    fi
    sleep 0.5
done

# Wait for completion
wait $TEST_PID
EXIT_CODE=$?

# Final count
COUNT=$(grep -c "passed\|failed" "$LOGFILE" 2>/dev/null || echo 0)
PERCENT=$((COUNT * 100 / TOTAL))
printf "\r[%3d%%] %d/%d tests\n" "$PERCENT" "$COUNT" "$TOTAL"

# Show summary
echo ""
tail -5 "$LOGFILE" | grep "Test run"

# Cleanup
rm -f "$LOGFILE"

exit $EXIT_CODE
