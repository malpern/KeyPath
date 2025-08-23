#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -e  # Exit on any error

echo "🦀 Building bundled kanata..."
# Build kanata from source (required for proper signing)
./Scripts/build-kanata.sh

echo "🏗️  Building KeyPath..."
# Build main app (disable whole-module optimization to avoid hang)
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization

echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Clean and create directories
rm -rf "$DIST_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$CONTENTS/Library/KeyPath"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy bundled kanata binary
cp "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"

# Copy main app Info.plist
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"


# Create PkgInfo file (required for app bundles)
echo "APPL????" > "$CONTENTS/PkgInfo"

echo "✍️  Signing executables..."
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Sign bundled kanata binary (already signed in build-kanata.sh, but ensure consistency)
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata"

# Sign main app
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"

echo "📦 Creating distribution archive..."
cd "$DIST_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
cd ..

echo "📋 Submitting for notarization..."
xcrun notarytool submit "${DIST_DIR}/${APP_NAME}.zip" \
    --keychain-profile "KeyPath-Profile" \
    --wait

echo "🔖 Stapling notarization..."
xcrun stapler staple "$APP_BUNDLE"

echo "🎉 Build complete!"
echo "📍 Signed app: $APP_BUNDLE"
echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

echo "🔍 Final verification..."
spctl -a -vvv "$APP_BUNDLE"

echo "✨ Ready for distribution!"