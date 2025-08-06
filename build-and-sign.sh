#!/bin/bash
set -e

# Configuration
APP_NAME="KeyPath"
BUNDLE_IDENTIFIER="com.keypath.app"
TEAM_ID="${KEYPATH_SIGNING_TEAM_ID:-REPLACE_WITH_YOUR_TEAM_ID}"  # Replace with actual Team ID

# Build the release version
swift build -c release --product KeyPath

# Create app bundle
mkdir -p /Applications/${APP_NAME}.app/Contents/MacOS
mkdir -p /Applications/${APP_NAME}.app/Contents/Resources

# Copy built binary
cp .build/release/KeyPath /Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}

# Create Info.plist
cat > /Applications/${APP_NAME}.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyPath</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Sign the app bundle only if a valid team ID is provided
if [[ "${TEAM_ID}" != *"REPLACE_WITH_YOUR_TEAM_ID"* ]]; then
    codesign --force --deep --sign "${TEAM_ID}" /Applications/${APP_NAME}.app
    echo "Signed and installed ${APP_NAME} to /Applications/${APP_NAME}.app"
else
    echo "Skipping signing. No valid Team ID provided."
    echo "Installed unsigned ${APP_NAME} to /Applications/${APP_NAME}.app"
fi