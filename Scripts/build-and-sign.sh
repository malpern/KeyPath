#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -e  # Exit on any error

echo "🦀 Building bundled kanata..."
# Build kanata from source (required for proper signing)
./Scripts/build-kanata.sh

echo "🔐 Building privileged helper..."
# Build and sign the helper tool
./Scripts/build-helper.sh

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
ditto "$BUILD_DIR/KeyPath" "$MACOS/KeyPath"

# Copy bundled kanata binary
ditto "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"

# Embed privileged helper for SMJobBless
echo "📦 Embedding privileged helper (SMAppService layout)..."
HELPER_TOOLS="$CONTENTS/Library/HelperTools"
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"
mkdir -p "$HELPER_TOOLS" "$LAUNCH_DAEMONS"

# Copy helper binary into bundle-local HelperTools
ditto "$BUILD_DIR/KeyPathHelper" "$HELPER_TOOLS/KeyPathHelper"

# Copy daemon plist into bundle-local LaunchDaemons with final name
ditto "Sources/KeyPathHelper/com.keypath.helper.plist" "$LAUNCH_DAEMONS/com.keypath.helper.plist"

# Copy Kanata daemon plist for SMAppService
ditto "Sources/KeyPath/com.keypath.kanata.plist" "$LAUNCH_DAEMONS/com.keypath.kanata.plist"

echo "✅ Helper embedded: $HELPER_TOOLS/KeyPathHelper"
echo "✅ Helper plist embedded: $LAUNCH_DAEMONS/com.keypath.helper.plist"
echo "✅ Kanata daemon plist embedded: $LAUNCH_DAEMONS/com.keypath.kanata.plist"

# Copy main app Info.plist
ditto "Sources/KeyPath/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon
if [ -f "Sources/KeyPath/Resources/AppIcon.icns" ]; then
    ditto "Sources/KeyPath/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
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

echo "✍️  Signing executables..."
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"

# Sign from innermost to outermost (helper -> kanata -> main app)

# Sign privileged helper (bundle-local binary)
HELPER_ENTITLEMENTS="Sources/KeyPathHelper/KeyPathHelper.entitlements"
codesign --force --options=runtime \
    --identifier "com.keypath.helper" \
    --entitlements "$HELPER_ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$HELPER_TOOLS/KeyPathHelper"

# Sign bundled kanata binary (already signed in build-kanata.sh, but ensure consistency)
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata"

# Sign main app WITH entitlements
ENTITLEMENTS_FILE="KeyPath.entitlements"
if [ -f "$ENTITLEMENTS_FILE" ]; then
    echo "Applying entitlements from $ENTITLEMENTS_FILE..."
    codesign --force --options=runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    echo "⚠️ WARNING: No entitlements file found - admin operations may fail"
    codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

echo "✅ Verifying signatures..."
codesign -dvvv "$APP_BUNDLE"

echo "📦 Creating distribution archive..."
cd "$DIST_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
cd ..

echo "📋 Submitting for notarization..."
NOTARY_PROFILE="${NOTARY_PROFILE:-KeyPath-Profile}"
xcrun notarytool submit "${DIST_DIR}/${APP_NAME}.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "🔖 Stapling notarization..."
xcrun stapler staple "$APP_BUNDLE"

echo "🎉 Build complete!"
echo "📍 Signed app: $APP_BUNDLE"
echo "📦 Distribution zip: ${DIST_DIR}/${APP_NAME}.zip"

echo "🔍 Final verification..."
spctl -a -vvv "$APP_BUNDLE"

echo "✨ Ready for distribution!"

echo "📂 Deploying to ~/Applications..."
USER_APPS_DIR="$HOME/Applications"
APP_DEST="$USER_APPS_DIR/${APP_NAME}.app"
mkdir -p "$USER_APPS_DIR"
rm -rf "$APP_DEST"
if ditto "$APP_BUNDLE" "$APP_DEST"; then
    echo "✅ Deployed latest $APP_NAME to $APP_DEST"
else
    echo "⚠️ WARNING: Failed to copy $APP_NAME to $APP_DEST" >&2
fi

echo "🚪 Restarting app..."
osascript -e 'tell application "KeyPath" to quit' || true
sleep 1
open "$APP_DEST"
