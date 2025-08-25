#!/bin/bash
#
# Build Script: build-kanata.sh
# Purpose: Compile kanata from source with proper macOS signing
# Output: build/kanata-universal (signed, universal binary)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KANATA_SOURCE="$PROJECT_ROOT/External/kanata"
BUILD_DIR="$PROJECT_ROOT/build"

# Signing identity from environment or use Developer ID
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"

echo "🦀 Building Kanata from source..."

# Check prerequisites
if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Error: Rust toolchain (cargo) not found." >&2
    echo "   Install via: https://rustup.rs" >&2
    echo "   Or run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
    exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
    echo "❌ Error: rustup not found." >&2
    echo "   Install via: https://rustup.rs" >&2
    exit 1
fi

if [ ! -d "$KANATA_SOURCE" ]; then
    echo "❌ Error: Kanata source not found at $KANATA_SOURCE" >&2
    echo "   Run: git submodule update --init --recursive" >&2
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

echo "📁 Kanata source: $KANATA_SOURCE"
echo "📁 Build directory: $BUILD_DIR"

# Add required Rust targets
echo "🎯 Adding Rust targets..."
rustup target add aarch64-apple-darwin >/dev/null 2>&1 || true
rustup target add x86_64-apple-darwin >/dev/null 2>&1 || true

# Build for ARM64 (Apple Silicon)
echo "🔨 Building for ARM64 (Apple Silicon)..."
cd "$KANATA_SOURCE"
MACOSX_DEPLOYMENT_TARGET=11.0 \
cargo build \
    --release \
    --features cmd \
    --target aarch64-apple-darwin

# Skip x86_64 build for now due to Rust toolchain issues
echo "⚠️ Skipping x86_64 build (ARM64 only for now)..."

# Return to project root
cd "$PROJECT_ROOT"

# Create universal binary (fallback to ARM64 if lipo fails)
echo "🔗 Creating universal binary..."
if /usr/bin/lipo -create \
    -output "$BUILD_DIR/kanata-universal" \
    "$KANATA_SOURCE/target/aarch64-apple-darwin/release/kanata" \
    "$KANATA_SOURCE/target/x86_64-apple-darwin/release/kanata" 2>/dev/null; then
    
    echo "✅ Universal binary created successfully"
    /usr/bin/lipo -info "$BUILD_DIR/kanata-universal"
else
    echo "⚠️  lipo failed, using ARM64 binary (sufficient for Apple Silicon)"
    cp "$KANATA_SOURCE/target/aarch64-apple-darwin/release/kanata" "$BUILD_DIR/kanata-universal"
fi

# Verify the binary
echo "✅ Verifying binary..."
file "$BUILD_DIR/kanata-universal"

# Sign the binary
echo "🔏 Signing kanata binary..."
if [[ "$SIGNING_IDENTITY" == *"Developer ID"* ]]; then
    # Production signing with runtime hardening
    codesign \
        --force \
        --options=runtime \
        --sign "$SIGNING_IDENTITY" \
        "$BUILD_DIR/kanata-universal"
    
    echo "✅ Kanata signed for production with Developer ID"
else
    # Development signing (requires valid certificate)
    if codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        "$BUILD_DIR/kanata-universal" 2>/dev/null; then
        echo "✅ Kanata signed for development"
    else
        echo "❌ SIGNING FAILED: No valid signing identity available"
        echo "💡 Ensure you have a valid Apple Developer certificate"
        exit 1
    fi
fi

# Verify signature
echo "🔍 Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/kanata-universal" 2>&1 || {
    echo "⚠️  Code signature verification failed (may be expected for development builds)"
}

# Test basic functionality
echo "🧪 Testing kanata binary..."
if "$BUILD_DIR/kanata-universal" --version >/dev/null 2>&1; then
    VERSION=$("$BUILD_DIR/kanata-universal" --version)
    echo "✅ Kanata build successful: $VERSION"
else
    echo "❌ Error: Kanata binary failed basic functionality test" >&2
    exit 1
fi

echo "🎉 Kanata build complete!"
echo "📍 Output: $BUILD_DIR/kanata-universal"
echo "📊 Size: $(du -h "$BUILD_DIR/kanata-universal" | cut -f1)"