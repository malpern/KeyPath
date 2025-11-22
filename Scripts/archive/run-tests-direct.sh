#!/bin/bash
set -euo pipefail

# Direct XCTest runner - bypasses SwiftPM test aggregator to avoid Swift 6.2 beta crash
# This runs the XCTest bundle directly with xcrun xctest

echo "Building tests..."
swift build --build-tests

echo "Locating test bundle..."
BIN_DIR=$(swift build --build-tests --show-bin-path)
BUNDLE=""

# Try to find the test bundle
if [ -d "$BIN_DIR/KeyPathPackageTests.xctest" ]; then
    BUNDLE="$BIN_DIR/KeyPathPackageTests.xctest"
elif [ -d "$BIN_DIR/KeyPathTests.xctest" ]; then
    BUNDLE="$BIN_DIR/KeyPathTests.xctest"
else
    # Pick any .xctest if naming differs
    BUNDLE=$(ls "$BIN_DIR"/*.xctest 2>/dev/null | head -n1 || true)
fi

if [ -z "${BUNDLE:-}" ] || [ ! -d "$BUNDLE" ]; then
    echo "❌ Could not locate an XCTest bundle in $BIN_DIR"
    exit 1
fi

echo "Running tests directly via xcrun xctest..."
echo "→ Bundle: $BUNDLE"

# Run the tests directly, bypassing SwiftPM
set +e
xcrun xctest "$BUNDLE"
status=$?
set -e

if [ $status -eq 0 ]; then
    echo "✅ All tests passed (via direct xctest execution)"
    exit 0
else
    echo "❌ Tests failed with exit code $status"
    exit $status
fi