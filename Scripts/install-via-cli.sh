#!/bin/bash
# Install KeyPath using the CLI
# This script builds KeyPath and runs the CLI to perform installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔨 Building KeyPath..."
cd "$PROJECT_ROOT"
swift build --target KeyPath

echo ""
echo "🚀 Running KeyPath CLI install..."
.build/arm64-apple-macosx/debug/KeyPath install

echo ""
echo "✅ Installation complete!"

