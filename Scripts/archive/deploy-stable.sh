#\!/bin/bash
# Deploy stable build to ~/Applications to preserve permissions

echo "🏗️  Building stable signed version..."
./Scripts/build-and-sign.sh

echo "📦 Installing to /Applications..."
rm -rf /Applications/KeyPath.app
cp -r dist/KeyPath.app /Applications/

echo "✅ Installed to /Applications/KeyPath.app"
echo "Developer ID signing preserves TCC permissions across builds"
