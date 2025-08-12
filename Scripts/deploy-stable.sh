#\!/bin/bash
# Deploy stable build to ~/Applications to preserve permissions

echo "🏗️  Building stable signed version..."
./Scripts/build-and-sign.sh

echo "📦 Installing to ~/Applications (preserves permissions)..."
mkdir -p ~/Applications
cp -r dist/KeyPath.app ~/Applications/

echo "✅ Installed to ~/Applications/KeyPath.app"
echo "This location preserves permissions across builds when using Developer ID signing"
