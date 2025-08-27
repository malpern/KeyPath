#!/bin/bash

# REAL FIX for KeyPath build hanging issue
# Root cause: Complex codebase overwhelming Swift compiler type inference

set -e

echo "🔧 KeyPath Build - Real Fix"
echo "=========================="

# Temporarily simplify Package.swift to reduce compiler load
echo "1. Temporarily removing compiler warnings suppression..."
cp Package.swift Package.swift.backup

sed 's/\.unsafeFlags(\["-suppress-warnings"\])/\/\/ .unsafeFlags(["-suppress-warnings"])/' Package.swift > Package.swift.tmp
mv Package.swift.tmp Package.swift

# Clear all caches
echo "2. Clearing all build caches..."
rm -rf .build
rm -rf ~/Library/Developer/Xcode/DerivedData/*KeyPath* 2>/dev/null || true

# Build with minimal optimization to reduce type inference load
echo "3. Building with reduced optimization..."
swift build -c release \
    -Xswiftc -O \
    -Xswiftc -disable-batch-mode \
    -Xswiftc -j1 \
    --product KeyPath

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Restore original Package.swift
    mv Package.swift.backup Package.swift
    
    # Package the app
    ./Scripts/build.sh
    
    echo "✅ App packaged successfully"
else
    echo "❌ Build failed"
    mv Package.swift.backup Package.swift
    exit 1
fi