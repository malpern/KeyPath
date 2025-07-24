#!/bin/bash

# Fix SMJobBless Implementation
# This script corrects the helper bundle structure and signing

set -e

echo "🔧 Fixing SMJobBless implementation..."

BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/KeyPath.app"
CONTENTS="${APP_BUNDLE}/Contents"
HELPERS_DIR="${CONTENTS}/Library/LaunchServices"
HELPER_BUNDLE="${HELPERS_DIR}/com.keypath.helper"
HELPER_CONTENTS="${HELPER_BUNDLE}/Contents"
HELPER_MACOS="${HELPER_CONTENTS}/MacOS"

# Create proper helper bundle structure
echo "📦 Creating proper helper bundle..."
rm -rf "$HELPER_BUNDLE"
mkdir -p "$HELPER_MACOS"

# Copy helper executable to proper location
cp "$BUILD_DIR/KeyPathHelper" "$HELPER_MACOS/"

# Create helper's Info.plist with correct structure
cat > "$HELPER_CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>KeyPathHelper</string>
	<key>CFBundleIdentifier</key>
	<string>com.keypath.helper</string>
	<key>CFBundleName</key>
	<string>KeyPath Helper</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>SMAuthorizedClients</key>
	<array>
		<string>identifier "com.keypath.KeyPath" and anchor apple generic and certificate leaf[subject.CN] = "Developer ID Application: Micah Alpern (X2RKZ5TG99)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */</string>
	</array>
</dict>
</plist>
EOF

# Copy launchd.plist to Resources (not Contents root)
mkdir -p "$HELPER_CONTENTS/Resources"
cp "Sources/KeyPathHelper/launchd.plist" "$HELPER_CONTENTS/Resources/"

echo "✍️  Signing helper bundle..."
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

# Sign the helper bundle (not just executable)
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$HELPER_BUNDLE"

# Re-sign the main app to include the updated helper
codesign --force --options=runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "✅ Fixed SMJobBless structure!"
echo "🔍 Verifying..."
codesign -dvvv "$HELPER_BUNDLE"
codesign -dvvv "$APP_BUNDLE"

echo "✨ Helper bundle properly structured and signed!"