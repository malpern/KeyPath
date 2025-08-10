#!/bin/bash
set -e

# Configuration
APP_NAME="KeyPath"
BUNDLE_IDENTIFIER="com.keypath.KeyPath"
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

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

# Sign the app bundle
echo "Signing app bundle..."
codesign --force --deep --sign "${SIGNING_IDENTITY}" /Applications/${APP_NAME}.app

# Verify signature
echo "Verifying signature..."
codesign -dv /Applications/${APP_NAME}.app

echo "Signed and installed ${APP_NAME} to /Applications/${APP_NAME}.app"