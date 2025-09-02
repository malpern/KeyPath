#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app
# Usage: ./build-and-sign.sh [--skip-notarization]

set -e  # Exit on any error

# Parse command line arguments
SKIP_NOTARIZATION=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-notarization)
            SKIP_NOTARIZATION=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-notarization]"
            exit 1
            ;;
    esac
done

echo "🚀 Starting parallel build process..."

# Start kanata build in background
echo "🦀 Building bundled kanata (background)..."
./Scripts/build-kanata.sh &
KANATA_PID=$!

echo "🏗️  Building KeyPath (parallel)..."
# Build main app with parallel compilation
NCPU=$(sysctl -n hw.ncpu)
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization -j $NCPU

# Wait for kanata build to complete
echo "⏳ Waiting for kanata build to complete..."
wait $KANATA_PID
echo "✅ Kanata build finished"

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

# Kanata binary is already signed in build-kanata.sh, skip redundant signing
echo "ℹ️  Kanata binary already signed during build process"

# Sign main app
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"

if [ "$SKIP_NOTARIZATION" = true ]; then
    echo "⚠️  Skipping notarization (--skip-notarization flag provided)"
    echo "🎉 Build complete (local development build)!"
    echo "📍 Signed app: $APP_BUNDLE"
else
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
fi

if [ "$SKIP_NOTARIZATION" = false ]; then
    echo "🎉 Build complete!"
    echo "📍 Signed app: $APP_BUNDLE"
    echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

    echo "🔍 Final verification..."
    spctl -a -vvv "$APP_BUNDLE"

    echo "✨ Ready for distribution!"
else
    echo "🔍 Final verification (development build)..."
    spctl -a -vvv "$APP_BUNDLE" || echo "⚠️  Development build may not pass Gatekeeper verification"
    
    echo "✨ Ready for local testing!"
    echo "💡 For distribution, run without --skip-notarization"
fi