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

# Create helper bundle structure (required for SMJobBless)
echo "2️⃣  Creating helper bundle structure..."
rm -rf "$HELPER_BUILD_DIR"
mkdir -p "$HELPER_BUILD_DIR"

# Copy executable
cp "$BUILD_DIR/$HELPER_NAME" "$HELPER_BUILD_DIR/"

# TODO: Embed Info.plist and launchd.plist
# SMJobBless requires these to be embedded in specific locations
# This might require a custom build phase or tool like PlistBuddy
# For now, document the requirement

echo "3️⃣  Signing helper..."
HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"

if [ -f "$HELPER_ENTITLEMENTS" ]; then
    codesign --force --options=runtime \
        --entitlements "$HELPER_ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        "$HELPER_BUILD_DIR/$HELPER_NAME"
else
    echo "❌ ERROR: Helper entitlements not found: $HELPER_ENTITLEMENTS"
    exit 1
fi

echo "4️⃣  Verifying helper signature..."
codesign -dvvv "$HELPER_BUILD_DIR/$HELPER_NAME"

echo "✅ Helper build complete: $HELPER_BUILD_DIR/$HELPER_NAME"
