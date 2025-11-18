#!/bin/bash
# Fast local development build (no notarization)
# Use this for local testing - it's 10x faster than full notarization

set -euo pipefail

cd "$(dirname "$0")/.."

echo "🚀 Fast local build (skipping notarization)..."

# Build
swift build -c release

# Use the build.sh script but stop before notarization
./Scripts/build.sh 2>&1 | sed '/📋 Submitting for notarization/q' || true

# Kill any notarization that might have started
pkill -9 notarytool 2>/dev/null || true

# Deploy
echo "📂 Deploying to /Applications..."
cp -r dist/KeyPath.app /Applications/
killall KeyPath 2>/dev/null || true
open /Applications/KeyPath.app

echo "✅ Deployed (local development build)"
echo "⚡ For production release, use: ./build.sh"
