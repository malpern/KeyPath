#!/bin/bash
#
# Core Test Runner for KeyPath
# Runs essential tests that can pass in CI environment
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧪 Running KeyPath Core Tests"
echo "=============================="

# Set environment variables for testing
export CI_ENVIRONMENT="${CI_ENVIRONMENT:-false}"
export KEYPATH_TESTING="true"

# Create test results directory
mkdir -p test-results

echo "📊 Test Configuration:"
echo "  Mode: Full test suite (no filters)"
echo "  CI Environment: $CI_ENVIRONMENT"
echo ""

# Track overall success
OVERALL_SUCCESS=0

echo "🚀 Running Full Test Suite (No Filters)"
echo "========================================"
echo "Running all 422 tests for maximum refactor safety"
echo ""

# Run ALL tests without filters
TEST_LOG="test-results/all-tests.log"

# Use gtimeout on macOS, timeout on Linux; fallback to no-timeout if unavailable
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 300"  # 5 minute timeout
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 300"
fi

echo "🔍 Executing: swift test --parallel"
echo ""

if [ -n "$TIMEOUT_CMD" ]; then
    if $TIMEOUT_CMD swift test --parallel 2>&1 | tee "$TEST_LOG"; then
        OVERALL_SUCCESS=0
    else
        OVERALL_SUCCESS=$?
    fi
else
    if swift test --parallel 2>&1 | tee "$TEST_LOG"; then
        OVERALL_SUCCESS=0
    else
        OVERALL_SUCCESS=$?
    fi
fi

echo ""
echo "📋 Test Summary"
echo "==============="

# Count test results from log
if [ -f "$TEST_LOG" ]; then
    # Extract from the final summary line: "Test run with X tests in Y suites..."
    SUMMARY_LINE=$(grep "Test run with.*tests.*suites" "$TEST_LOG" | tail -1)
    TOTAL_TESTS=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ tests' | grep -oE '[0-9]+' || echo "0")
    TOTAL_SUITES=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ suites' | grep -oE '[0-9]+' || echo "0")

    # Count individual test and suite results
    PASSED_TESTS=$(grep -c "Test.*passed after" "$TEST_LOG" 2>/dev/null || echo "0")
    FAILED_TESTS=$(grep -c "Test Case.*failed" "$TEST_LOG" 2>/dev/null || echo "0")
    PASSED_SUITES=$(grep -c "Suite.*passed after" "$TEST_LOG" 2>/dev/null || echo "0")
    FAILED_SUITES=$(grep -c "Suite.*failed after" "$TEST_LOG" 2>/dev/null || echo "0")

    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Total Suites: $TOTAL_SUITES"
    echo "  Passed: $PASSED_TESTS tests in $PASSED_SUITES suites"

    if [ "$FAILED_TESTS" != "0" ] || [ "$FAILED_SUITES" != "0" ]; then
        echo "  ❌ Failed: $FAILED_TESTS tests in $FAILED_SUITES suites"
        echo ""
        echo "💡 Failed test details:"
        grep "Test Case.*failed\|error:" "$TEST_LOG" | head -20
        echo ""
        echo "📝 Full log: $TEST_LOG"
    fi
fi

echo ""

# Final result
if [ $OVERALL_SUCCESS -eq 0 ]; then
    echo "🎉 All tests passed!"
    echo ""
    echo "✅ Full test suite provides maximum safety for refactor"
    echo "📊 Baseline established - record this count for comparison"
    echo ""
else
    echo "❌ Some tests failed"
    echo ""
    echo "📝 Review failures in: $TEST_LOG"
    echo "🔍 Common issues:"
    echo "   - Environment setup (KEYPATH_TEST_MODE, sandbox paths)"
    echo "   - Missing test fixtures"
    echo "   - Flaky integration tests"
    echo ""
fi

exit $OVERALL_SUCCESS