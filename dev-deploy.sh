#!/bin/bash
# Fast development deployment script
set -e

echo "🔨 Building KeyPath..."
swift build -c release --product KeyPath

echo "📦 Creating app bundle..."
rm -rf dist/KeyPath.app
mkdir -p dist/KeyPath.app/Contents/MacOS
mkdir -p dist/KeyPath.app/Contents/Resources

# Copy binary
cp .build/arm64-apple-macosx/release/KeyPath dist/KeyPath.app/Contents/MacOS/

# Copy icon
if [ -f Sources/KeyPath/Resources/AppIcon.icns ]; then
    cp Sources/KeyPath/Resources/AppIcon.icns dist/KeyPath.app/Contents/Resources/
fi

# Create Info.plist
cat > dist/KeyPath.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyPath</string>
    <key>CFBundleIdentifier</key>
    <string>com.keypath.KeyPath</string>
    <key>CFBundleName</key>
    <string>KeyPath</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Deploy to ~/Applications (user directory - no permissions needed)
echo "🚀 Deploying to ~/Applications..."
rm -rf ~/Applications/KeyPath.app
cp -r dist/KeyPath.app ~/Applications/

echo "✅ Done! Build time: $(date '+%H:%M:%S')"
echo "📍 Deployed to: ~/Applications/KeyPath.app"
echo ""
echo "To launch: open ~/Applications/KeyPath.app"