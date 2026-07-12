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
source "$SCRIPT_DIR/lib/submodules.sh"
BRIDGE_ROOT="$PROJECT_ROOT/Rust/KeyPathKanataHostBridge"
BUILD_DIR="$PROJECT_ROOT/build/kanata-host-bridge"
CACHE_INFO="$BUILD_DIR/host-bridge-cache.info"
BRIDGE_FEATURES="${KEYPATH_KANATA_HOST_BRIDGE_FEATURES:-passthru-output-spike}"
BRIDGE_TARGET="aarch64-apple-darwin"
BRIDGE_VERIFY_SCRIPT="$SCRIPT_DIR/verify-kanata-host-bridge.py"

echo "🧩 Building KeyPath Kanata host bridge..."

keypath_ensure_kanata_submodule "$PROJECT_ROOT"

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

calculate_build_fingerprint() {
    {
        printf 'source=%s\n' "$(calculate_source_hash)"
        printf 'features=%s\n' "$BRIDGE_FEATURES"
        printf 'target=%s\n' "$BRIDGE_TARGET"
        printf 'developer_dir=%s\n' "${DEVELOPER_DIR:-<unset>}"
        rustc --version --verbose
        cargo --version
        xcrun ld -v 2>&1 || true
    } | shasum -a 256 | cut -d' ' -f1
}

verify_bridge() {
    python3 "$BRIDGE_VERIFY_SCRIPT" "$BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
}

CURRENT_FINGERPRINT=$(calculate_build_fingerprint)
CACHED_FINGERPRINT=$(cat "$CACHE_INFO" 2>/dev/null || echo "")

if [ "$CURRENT_FINGERPRINT" = "$CACHED_FINGERPRINT" ] && \
   [ -f "$BUILD_DIR/libkeypath_kanata_host_bridge.dylib" ] && \
   [ -f "$BUILD_DIR/libkeypath_kanata_host_bridge.a" ]; then
    echo "🎯 Cache HIT: Host bridge inputs unchanged, verifying existing artifacts"
    if verify_bridge; then
        echo "✅ Host bridge ready"
        exit 0
    fi
    echo "⚠️  Cached host bridge failed its load check; rebuilding" >&2
fi

echo "🔨 Cache miss, compiling host bridge..."

# The outer cache tracks linker/toolchain identity, but Cargo has its own target
# cache and does not reliably treat a DEVELOPER_DIR/linker change as a relink
# input. Remove only this package's release outputs so dependencies stay warm
# while the final Mach-O artifact is guaranteed to use the current toolchain.
cargo clean \
    --manifest-path "$BRIDGE_ROOT/Cargo.toml" \
    --release \
    --target "$BRIDGE_TARGET" \
    --package keypath-kanata-host-bridge

if [ -n "$BRIDGE_FEATURES" ]; then
    cargo build \
        --manifest-path "$BRIDGE_ROOT/Cargo.toml" \
        --release \
        --features "$BRIDGE_FEATURES" \
        --target "$BRIDGE_TARGET"
else
    cargo build \
        --manifest-path "$BRIDGE_ROOT/Cargo.toml" \
        --release \
        --target "$BRIDGE_TARGET"
fi

cp "$BRIDGE_ROOT/target/$BRIDGE_TARGET/release/libkeypath_kanata_host_bridge.a" \
   "$BUILD_DIR/libkeypath_kanata_host_bridge.a"
cp "$BRIDGE_ROOT/target/$BRIDGE_TARGET/release/libkeypath_kanata_host_bridge.dylib" \
   "$BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
cp "$BRIDGE_ROOT/include/keypath_kanata_host_bridge.h" \
   "$BUILD_DIR/include/keypath_kanata_host_bridge.h"

echo "🧪 Verifying host bridge can be loaded by the release runtime..."
if ! verify_bridge; then
    echo "❌ Host bridge failed its load check; refusing to cache or package it" >&2
    exit 1
fi

echo "$CURRENT_FINGERPRINT" > "$CACHE_INFO"

echo "✅ Host bridge built"
if [ -n "$BRIDGE_FEATURES" ]; then
    echo "🧪 Bridge features: $BRIDGE_FEATURES"
fi
echo "📍 Static library: $BUILD_DIR/libkeypath_kanata_host_bridge.a"
echo "📍 Dynamic library: $BUILD_DIR/libkeypath_kanata_host_bridge.dylib"
echo "📍 Header: $BUILD_DIR/include/keypath_kanata_host_bridge.h"
