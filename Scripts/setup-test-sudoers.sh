#!/bin/bash

# setup-test-sudoers.sh
# Sets up passwordless sudo rules for KeyPath testing

set -e

CURRENT_USER=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/keypath-testing"

echo "🔐 Setting up passwordless sudo for KeyPath testing..."
echo "👤 Current user: $CURRENT_USER"

# Create sudoers content for testing
SUDOERS_CONTENT="# KeyPath Testing - Passwordless sudo rules
# This file enables automated testing without password prompts
# WARNING: Only use this for development/testing environments

# Allow current user to run specific KeyPath test commands without password
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill -f kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill -f Karabiner*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/launchctl bootout*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/launchctl load*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/launchctl unload*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm /Library/LaunchDaemons/com.keypath.*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm /var/log/kanata.log
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/touch /var/log/kanata.log
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod * /var/log/kanata.log
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/chown * /var/log/kanata.log"

echo "📝 Creating sudoers file for testing..."

# Use osascript to write the sudoers file with admin privileges
osascript -e "do shell script \"echo '$SUDOERS_CONTENT' > $SUDOERS_FILE\" with administrator privileges with prompt \"KeyPath needs to set up passwordless sudo for automated testing.\""

# Validate the sudoers file
if osascript -e "do shell script \"visudo -c -f $SUDOERS_FILE\" with administrator privileges" >/dev/null 2>&1; then
    echo "✅ Test sudoers file created and validated successfully"
    echo "📍 Location: $SUDOERS_FILE"
    echo ""
    echo "🧪 You can now run tests without password prompts"
    echo "⚠️  Remember to remove this file when done testing:"
    echo "    sudo rm $SUDOERS_FILE"
else
    echo "❌ Sudoers validation failed"
    exit 1
fi