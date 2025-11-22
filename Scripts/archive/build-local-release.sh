#!/bin/bash

# Local release build script — signs (Developer ID) but doesn't notarize
# For testing SMAppService helper functionality before distribution

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
mkdir -p "$CONTENTS/Library/HelperTools"
mkdir -p "$CONTENTS/Library/LaunchDaemons"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy bundled kanata binary
cp "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"

echo "📦 Embedding privileged helper (SMAppService layout)..."
# Copy helper binary into bundle-local HelperTools
cp "$BUILD_DIR/KeyPathHelper" "$CONTENTS/Library/HelperTools/KeyPathHelper"
# Copy daemon plist into bundle-local LaunchDaemons with final name
cp "Sources/KeyPathHelper/com.keypath.helper.plist" "$CONTENTS/Library/LaunchDaemons/com.keypath.helper.plist"
echo "✅ Helper embedded: $CONTENTS/Library/HelperTools/KeyPathHelper"
echo "✅ Daemon plist embedded: $CONTENTS/Library/LaunchDaemons/com.keypath.helper.plist"

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

echo "✍️  Signing executables (Developer ID for SMAppService testing)..."
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Sign privileged helper (bundle-local binary)
codesign --force --options=runtime \
    --identifier "com.keypath.helper" \
    --entitlements "Sources/KeyPathHelper/KeyPathHelper.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    "$CONTENTS/Library/HelperTools/KeyPathHelper"

# Sign bundled kanata binary
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata"

# Sign main app WITH entitlements
codesign --force --options=runtime --entitlements "KeyPath.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

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

echo "✨ Ready for local testing (SMAppService) — no notarization performed"
