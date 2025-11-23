#!/bin/bash

# run-tests.sh
# Main test runner - uses automated passwordless approach by default

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_FILE="/etc/sudoers.d/keypath-testing"

echo "🧪 KeyPath Test Runner"
echo "======================"

# Check if automated test runner exists (local development only)
if [ -f "$SCRIPT_DIR/run-tests-automated.sh" ] && [ "$KEYPATH_MANUAL_TESTS" != "true" ]; then
    echo "🚀 Using automated test runner (passwordless sudo)..."
    echo "💡 To use manual testing: KEYPATH_MANUAL_TESTS=true ./run-tests.sh"
    echo ""
    exec "$SCRIPT_DIR/run-tests-automated.sh"
fi

# Check if sudoers is configured for passwordless testing
# TODO: TEMPORARY - Remove sudo mode before shipping
if [ -f "$SUDOERS_FILE" ] && [ "$KEYPATH_USE_SUDO" != "0" ]; then
    echo "🔓 Sudoers configured - enabling passwordless sudo mode"
    echo "   (Set KEYPATH_USE_SUDO=0 to disable)"
    export KEYPATH_USE_SUDO=1
elif [ "$KEYPATH_USE_SUDO" = "1" ]; then
    echo "🔓 KEYPATH_USE_SUDO=1 set - using sudo mode"
    echo "⚠️  Note: Run ./Scripts/setup-test-sudo.sh first if not already done"
else
    echo "⚠️  Manual testing mode - you may be prompted for passwords"
    echo "💡 Run ./Scripts/setup-test-sudo.sh for passwordless testing"
fi
echo ""

# Fallback to manual testing
echo "Running Swift unit tests (safe runner)..."
"$SCRIPT_DIR/Scripts/run-tests-safe.sh"

echo ""
echo "Running integration tests..."
./test-kanata-system.sh
./test-hot-reload.sh
./test-service-status.sh
./test-installer.sh

echo ""
echo "All tests completed successfully!"