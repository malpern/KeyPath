#!/bin/bash
# Install accessibility pre-commit hook
#
# Usage: ./Scripts/accessibility/install-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "📦 Installing accessibility pre-commit hook..."

# Create hooks directory if needed
mkdir -p "$HOOKS_DIR"

# Check for existing pre-commit hook
if [[ -f "$HOOKS_DIR/pre-commit" ]]; then
    echo ""
    echo "⚠️  Existing pre-commit hook found."
    echo ""
    echo "Add this line to your existing hook:"
    echo "  $SCRIPT_DIR/pre-commit-accessibility || exit 1"
    echo ""
    echo "Or to replace entirely:"
    echo "  cp $SCRIPT_DIR/pre-commit-accessibility $HOOKS_DIR/pre-commit"
else
    cp "$SCRIPT_DIR/pre-commit-accessibility" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "✅ Pre-commit hook installed!"
fi

echo ""
echo "Available scripts:"
echo "  ./Scripts/accessibility/lint-accessibility.sh     - Lint for common issues"
echo "  ./Scripts/accessibility/extract-identifiers.sh    - Generate identifier manifest"
echo "  swift Scripts/accessibility/fix-modifier-order.swift FILE - Check modifier order"
echo ""
