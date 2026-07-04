#!/bin/bash
# Pre-commit hook for KeyPath
# Lightweight checks only — full test suite runs on pre-push

set -e
cd "$(git rev-parse --show-toplevel)"

# Accessibility check (warning only) on staged UI files
STAGED_UI_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "^Sources/KeyPathAppKit/UI/.*\.swift$" || true)
if [ -n "$STAGED_UI_FILES" ]; then
    echo "♿ Checking accessibility identifiers in staged UI files..."
    if python3 Scripts/check-accessibility.py 2>&1 | grep -q "Found.*issue"; then
        echo ""
        echo "⚠️  WARNING: Some UI elements are missing accessibility identifiers"
        echo "💡 This won't block your commit, but please add identifiers for automation"
        echo "💡 See docs/testing/accessibility-coverage.md for examples"
        echo ""
    fi
fi
