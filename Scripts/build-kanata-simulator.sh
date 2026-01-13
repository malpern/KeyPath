#!/bin/bash
#
# Build Script: build-kanata-simulator.sh
# Purpose: Compile kanata_simulated_input for dry-run simulation
# Output: build/kanata-simulator (signed binary)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KANATA_SOURCE="$PROJECT_ROOT/External/kanata"
BUILD_DIR="$PROJECT_ROOT/build"
CACHE_INFO="$BUILD_DIR/kanata-simulator-cache.info"

# Signing identity from environment or use Developer ID
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"

echo "🔬 Building Kanata Simulator from source..."

# Check prerequisites
if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Error: Rust toolchain (cargo) not found." >&2
    exit 1
fi

if [ ! -d "$KANATA_SOURCE" ]; then
    echo "❌ Error: Kanata source not found at $KANATA_SOURCE" >&2
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

echo "📁 Kanata source: $KANATA_SOURCE"
echo "📁 Build directory: $BUILD_DIR"

# Cache Logic (similar to kanata build)
function calculate_source_hash() {
    cd "$KANATA_SOURCE"
    find . \( -name "*.rs" -o -name "*.toml" -o -name "*.lock" \) \
        -not -path "./target/*" \
        -exec shasum -a 256 {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

function check_cache_validity() {
    local current_hash
    local cached_hash
    local cache_valid=false

    if [[ -f "$BUILD_DIR/kanata-simulator" && -f "$CACHE_INFO" ]]; then
        current_hash=$(calculate_source_hash)
        cached_hash=$(cat "$CACHE_INFO" 2>/dev/null || echo "")

        if [[ "$current_hash" == "$cached_hash" ]]; then
            if [[ "$SKIP_CODESIGN" == "1" ]]; then
                cache_valid=true
                echo "🎯 Cache HIT: Simulator source unchanged (signature check skipped)" >&2
            elif codesign --verify --deep --strict "$BUILD_DIR/kanata-simulator" >/dev/null 2>&1; then
                cache_valid=true
                echo "🎯 Cache HIT: Simulator source unchanged, using existing binary" >&2
            fi
        else
            echo "🔄 Cache MISS: Source changed, rebuilding required" >&2
        fi
    else
        echo "🆕 No cached simulator binary found, building from scratch" >&2
    fi

    echo "$cache_valid"
}

# Check if we can use cached binary
CACHE_VALID=$(check_cache_validity)

if [[ "$CACHE_VALID" == "true" ]]; then
    echo "✅ Using cached simulator binary"
    "$BUILD_DIR/kanata-simulator" --version 2>/dev/null || echo "   (version check skipped)"
    exit 0
fi

echo "🔨 Proceeding with simulator compilation..."

# Build for ARM64 (Apple Silicon)
echo "🔨 Building kanata_simulated_input for ARM64..."
cd "$KANATA_SOURCE"
MACOSX_DEPLOYMENT_TARGET=11.0 \
cargo build \
    --release \
    --package kanata-sim \
    --target aarch64-apple-darwin

# Return to project root
cd "$PROJECT_ROOT"

# Copy binary (ARM64 only for now)
echo "📋 Copying simulator binary..."
cp "$KANATA_SOURCE/target/aarch64-apple-darwin/release/kanata_simulated_input" "$BUILD_DIR/kanata-simulator"

# Verify the binary
echo "✅ Verifying binary..."
file "$BUILD_DIR/kanata-simulator"

# Sign the binary
if [[ "$SKIP_CODESIGN" == "1" ]]; then
    echo "⏭️  Skipping simulator codesign (SKIP_CODESIGN=1)"
else
    echo "🔏 Signing simulator binary..."
    if [[ "$SIGNING_IDENTITY" == *"Developer ID"* ]]; then
        codesign \
            --force \
            --options=runtime \
            --sign "$SIGNING_IDENTITY" \
            "$BUILD_DIR/kanata-simulator"

        echo "✅ Simulator signed for production with Developer ID"
    else
        if codesign \
            --force \
            --sign "$SIGNING_IDENTITY" \
            "$BUILD_DIR/kanata-simulator" 2>/dev/null; then
            echo "✅ Simulator signed for development"
        else
            echo "❌ SIGNING FAILED: No valid signing identity available"
            exit 1
        fi
    fi

    # Verify signature
    echo "🔍 Verifying code signature..."
    codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/kanata-simulator" 2>&1 || {
        echo "⚠️  Code signature verification failed (may be expected for development builds)"
    }
fi

# Test basic functionality
echo "🧪 Testing simulator binary..."
if "$BUILD_DIR/kanata-simulator" --help >/dev/null 2>&1; then
    echo "✅ Simulator build successful"
else
    echo "❌ Error: Simulator binary failed basic functionality test" >&2
    exit 1
fi

echo "🎉 Simulator build complete!"
echo "📍 Output: $BUILD_DIR/kanata-simulator"
echo "📊 Size: $(du -h "$BUILD_DIR/kanata-simulator" | cut -f1)"

# Update cache info
NEW_HASH=$(calculate_source_hash)
echo "$NEW_HASH" > "$CACHE_INFO"
echo "💾 Cache updated"
