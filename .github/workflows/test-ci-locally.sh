#!/bin/bash

# test-ci-locally.sh
# Script to test CI workflow locally before pushing

set -e

echo "🧪 Testing CI workflow locally..."

# Set CI environment variables
export CI_ENVIRONMENT=true
export KEYPATH_TESTING=false

# Test 1: Check if kanata is available
echo "📦 Checking kanata availability..."
if command -v kanata &> /dev/null; then
    echo "✅ Kanata found: $(which kanata)"
    kanata --version
else
    echo "⚠️ Kanata not found, installing..."
    brew install kanata
fi

# Test 2: Run unit tests
echo "🧪 Running unit tests..."
if swift test --filter ".*Tests" 2>&1 | tee local_test_output.log; then
    echo "✅ Unit tests completed"
else
    echo "❌ Unit tests failed"
    cat local_test_output.log
    exit 1
fi

# Test 3: Build release
echo "🔨 Testing release build..."
if swift build -c release; then
    echo "✅ Release build successful"
else
    echo "❌ Release build failed"
    exit 1
fi

# Test 4: Verify artifacts
echo "🔍 Verifying build artifacts..."
if [ -f ".build/release/KeyPath" ]; then
    echo "✅ KeyPath binary created successfully"
    ls -la .build/release/KeyPath
else
    echo "❌ KeyPath binary not found"
    exit 1
fi

echo "🎉 Local CI test completed successfully!"
echo "💡 Ready to push to GitHub - CI should work correctly"

# Cleanup
rm -f local_test_output.log