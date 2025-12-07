#!/bin/bash
# Build documentation HTML from AsciiDoc sources
#
# Usage: ./Scripts/build-docs.sh
#
# Generates HTML versions of .adoc files in docs/ folder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/Scripts}"
DOCS_DIR="$REPO_ROOT/docs"

# Check if asciidoctor is installed
if ! command -v asciidoctor &> /dev/null; then
    echo "Error: asciidoctor is not installed."
    echo ""
    echo "Install with:"
    echo "  brew install asciidoctor"
    echo ""
    exit 1
fi

echo "Building documentation HTML files..."

# Build KEYPATH_GUIDE.adoc
if [ -f "$DOCS_DIR/KEYPATH_GUIDE.adoc" ]; then
    echo "  → KEYPATH_GUIDE.adoc → KEYPATH_GUIDE.html"
    asciidoctor \
        -b html5 \
        -a toc=left \
        -a toclevels=3 \
        -a source-highlighter=highlight.js \
        -a icons=font \
        "$DOCS_DIR/KEYPATH_GUIDE.adoc" \
        -o "$DOCS_DIR/KEYPATH_GUIDE.html"
    echo "    ✓ Generated $DOCS_DIR/KEYPATH_GUIDE.html"
else
    echo "  ⚠ Warning: $DOCS_DIR/KEYPATH_GUIDE.adoc not found"
fi

# Build kanata-push-msg-docs.adoc if it exists
if [ -f "$DOCS_DIR/kanata-push-msg-docs.adoc" ]; then
    echo "  → kanata-push-msg-docs.adoc → kanata-push-msg-docs.html"
    asciidoctor \
        -b html5 \
        -a toc=left \
        -a toclevels=2 \
        -a source-highlighter=highlight.js \
        -a icons=font \
        "$DOCS_DIR/kanata-push-msg-docs.adoc" \
        -o "$DOCS_DIR/kanata-push-msg-docs.html"
    echo "    ✓ Generated $DOCS_DIR/kanata-push-msg-docs.html"
fi

echo ""
echo "✓ Documentation build complete!"
echo ""
echo "HTML files generated in: $DOCS_DIR/"
