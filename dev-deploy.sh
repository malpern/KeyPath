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

# Graceful shutdown of a running instance (best effort)
echo "🛑 Stopping running KeyPath (if any)..."
osascript -e 'tell application "KeyPath" to quit' >/dev/null 2>&1 || true
pkill -f "/KeyPath.app/Contents/MacOS/KeyPath" >/dev/null 2>&1 || true

# Remove any user-local copy that could confuse TCC grants
if [ -d "$HOME/Applications/KeyPath.app" ]; then
  echo "🧹 Removing user-local copy: $HOME/Applications/KeyPath.app"
  rm -rf "$HOME/Applications/KeyPath.app"
fi

# Deploy to /Applications (system Applications)
echo "🚀 Deploying to /Applications..."
if rm -rf /Applications/KeyPath.app 2>/dev/null && cp -R dist/KeyPath.app /Applications/; then
  echo "✅ Deployed to /Applications/KeyPath.app"
else
  echo "⚠️  Permission denied copying to /Applications — retrying with sudo"
  sudo rm -rf /Applications/KeyPath.app || true
  sudo cp -R dist/KeyPath.app /Applications/
  echo "✅ Deployed (sudo) to /Applications/KeyPath.app"
fi

echo "✅ Done! Build time: $(date '+%H:%M:%S')"
echo "📍 Deployed to: /Applications/KeyPath.app"
echo ""
echo "To launch: open /Applications/KeyPath.app"
