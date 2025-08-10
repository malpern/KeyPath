#!/bin/bash
set -e

# Configuration
APP_NAME="KeyPath"
BUNDLE_IDENTIFIER="com.keypath.KeyPath"
VERSION="1.0.0"
SIGNING_IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"

echo "Building KeyPath release version..."

# Build the release version
swift build -c release --product KeyPath

# Create app bundle in dist
echo "Creating app bundle..."
rm -rf dist/${APP_NAME}.app
mkdir -p dist/${APP_NAME}.app/Contents/MacOS
mkdir -p dist/${APP_NAME}.app/Contents/Resources

# Copy built binary
cp .build/release/KeyPath dist/${APP_NAME}.app/Contents/MacOS/${APP_NAME}

# Copy icon if it exists
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns dist/${APP_NAME}.app/Contents/Resources/
fi

# Create Info.plist
cat > dist/${APP_NAME}.app/Contents/Info.plist << EOF
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
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Code sign the app bundle
echo "Signing app bundle..."
codesign --force --sign "${SIGNING_IDENTITY}" --deep dist/${APP_NAME}.app

# Verify signature
echo "Verifying signature..."
codesign -dv dist/${APP_NAME}.app

echo "App bundle created and signed at dist/${APP_NAME}.app"
echo "Run 'cp -r dist/${APP_NAME}.app ~/Applications/' to install"