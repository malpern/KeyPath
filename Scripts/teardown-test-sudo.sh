#!/bin/bash
# =============================================================================
# teardown-test-sudo.sh - Remove sudoers configuration for test automation
# =============================================================================
#
# This script removes the sudoers.d entry created by setup-test-sudo.sh.
#
# Usage:
#   ./Scripts/teardown-test-sudo.sh
#
# =============================================================================

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/keypath-testing"

echo "🧹 Removing KeyPath test sudoers configuration..."
echo ""

if [ ! -f "$SUDOERS_FILE" ]; then
    echo "ℹ️  Sudoers file not found at $SUDOERS_FILE"
    echo "   Nothing to remove."
    exit 0
fi

echo "📋 Removing: $SUDOERS_FILE"
sudo rm -f "$SUDOERS_FILE"

echo ""
echo "✅ Sudoers configuration removed successfully!"
echo ""
echo "📌 Tests will now use the default osascript password dialog method."
echo "   To re-enable passwordless testing, run: ./Scripts/setup-test-sudo.sh"
