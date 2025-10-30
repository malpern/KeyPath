#!/bin/bash

# Local release build script - signs but doesn't notarize
# For testing helper functionality before distribution

set -e  # Exit on any error

echo "🦀 Building bundled kanata..."
./Scripts/build-kanata.sh

echo "🔐 Building privileged helper..."
./Scripts/build-helper.sh

echo "🏗️  Building KeyPath..."
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization

echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist-local"
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

# Embed privileged helper for SMJobBless
echo "📦 Embedding privileged helper..."
LAUNCH_SERVICES="$CONTENTS/Library/LaunchServices"
mkdir -p "$LAUNCH_SERVICES"

# Copy signed helper executable
cp "$BUILD_DIR/KeyPathHelper" "$LAUNCH_SERVICES/com.keypath.helper"

# Copy helper's Info.plist and launchd.plist for SMJobBless
cp "Sources/KeyPathHelper/Info.plist" "$LAUNCH_SERVICES/com.keypath.helper-Info.plist"
cp "Sources/KeyPathHelper/launchd.plist" "$LAUNCH_SERVICES/com.keypath.helper-Launchd.plist"

echo "✅ Helper embedded: $LAUNCH_SERVICES/com.keypath.helper"

# Copy main app Info.plist
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"

# Copy app icon
if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
    cp "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES/"
    echo "✅ Copied app icon"
else
    echo "⚠️ WARNING: AppIcon.icns not found"
fi

# Create PkgInfo file (required for app bundles)
echo "APPL????" > "$CONTENTS/PkgInfo"

# Create BuildInfo.plist for About dialog
echo "🧾 Writing BuildInfo.plist..."
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CFVER=$(defaults read "$CONTENTS/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
CFBUILD=$(defaults read "$CONTENTS/Info" CFBundleVersion 2>/dev/null || echo "0")
cat > "$RESOURCES/BuildInfo.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>${CFVER}</string>
  <key>CFBundleVersion</key>
  <string>${CFBUILD}</string>
  <key>GitCommit</key>
  <string>${GIT_HASH}</string>
  <key>BuildDate</key>
  <string>${BUILD_DATE}</string>
</dict>
</plist>
EOF

echo "✍️  Signing executables (ad-hoc for local testing)..."

# Sign with ad-hoc signature (no Developer ID needed)
# This allows local testing without notarization

# Sign privileged helper
codesign --force --sign - \
    --identifier "com.keypath.helper" \
    --entitlements "Sources/KeyPathHelper/KeyPathHelper.entitlements" \
    "$LAUNCH_SERVICES/com.keypath.helper"

# Sign bundled kanata binary
codesign --force --sign - "$CONTENTS/Library/KeyPath/kanata"

# Sign main app WITH entitlements
codesign --force --deep --sign - \
    --entitlements "KeyPath.entitlements" \
    "$APP_BUNDLE"

echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"

echo "🎉 Local build complete!"
echo "📍 App bundle: $APP_BUNDLE"

echo "📂 Deploying to /Applications..."
APP_DEST="/Applications/${APP_NAME}.app"
if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
fi
if cp -R "$APP_BUNDLE" "/Applications/"; then
    echo "✅ Deployed latest $APP_NAME to $APP_DEST"
else
    echo "⚠️ WARNING: Failed to copy $APP_NAME to /Applications. You may need to rerun this step with sudo." >&2
fi

echo "✨ Ready for local testing!"
echo "⚠️ NOTE: This build uses ad-hoc signing and cannot be distributed"
