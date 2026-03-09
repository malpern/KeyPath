#!/bin/bash
#
# Build Script: build-kanata-host-bridge.sh
# Purpose: Build the Rust C-ABI bridge layer that a future bundled Swift host can link against.
# Output:
#   - build/kanata-host-bridge/libkeypath_kanata_host_bridge.a
#   - build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib
#   - build/kanata-host-bridge/include/keypath_kanata_host_bridge.h

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIDGE_ROOT="$PROJECT_ROOT/Rust/KeyPathKanataHostBridge"
BUILD_DIR="$PROJECT_ROOT/build/kanata-host-bridge"
BRIDGE_FEATURES="${KEYPATH_KANATA_HOST_BRIDGE_FEATURES:-passthru-output-spike}"

echo "🧩 Building KeyPath Kanata host bridge..."

if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Error: Rust toolchain (cargo) not found." >&2
    exit 1
fi

if [ ! -f "$BRIDGE_ROOT/Cargo.toml" ]; then
    echo "❌ Error: Bridge crate not found at $BRIDGE_ROOT" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/include"

if [ -n "$BRIDGE_FEATURES" ]; then
    cargo build \
        --manifest-path "$BRIDGE_ROOT/Cargo.toml" \
        --release \
        --features "$BRIDGE_FEATURES" \
        --target aarch64-apple-darwin
else
    cargo build \
        --manifest-path "$BRIDGE_ROOT/Cargo.toml" \
        --release \
        --target aarch64-apple-darwin
fi

cp "$BRIDGE_ROOT/target/aarch64-apple-darwin/release/libkeypath_kanata_host_bridge.a" \
   "$BUILD_DIR/libkeypath_kanata_host_bridge.a"
cp "$BRIDGE_ROOT/target/aarch64-apple-darwin/release/libkeypath_kanata_host_bridge.dylib" \
   "$BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
cp "$BRIDGE_ROOT/include/keypath_kanata_host_bridge.h" \
   "$BUILD_DIR/include/keypath_kanata_host_bridge.h"

echo "✅ Host bridge built"
if [ -n "$BRIDGE_FEATURES" ]; then
    echo "🧪 Bridge features: $BRIDGE_FEATURES"
fi
echo "📍 Static library: $BUILD_DIR/libkeypath_kanata_host_bridge.a"
echo "📍 Dynamic library: $BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
echo "📍 Header: $BUILD_DIR/include/keypath_kanata_host_bridge.h"
