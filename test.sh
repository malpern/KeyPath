#!/bin/bash

# run-tests.sh
# Main test runner - uses automated passwordless approach by default

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 KeyPath Test Runner"
echo "======================"

# Check if automated test runner exists (local development only)
if [ -f "$SCRIPT_DIR/run-tests-automated.sh" ] && [ "$KEYPATH_MANUAL_TESTS" != "true" ]; then
    echo "🚀 Using automated test runner (passwordless sudo)..."
    echo "💡 To use manual testing: KEYPATH_MANUAL_TESTS=true ./run-tests.sh"
    echo ""
    exec "$SCRIPT_DIR/run-tests-automated.sh"
fi

# Manual testing mode
echo "⚠️  Manual testing mode - you may be prompted for passwords"
echo "💡 Create run-tests-automated.sh locally for passwordless testing"
echo ""

# Fallback to manual testing
echo "Running Swift unit tests (safe runner)..."
"$SCRIPT_DIR/Scripts/run-tests-safe.sh"

echo ""
echo "Running integration tests..."
./Scripts/test-scripts/system/test-kanata-system.sh
./Scripts/test-hot-reload.sh
./Scripts/test-installer.sh

echo ""
echo "All tests completed successfully!"