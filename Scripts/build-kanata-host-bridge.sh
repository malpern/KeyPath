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
CACHE_INFO="$BUILD_DIR/host-bridge-cache.info"
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

calculate_source_hash() {
    cd "$BRIDGE_ROOT"
    find . \( -name "*.rs" -o -name "*.toml" -o -name "*.lock" \) \
        -not -path "./target/*" \
        -exec shasum -a 256 {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

CURRENT_HASH=$(calculate_source_hash)
CACHED_HASH=$(cat "$CACHE_INFO" 2>/dev/null || echo "")

if [ "$CURRENT_HASH" = "$CACHED_HASH" ] && \
   [ -f "$BUILD_DIR/libkeypath_kanata_host_bridge.dylib" ] && \
   [ -f "$BUILD_DIR/libkeypath_kanata_host_bridge.a" ]; then
    echo "🎯 Cache HIT: Host bridge source unchanged, using existing artifacts"
    echo "✅ Host bridge ready"
    exit 0
fi

echo "🔨 Cache miss, compiling host bridge..."

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

echo "$CURRENT_HASH" > "$CACHE_INFO"

echo "✅ Host bridge built"
if [ -n "$BRIDGE_FEATURES" ]; then
    echo "🧪 Bridge features: $BRIDGE_FEATURES"
fi
echo "📍 Static library: $BUILD_DIR/libkeypath_kanata_host_bridge.a"
echo "📍 Dynamic library: $BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
echo "📍 Header: $BUILD_DIR/include/keypath_kanata_host_bridge.h"
