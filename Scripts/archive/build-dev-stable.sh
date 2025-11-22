#!/bin/bash

# KeyPath Development Build with Stable Signing
# This maintains permissions between builds by using consistent signing

set -e

echo "🏗️  Building KeyPath for development..."
swift build --configuration release --product KeyPath

echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/release"
DEV_DIR="dev-build"
APP_BUNDLE="${DEV_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Clean and create directories
rm -rf "$DEV_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy main app Info.plist
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"

# Create PkgInfo file
echo "APPL????" > "$CONTENTS/PkgInfo"

echo "✍️  Signing with development certificate..."
# Use Apple Development certificate instead of ad-hoc signing
# This provides stable identity across builds
codesign --force --sign "Apple Development" "$APP_BUNDLE" || {
    echo "⚠️  Development certificate not found, trying Developer ID..."
    codesign --force --options=runtime --sign "Developer ID Application: Micah Alpern (X2RKZ5TG99)" "$APP_BUNDLE" || {
        echo "❌ No suitable signing certificate found"
        echo "💡 Either install Xcode with development certificates or use build-and-sign.sh"
        exit 1
    }
}

echo "✅ Verifying signature..."
codesign -dvvv "$APP_BUNDLE"

echo "🎉 Development build complete!"
echo "📍 App bundle: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "💡 This build uses stable signing to preserve permissions between builds"