#!/bin/bash

# cleanup-test-sudoers.sh
# Removes the test sudoers file for security

set -e

SUDOERS_FILE="/etc/sudoers.d/keypath-testing"

echo "🧹 Cleaning up KeyPath test sudoers..."

if [ -f "$SUDOERS_FILE" ]; then
    # Use osascript to remove the sudoers file with admin privileges
    osascript -e "do shell script \"rm '$SUDOERS_FILE'\" with administrator privileges with prompt \"KeyPath needs to remove the test sudoers file for security.\""
    echo "✅ Test sudoers file removed successfully"
    echo "🔐 System security restored"
else
    echo "ℹ️  Test sudoers file doesn't exist - nothing to clean up"
fi