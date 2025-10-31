#!/bin/bash
#
# Build and sign KeyPathHelper (privileged helper tool)
# This script is called by build-and-sign.sh for release builds
#
# Prerequisites:
# - Developer ID Application certificate
# - Helper source files in Sources/KeyPathHelper/
# - Entitlements in Sources/KeyPathHelper/KeyPathHelper.entitlements
#
# Output:
# - Signed helper binary ready to embed in main app
#

set -e  # Exit on error

echo "🔐 Building KeyPathHelper (privileged helper)..."

# Configuration
HELPER_NAME="KeyPathHelper"
BUILD_DIR=".build/arm64-apple-macosx/release"
HELPER_BUILD_DIR="${BUILD_DIR}/${HELPER_NAME}"
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Build helper
echo "1️⃣  Building helper executable..."
swift build --configuration release --product "$HELPER_NAME" -Xswiftc -no-whole-module-optimization

# The executable is at BUILD_DIR/HELPER_NAME (not in a subdirectory)
HELPER_EXECUTABLE="$BUILD_DIR/$HELPER_NAME"

if [ ! -f "$HELPER_EXECUTABLE" ]; then
    echo "❌ ERROR: Helper executable not found at: $HELPER_EXECUTABLE"
    exit 1
fi

echo "2️⃣  Signing helper..."
HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"

if [ -f "$HELPER_ENTITLEMENTS" ]; then
    codesign --force --options=runtime \
        --identifier "com.keypath.helper" \
        --entitlements "$HELPER_ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        "$HELPER_EXECUTABLE"
else
    echo "❌ ERROR: Helper entitlements not found: $HELPER_ENTITLEMENTS"
    exit 1
fi

echo ""
echo "✅ Helper build complete: $HELPER_EXECUTABLE"
