#!/bin/bash
set -euo pipefail

# Local build + sign (no notarization) for fast iteration
echo "🦀 Building bundled kanata (cache-aware)..."
./Scripts/build-kanata.sh

echo "🏗️  Building KeyPath (release, no WMO hang)..."
swift build --configuration release --product KeyPath -Xswiftc -no-whole-module-optimization

APP_NAME="KeyPath"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

rm -rf "$DIST_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$CONTENTS/Library/KeyPath"

cp "$BUILD_DIR/KeyPath" "$MACOS/"
cp "build/kanata-universal" "$CONTENTS/Library/KeyPath/kanata"
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"
echo "APPL????" > "$CONTENTS/PkgInfo"

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

echo "✍️  Signing (no notarization)..."
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$CONTENTS/Library/KeyPath/kanata"
codesign --force --options=runtime --entitlements "KeyPath.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Local build + sign complete: $APP_BUNDLE"
