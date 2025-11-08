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
mkdir -p "$CONTENTS/Library/LaunchDaemons"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy bundled kanata binary
cp "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"

# Copy Kanata daemon plist for SMAppService
cp "Sources/KeyPath/com.keypath.kanata.plist" "$CONTENTS/Library/LaunchDaemons/com.keypath.kanata.plist"
echo "✅ Kanata daemon plist embedded: $CONTENTS/Library/LaunchDaemons/com.keypath.kanata.plist"

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

echo "📂 Deploying to ~/Applications for TCC testing..."
USER_APPS_DIR="$HOME/Applications"
APP_DEST="$USER_APPS_DIR/${APP_NAME}.app"
mkdir -p "$USER_APPS_DIR"
rm -rf "$APP_DEST"
if ditto "$APP_BUNDLE" "$APP_DEST"; then
    echo "✅ Deployed latest $APP_NAME to $APP_DEST"
    echo "   (TCC permissions require app to be in Applications folder)"
else
    echo "⚠️ WARNING: Failed to copy $APP_NAME to $APP_DEST" >&2
fi

echo "✨ Ready for development testing!"
echo "📍 App location: $APP_DEST"
echo "💡 Use ./Scripts/build-and-sign.sh for production builds with notarization"