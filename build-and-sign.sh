#!/bin/bash

# KeyPath Build, Sign, and Notarize Script
# Run this to create a production-ready, signed, and notarized app

set -e  # Exit on any error

echo "🏗️  Building KeyPath..."
swift build --configuration release

echo "📦 Creating app bundle..."
APP_NAME="KeyPath"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
LIBRARY="${CONTENTS}/Library"
LAUNCHSERVICES="${LIBRARY}/LaunchServices"
LAUNCHDAEMONS="${LIBRARY}/LaunchDaemons"

# Clean and create directories
rm -rf "$DIST_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$LAUNCHSERVICES"
mkdir -p "$LAUNCHDAEMONS"

# Copy main executable
cp "$BUILD_DIR/KeyPath" "$MACOS/"

# Copy helper to proper location for SMAppService (MacOS directory)
cp "$BUILD_DIR/KeyPathHelper" "$MACOS/"

# Also copy to LaunchServices for backward compatibility
cp "$BUILD_DIR/KeyPathHelper" "$LAUNCHSERVICES/"

# Copy main app Info.plist
cp "Sources/KeyPath/Info.plist" "$CONTENTS/"

# Copy helper configuration files to Resources
cp "Sources/KeyPathHelper/Info.plist" "$RESOURCES/KeyPathHelper-Info.plist"
cp "Sources/KeyPathHelper/launchd.plist" "$RESOURCES/KeyPathHelper-Launchd.plist"

# Create SMAppService daemon plist in LaunchDaemons directory
cat > "$LAUNCHDAEMONS/com.keypath.KeyPath.helper.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.keypath.KeyPath.helper</string>
	<key>Program</key>
	<string>Contents/MacOS/KeyPathHelper</string>
	<key>MachServices</key>
	<dict>
		<key>com.keypath.KeyPath.helper</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<false/>
</dict>
</plist>
EOF

# Create PkgInfo file (required for app bundles)
echo "APPL????" > "$CONTENTS/PkgInfo"

echo "✍️  Signing executables..."
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Sign helper executables
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$MACOS/KeyPathHelper"
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$LAUNCHSERVICES/KeyPathHelper"

# Sign main app
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Verifying signatures..."
codesign -dvvv "$MACOS/KeyPathHelper"
codesign -dvvv "$LAUNCHSERVICES/KeyPathHelper"
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