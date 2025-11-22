#!/bin/bash
# Quick script to prepare and test SMAppService POC

set -e

echo "🧪 SMAppService POC Test Setup"
echo "================================"
echo ""

# Step 1: Ensure POC executable is built and in bundle
echo "1️⃣ Building POC executable..."
swift build --product smappservice-poc > /dev/null 2>&1
POC_PATH=$(swift build --product smappservice-poc --show-bin-path)/smappservice-poc
mkdir -p dist/KeyPath.app/Contents/MacOS
cp "$POC_PATH" dist/KeyPath.app/Contents/MacOS/
echo "   ✅ POC executable ready"

# Step 2: Ensure helper plist is in bundle
echo "2️⃣ Ensuring helper plist is in bundle..."
mkdir -p dist/KeyPath.app/Contents/Library/LaunchDaemons
cp Sources/KeyPathHelper/com.keypath.helper.plist dist/KeyPath.app/Contents/Library/LaunchDaemons/ 2>/dev/null || true
echo "   ✅ Helper plist ready"

# Step 3: Check if app is signed
echo "3️⃣ Checking app bundle signature..."
if codesign -dv dist/KeyPath.app 2>&1 | grep -q "valid on disk"; then
    echo "   ✅ App bundle is signed"
    SIGNED=true
else
    echo "   ⚠️  App bundle is NOT signed"
    echo "   💡 SMAppService requires signed app bundle"
    echo "   💡 Run: ./Scripts/build-and-sign.sh (or build-and-sign-dev.sh)"
    SIGNED=false
fi

echo ""
echo "📋 Ready to test!"
echo ""
if [ "$SIGNED" = true ]; then
    echo "🚀 Running SMAppService lifecycle test..."
    echo ""
    dist/KeyPath.app/Contents/MacOS/smappservice-poc com.keypath.helper.plist lifecycle --verbose
else
    echo "⚠️  Cannot test registration without signed app bundle"
    echo "   But we can test status checking:"
    echo ""
    dist/KeyPath.app/Contents/MacOS/smappservice-poc com.keypath.helper.plist status --verbose
fi

