#!/bin/bash

# Build using Xcode instead of Swift Package Manager
# This avoids Swift 6.2 SPM performance issues

set -e

echo "🎯 KeyPath Xcode Build"
echo "====================="

# Check if xcodeproj exists, if not generate it
if [ ! -d "KeyPath.xcodeproj" ]; then
    echo "Generating Xcode project..."
    swift package generate-xcodeproj
fi

# Build using xcodebuild
echo "Building with Xcode..."

xcodebuild \
    -project KeyPath.xcodeproj \
    -scheme KeyPath \
    -configuration Release \
    -derivedDataPath DerivedData \
    clean build \
    SWIFT_COMPILATION_MODE=wholemodule \
    SWIFT_OPTIMIZATION_LEVEL=-O \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# Find the built app
BUILT_APP=$(find DerivedData -name "KeyPath.app" -type d | head -1)

if [ -n "$BUILT_APP" ]; then
    echo "✅ Build successful!"
    echo "Found app at: $BUILT_APP"
    
    # Copy to build directory
    mkdir -p build
    rm -rf build/KeyPath.app
    cp -R "$BUILT_APP" build/
    
    echo "✅ App copied to: build/KeyPath.app"
    echo ""
    echo "To install: sudo cp -r build/KeyPath.app /Applications/"
else
    echo "❌ Could not find built app"
    exit 1
fi