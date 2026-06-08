#!/bin/bash

# test-ci-locally.sh
# Script to test CI workflow locally before pushing

set -e

echo "🧪 Testing CI workflow locally..."

# Set CI environment variables
export CI_ENVIRONMENT=true
export KEYPATH_TESTING=false
export SKIP_EVENT_TAP_TESTS=1
export KP_SIGN_DRY_RUN=1

# Test 1: Check if kanata is available
echo "📦 Checking kanata availability..."
if command -v kanata &> /dev/null; then
    echo "✅ Kanata found: $(which kanata)"
    kanata --version
else
    echo "⚠️ Kanata not found, installing..."
    brew install kanata
fi

# Test 2: Run isolated smoke lane
echo "🧪 Running isolated smoke lane..."
chmod +x ./Scripts/test-lane.sh
if KEYPATH_ISOLATED_SMOKE_CLEAN=1 ./Scripts/test-lane.sh smoke-isolated 2>&1 | tee local_test_output.log; then
    echo "✅ Isolated smoke lane completed"
else
    echo "❌ Isolated smoke lane failed"
    cat local_test_output.log
    exit 1
fi

# Test 3: Run full named lane
echo "🧪 Running full test lane..."
chmod +x ./Scripts/run-tests-safe.sh
if ./Scripts/test-lane.sh full 2>&1 | tee local_test_output.log; then
    echo "✅ Full test lane completed"
else
    echo "❌ Full test lane failed"
    cat local_test_output.log
    exit 1
fi

# Test 4: Build release
echo "🔨 Testing release build..."
if swift build -c release; then
    echo "✅ Release build successful"
else
    echo "❌ Release build failed"
    exit 1
fi

# Test 5: Verify artifacts
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
