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

# Copy app icon if present
if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
    cp "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES/"
else
    echo "⚠️ WARNING: AppIcon.icns not found at Sources/KeyPath/Resources/AppIcon.icns" >&2
fi

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

echo "📂 Deploying to Applications..."
DEST_DIR="/Applications"
APP_DEST="$DEST_DIR/${APP_NAME}.app"
# Always use sudo for predictable deployment (prevents false-positive -w checks)
echo "🛑 Stopping any running KeyPath before deploy..."
pkill -f "$APP_DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "🧹 Removing existing $APP_DEST (sudo)..."
sudo rm -rf "$APP_DEST" 2>/dev/null || true

echo "📥 Copying app to /Applications (sudo)..."
if sudo ditto "$APP_BUNDLE" "$APP_DEST"; then
  echo "✅ Deployed to $APP_DEST"
else
  echo "⚠️ WARNING: sudo copy to /Applications failed. Retrying without sudo..." >&2
  rm -rf "$APP_DEST" 2>/dev/null || true
  if ditto "$APP_BUNDLE" "$APP_DEST"; then
    echo "✅ Deployed to $APP_DEST (no sudo)"
  else
    echo "❌ ERROR: Deployment to /Applications failed" >&2
    exit 1
  fi
fi

echo "✨ Ready for development testing!"
echo "📍 App location: $APP_DEST"
echo "💡 Use ./Scripts/build-and-sign.sh for production builds with notarization"