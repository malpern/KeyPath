#!/bin/bash
#
# Build Script: build-kanata.sh (TCC-Safe Caching Version)
# Purpose: Compile kanata from source with proper macOS signing and TCC preservation
# Output: build/kanata-universal (signed, universal binary)
# 
# TCC-Safe Caching Strategy:
# - Only rebuild kanata when source code actually changes
# - Preserve existing signed binary to maintain TCC identity
# - Use git hash + file timestamps to detect changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KANATA_SOURCE="$PROJECT_ROOT/External/kanata"
BUILD_DIR="$PROJECT_ROOT/build"
CACHE_INFO="$BUILD_DIR/kanata-cache.info"

# Signing identity from environment or use Developer ID
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Micah Alpern (X2RKZ5TG99)}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"

echo "🦀 Building Kanata from source (with TCC-safe caching)..."

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

# TCC-Safe Caching Logic
function calculate_source_hash() {
    # Generate hash based on kanata source files (excluding build artifacts)
    cd "$KANATA_SOURCE"
    find . \( -name "*.rs" -o -name "*.toml" -o -name "*.lock" \) \
        -not -path "./target/*" \
        -exec shasum -a 256 {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

function check_cache_validity() {
    # Check if we have a valid cached binary
    local current_hash
    local cached_hash
    local cache_valid=false
    
    if [[ -f "$BUILD_DIR/kanata-universal" && -f "$CACHE_INFO" ]]; then
        current_hash=$(calculate_source_hash)
        cached_hash=$(cat "$CACHE_INFO" 2>/dev/null || echo "")
        
        if [[ "$current_hash" == "$cached_hash" ]]; then
            # Verify the cached binary is still properly signed (unless skipping codesign)
            if [[ "$SKIP_CODESIGN" == "1" ]]; then
                cache_valid=true
                echo "🎯 TCC-Safe Cache HIT: Kanata source unchanged (signature check skipped)" >&2
                echo "📋 Source hash: $current_hash" >&2
            elif codesign --verify --deep --strict "$BUILD_DIR/kanata-universal" >/dev/null 2>&1; then
                cache_valid=true
                echo "🎯 TCC-Safe Cache HIT: Kanata source unchanged, using existing binary" >&2
                echo "📋 Source hash: $current_hash" >&2
                echo "🔐 Binary signature: VALID" >&2
            else
                echo "⚠️  TCC-Safe Cache: Binary signature invalid, will rebuild" >&2
            fi
        else
            echo "🔄 TCC-Safe Cache MISS: Kanata source changed, rebuilding required" >&2
            echo "📋 Previous hash: $cached_hash" >&2
            echo "📋 Current hash:  $current_hash" >&2
        fi
    else
        echo "🆕 TCC-Safe Cache: No cached binary found, building from scratch" >&2
    fi
    
    echo "$cache_valid"
}

# Check if we can use cached binary
CACHE_VALID=$(check_cache_validity)

if [[ "$CACHE_VALID" == "true" ]]; then
    echo "✅ Using cached kanata binary (TCC identity preserved)"
    VERSION=$("$BUILD_DIR/kanata-universal" --version)
    echo "✅ Cached kanata ready: $VERSION"
    echo "📊 Size: $(du -h "$BUILD_DIR/kanata-universal" | cut -f1)"
    exit 0
fi

echo "🔨 Proceeding with kanata compilation..."

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
    --features cmd,tcp_server \
    --target aarch64-apple-darwin

# Return to project root
cd "$PROJECT_ROOT"

# Copy ARM64 binary (x86_64 cross-compilation is disabled)
echo "📋 Copying ARM64 binary..."
cp "$KANATA_SOURCE/target/aarch64-apple-darwin/release/kanata" "$BUILD_DIR/kanata-universal"

# Verify the binary
echo "✅ Verifying binary..."
file "$BUILD_DIR/kanata-universal"

# Sign the binary
if [[ "$SKIP_CODESIGN" == "1" ]]; then
    echo "⏭️  Skipping kanata codesign (SKIP_CODESIGN=1)"
else
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
fi

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

# Update cache info for TCC preservation
echo "💾 Updating TCC-safe cache..."
NEW_HASH=$(calculate_source_hash)
echo "$NEW_HASH" > "$CACHE_INFO"
echo "📋 Cache updated with hash: $NEW_HASH"
echo "🔐 Future builds will preserve this TCC identity until kanata source changes"
