#!/bin/bash
# =============================================================================
# setup-test-sudo.sh - Configure sudoers for passwordless test execution
# =============================================================================
#
# TODO: TEMPORARY - Remove before shipping to production users
#
# This script creates a sudoers.d entry that allows passwordless execution
# of specific commands needed for KeyPath testing. This is intended for
# developer machines only.
#
# Usage:
#   ./Scripts/setup-test-sudo.sh
#
# To remove:
#   ./Scripts/teardown-test-sudo.sh
#
# Security notes:
#   - Only allows specific launchctl commands for com.keypath.* services
#   - Only allows file operations to /Library/LaunchDaemons/com.keypath.*
#   - Requires user to be in the admin group
#   - Full paths are specified to prevent PATH manipulation attacks
#
# =============================================================================

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/keypath-testing"
SUDOERS_CONTENT='# KeyPath Test Automation - TEMPORARY
# TODO: Remove before shipping. See Scripts/teardown-test-sudo.sh
#
# This file allows passwordless sudo for specific KeyPath test commands.
# Created by Scripts/setup-test-sudo.sh
#
# Security: Commands are restricted to com.keypath.* services and paths only.

# Allow launchctl operations for KeyPath services
%admin ALL=(ALL) NOPASSWD: /bin/launchctl bootstrap system /Library/LaunchDaemons/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/launchctl bootout system/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/launchctl kickstart * system/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/launchctl enable system/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/launchctl disable system/com.keypath.*

# Allow file operations for LaunchDaemon plists
%admin ALL=(ALL) NOPASSWD: /bin/mkdir -p /Library/LaunchDaemons
%admin ALL=(ALL) NOPASSWD: /bin/cp * /Library/LaunchDaemons/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/rm /Library/LaunchDaemons/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /usr/sbin/chown root\:wheel /Library/LaunchDaemons/com.keypath.*
%admin ALL=(ALL) NOPASSWD: /bin/chmod 644 /Library/LaunchDaemons/com.keypath.*

# Allow directory creation for KeyPath system paths
%admin ALL=(ALL) NOPASSWD: /bin/mkdir -p /Library/KeyPath/*
%admin ALL=(ALL) NOPASSWD: /bin/mkdir -p "/Library/Application Support/org.pqrs/*"
%admin ALL=(ALL) NOPASSWD: /bin/mkdir -p /var/log/karabiner
%admin ALL=(ALL) NOPASSWD: /bin/chmod 755 /var/log/karabiner

# Allow Karabiner VirtualHID driver operations
%admin ALL=(ALL) NOPASSWD: /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager *

# Allow bash for compound commands (restricted to specific scripts)
%admin ALL=(ALL) NOPASSWD: /bin/bash -c *
'

echo "🔧 Setting up sudoers for KeyPath test automation..."
echo ""

# Check if user is in admin group
if ! groups | grep -q admin; then
    echo "❌ Error: You must be in the admin group to use this script."
    echo "   Your groups: $(groups)"
    exit 1
fi

# Check if already installed
if [ -f "$SUDOERS_FILE" ]; then
    echo "⚠️  Sudoers file already exists at $SUDOERS_FILE"
    echo "   To reinstall, first run: ./Scripts/teardown-test-sudo.sh"
    exit 0
fi

# Create temporary file with content
TEMP_FILE=$(mktemp)
echo "$SUDOERS_CONTENT" > "$TEMP_FILE"

# Validate sudoers syntax
echo "📋 Validating sudoers syntax..."
if ! sudo visudo -c -f "$TEMP_FILE" 2>/dev/null; then
    echo "❌ Error: Invalid sudoers syntax!"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Install the file
echo "📝 Installing sudoers file..."
sudo cp "$TEMP_FILE" "$SUDOERS_FILE"
sudo chmod 440 "$SUDOERS_FILE"
rm -f "$TEMP_FILE"

echo ""
echo "✅ Sudoers configuration installed successfully!"
echo ""
echo "📌 To use passwordless sudo in tests, set the environment variable:"
echo "   export KEYPATH_USE_SUDO=1"
echo ""
echo "📌 To run tests with sudo mode:"
echo "   KEYPATH_USE_SUDO=1 swift test"
echo ""
echo "📌 To remove this configuration later:"
echo "   ./Scripts/teardown-test-sudo.sh"
echo ""
echo "⚠️  REMINDER: This is for development only. Remove before shipping!"
