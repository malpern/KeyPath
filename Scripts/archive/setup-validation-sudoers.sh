#!/bin/bash

# setup-validation-sudoers.sh
# Sets up passwordless sudo rules for KeyPath config validation

set -e

CURRENT_USER=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/keypath-validation"

echo "🔐 Setting up passwordless sudo for KeyPath validation..."
echo "👤 Current user: $CURRENT_USER"

# Create sudoers content for validation only
SUDOERS_CONTENT="# KeyPath Validation - Passwordless sudo rules
# This file enables config validation without password prompts
# Only allows kanata --check command for validation

# Allow current user to run kanata --check without password
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/kanata --cfg * --check
$CURRENT_USER ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata --cfg * --check"

echo "📝 Creating sudoers file for validation..."

# Use osascript to write the sudoers file with admin privileges
osascript -e "do shell script \"echo '$SUDOERS_CONTENT' > $SUDOERS_FILE\" with administrator privileges with prompt \"KeyPath needs to set up passwordless sudo for config validation.\""

# Validate the sudoers file
if osascript -e "do shell script \"visudo -c -f $SUDOERS_FILE\" with administrator privileges" >/dev/null 2>&1; then
    echo "✅ Validation sudoers file created and validated successfully"
    echo "📍 Location: $SUDOERS_FILE"
    echo ""
    echo "✨ KeyPath can now validate configs without password prompts"
    echo "ℹ️  This only allows 'kanata --check' commands for validation"
    echo ""
    echo "🗑️  To remove this setup later:"
    echo "    sudo rm $SUDOERS_FILE"
else
    echo "❌ Sudoers validation failed"
    osascript -e "do shell script \"rm -f $SUDOERS_FILE\" with administrator privileges" 2>/dev/null || true
    exit 1
fi