#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/xcode.sh"
keypath_use_stable_xcode

if xcrun -sdk macosx metal -v >/dev/null 2>&1; then
    echo "✅ Metal toolchain is installed"
    exit 0
fi

echo "⬇️  Installing the Metal toolchain for Xcode $KEYPATH_STABLE_XCODE_VERSION..."
"$DEVELOPER_DIR/usr/bin/xcodebuild" -downloadComponent MetalToolchain

if ! xcrun -sdk macosx metal -v >/dev/null 2>&1; then
    echo "❌ Metal toolchain is still unavailable after installation" >&2
    exit 1
fi

echo "✅ Metal toolchain installed"
