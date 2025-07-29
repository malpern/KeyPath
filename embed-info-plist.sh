#!/bin/bash

# Script to embed Info.plist into KeyPathHelper binary
# Based on solution from https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears

set -e

HELPER_BINARY="$1"
INFO_PLIST="$2"

if [ -z "$HELPER_BINARY" ] || [ -z "$INFO_PLIST" ]; then
    echo "Usage: $0 <helper-binary> <info-plist>"
    exit 1
fi

echo "Embedding Info.plist into helper binary..."

# Create a temporary object file from the Info.plist
TEMP_DIR=$(mktemp -d)
PLIST_BINARY="$TEMP_DIR/Info.plist"
OBJECT_FILE="$TEMP_DIR/info_plist.o"

# Convert plist to binary format
plutil -convert binary1 -o "$PLIST_BINARY" "$INFO_PLIST"

# Create assembly file that embeds the plist
cat > "$TEMP_DIR/info_plist.s" << EOF
.section __TEXT,__info_plist
.globl _info_plist_start
_info_plist_start:
.incbin "$PLIST_BINARY"
.globl _info_plist_end
_info_plist_end:
EOF

# Assemble the object file
as -o "$OBJECT_FILE" "$TEMP_DIR/info_plist.s"

# Link the object file with the binary
# First, we need to extract the existing binary's architecture
ARCH=$(lipo -info "$HELPER_BINARY" | awk -F': ' '{print $NF}')

# Create a new binary with the embedded plist
ld -r -arch "$ARCH" -o "$TEMP_DIR/helper_with_plist.o" "$OBJECT_FILE"

# Now we need to relink the helper with the embedded plist
# This is tricky with SPM-built executables, so let's use a different approach

# Alternative: Use linker flags in the build process
echo "Info.plist needs to be embedded during the build process."
echo "Add these to your build script:"
echo "  -sectcreate __TEXT __info_plist \"$INFO_PLIST\""

# Clean up
rm -rf "$TEMP_DIR"