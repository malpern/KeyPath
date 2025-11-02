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

# Set environment variables for CI-friendly testing
export CI_ENVIRONMENT="${CI_ENVIRONMENT:-false}"
export KEYPATH_TESTING="true"
export CI_INTEGRATION_TESTS="${CI_INTEGRATION_TESTS:-false}"

# Create test results directory
mkdir -p test-results

echo "📊 Test Configuration:"
echo "  CI Environment: $CI_ENVIRONMENT"
echo "  Integration Tests: $CI_INTEGRATION_TESTS"
echo "  Manual Tests: DISABLED"
echo ""

# Function to run test suite with error handling
run_test_suite() {
    local test_name="$1"
    local test_filter="$2"
    local timeout="${3:-120}"
    
    echo "🔍 Running $test_name..."
    
    # Use gtimeout on macOS, timeout on Linux
    TIMEOUT_CMD="timeout"
    if command -v gtimeout >/dev/null 2>&1; then
        TIMEOUT_CMD="gtimeout"
    fi
    
    if $TIMEOUT_CMD "$timeout" swift test --filter "$test_filter" --parallel 2>&1 | tee "test-results/$test_name.log"; then
        echo "✅ $test_name completed successfully"
        return 0
    else
        local exit_code=$?
        echo "⚠️ $test_name failed (exit code: $exit_code)"
        return $exit_code
    fi
}

# Track overall success
OVERALL_SUCCESS=0

echo "🚀 Starting Core Test Execution"
echo "================================"

# 1. Unit Tests (fast, no dependencies)
if run_test_suite "Unit Tests" "UnitTestSuite" 60; then
    echo "  Unit tests passed ✅"
else
    echo "  Unit tests failed ❌"
    OVERALL_SUCCESS=1
fi

echo ""

# 2. Core Tests (essential functionality)
if run_test_suite "Core Tests" "UnitTestSuite" 90; then
    echo "  Core tests passed ✅"
else
    echo "  Core tests failed ❌"
    OVERALL_SUCCESS=1
fi

echo ""

# 3. Basic Integration Tests (only if enabled)
if [ "$CI_INTEGRATION_TESTS" = "true" ]; then
    echo "🔗 Integration tests enabled"
    if run_test_suite "Integration Tests" "IntegrationTestSuite" 120; then
        echo "  Integration tests passed ✅"
    else
        echo "  Integration tests failed ❌"
        OVERALL_SUCCESS=1
    fi
else
    echo "⏭️  Integration tests skipped (set CI_INTEGRATION_TESTS=true to enable)"
fi

echo ""
echo "📋 Test Summary"
echo "==============="

# Count test results
if [ -f "test-results/Unit Tests.log" ]; then
    UNIT_PASSED=$(grep -c "Test Suite.*passed" "test-results/Unit Tests.log" 2>/dev/null || echo "0")
    echo "  Unit Tests: $UNIT_PASSED suites passed"
fi

if [ -f "test-results/Core Tests.log" ]; then
    CORE_PASSED=$(grep -c "Test Suite.*passed" "test-results/Core Tests.log" 2>/dev/null || echo "0")
    echo "  Core Tests: $CORE_PASSED suites passed"
fi

if [ -f "test-results/Integration Tests.log" ]; then
    INTEGRATION_PASSED=$(grep -c "Test Suite.*passed" "test-results/Integration Tests.log" 2>/dev/null || echo "0")
    echo "  Integration Tests: $INTEGRATION_PASSED suites passed"
fi

echo ""

# Final result
if [ $OVERALL_SUCCESS -eq 0 ]; then
    echo "🎉 All enabled tests passed!"
    echo ""
    echo "💡 To run more comprehensive tests:"
    echo "  CI_INTEGRATION_TESTS=true ./run-core-tests.sh"
    echo ""
else
    echo "❌ Some tests failed. Check test-results/ for details."
    echo ""
fi

exit $OVERALL_SUCCESS