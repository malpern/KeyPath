#!/bin/bash
#
# Development build script for contributors
# No Developer ID certificate required - builds with direct sudo only
#
# Usage: ./Scripts/build-dev-local.sh

set -e  # Exit on error

echo "🔧 Building KeyPath for development (DEBUG mode)"
echo "📋 No certificate required - helper will NOT be included"
echo ""

# Build in DEBUG mode (uses direct sudo, no helper)
echo "1️⃣  Building KeyPath executable..."
swift build -c debug --product KeyPath

echo ""
echo "✅ Development build complete!"
echo ""
echo "📁 Build location: .build/debug/KeyPath"
echo "🎯 Operation mode: Direct sudo (no privileged helper)"
echo ""
echo "To run:"
echo "  .build/debug/KeyPath"
echo ""
echo "Note: This build uses direct sudo for privileged operations."
echo "      Multiple password prompts are expected (this is normal for dev builds)."
