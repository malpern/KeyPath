#!/bin/bash
#
# Build Script: build-kanata-runtime-library.sh
# Purpose: Produce a linkable static library artifact from the vendored Kanata source.
# Output: build/kanata-runtime/libkanata_state_machine.a
#
# This does NOT create a Swift-callable bridge by itself. The upstream crate exposes
# Rust symbols, not a stable C ABI. This script exists to validate the packaging/linking
# half of the long-term "bundled host owns HID capture" migration without changing the
# shipping runtime path yet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KANATA_SOURCE="$PROJECT_ROOT/External/kanata"
BUILD_DIR="$PROJECT_ROOT/build"
OUTPUT_DIR="$BUILD_DIR/kanata-runtime"
OUTPUT_LIB="$OUTPUT_DIR/libkanata_state_machine.a"
OUTPUT_INFO="$OUTPUT_DIR/README.txt"

echo "🧱 Building Kanata runtime static library artifact..."

if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Error: Rust toolchain (cargo) not found." >&2
    exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
    echo "❌ Error: rustup not found." >&2
    exit 1
fi

if [ ! -d "$KANATA_SOURCE" ]; then
    echo "❌ Error: Kanata source not found at $KANATA_SOURCE" >&2
    echo "   Run: git submodule update --init --recursive" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "📁 Kanata source: $KANATA_SOURCE"
echo "📁 Output directory: $OUTPUT_DIR"

rustup target add aarch64-apple-darwin >/dev/null 2>&1 || true

cd "$KANATA_SOURCE"
MACOSX_DEPLOYMENT_TARGET=11.0 \
cargo rustc \
    --release \
    --lib \
    --target aarch64-apple-darwin \
    -- \
    --crate-type staticlib

cd "$PROJECT_ROOT"

SOURCE_LIB="$KANATA_SOURCE/target/aarch64-apple-darwin/release/libkanata_state_machine.a"
if [ ! -f "$SOURCE_LIB" ]; then
    echo "❌ Error: Expected static library not found at $SOURCE_LIB" >&2
    exit 1
fi

cp "$SOURCE_LIB" "$OUTPUT_LIB"

cat > "$OUTPUT_INFO" <<'EOF'
This artifact is a linkable static library build of Kanata's upstream Rust library target.

Important:
- It is NOT a stable C ABI.
- Swift cannot call it directly without a Rust bridge layer that exports C-callable entry points.
- It exists to validate that KeyPath can package and link the upstream library boundary as part
  of the long-term macOS runtime-host migration.

Expected next step:
- add a small Rust bridge crate that depends on kanata_state_machine and exposes a stable C ABI
  tailored to KeyPath's bundled macOS runtime host.
EOF

echo "✅ Kanata runtime library built"
echo "📍 Static library: $OUTPUT_LIB"
echo "📍 Notes: $OUTPUT_INFO"
file "$OUTPUT_LIB" || true
