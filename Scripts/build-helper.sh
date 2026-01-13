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
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"
if [ "${KP_SIGN_DRY_RUN:-0}" != "1" ] && [ "$SKIP_CODESIGN" != "1" ]; then
    if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
        echo "❌ ERROR: codesign identity not found: $SIGNING_IDENTITY" >&2
        echo "Available identities:" >&2
        security find-identity -v -p codesigning >&2 || true
        echo "💡 TIP: Set CODESIGN_IDENTITY to a valid Developer ID Application identity." >&2
        exit 1
    fi
fi

# Build helper with embedded Info.plist
echo "1️⃣  Building helper executable..."
HELPER_INFO_PLIST="Sources/KeyPathHelper/Info.plist"

if [ ! -f "$HELPER_INFO_PLIST" ]; then
    echo "❌ ERROR: Helper Info.plist not found: $HELPER_INFO_PLIST"
    exit 1
fi

swift build --configuration release --product "$HELPER_NAME" \
    -Xswiftc -no-whole-module-optimization \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$HELPER_INFO_PLIST"

# The executable is at BUILD_DIR/HELPER_NAME (not in a subdirectory)
HELPER_EXECUTABLE="$BUILD_DIR/$HELPER_NAME"

if [ ! -f "$HELPER_EXECUTABLE" ]; then
    echo "❌ ERROR: Helper executable not found at: $HELPER_EXECUTABLE"
    exit 1
fi

if [ "$SKIP_CODESIGN" = "1" ]; then
    echo "⏭️  Skipping helper codesign (SKIP_CODESIGN=1)"
else
    echo "2️⃣  Signing helper..."
    HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"

    if [ -f "$HELPER_ENTITLEMENTS" ]; then
        codesign --force --options=runtime \
            --identifier "com.keypath.helper" \
            --entitlements "$HELPER_ENTITLEMENTS" \
            --sign "$SIGNING_IDENTITY" \
            --timestamp \
            "$HELPER_EXECUTABLE"
    else
        echo "❌ ERROR: Helper entitlements not found: $HELPER_ENTITLEMENTS"
        exit 1
    fi
fi

echo ""
echo "✅ Helper build complete: $HELPER_EXECUTABLE"
