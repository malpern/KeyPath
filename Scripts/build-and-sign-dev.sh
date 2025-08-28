#!/bin/bash

# KeyPath Development Build and Sign Script
# Builds and signs the app but skips notarization for faster development iterations
# Maintains TCC identity by preserving Team ID, Bundle ID, and code signature

set -e  # Exit on any error

echo "🦀 Building bundled kanata..."
# Build kanata from source (with TCC-safe caching)
./Scripts/build-kanata.sh

echo "🏗️  Building KeyPath..."
# Use debug build for faster compilation during development
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

# Sign bundled kanata binary (preserves TCC identity)
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata"

# Sign main app (preserves TCC identity)
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"

echo "🎉 Development build complete!"
echo "📍 Signed app: $APP_BUNDLE"
echo "⚡ Notarization skipped for faster development"
echo "🔒 TCC identity preserved (Team ID + Bundle ID + Code Signature)"

echo "🔍 Code signature verification..."
codesign --verify --verbose=2 "$APP_BUNDLE"

echo "✨ Ready for development testing!"
echo "💡 Use ./Scripts/build-and-sign.sh for production builds with notarization"