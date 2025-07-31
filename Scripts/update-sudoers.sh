#!/bin/bash

# Update sudoers file with pkill support using osascript for password prompt

SUDOERS_FILE="/etc/sudoers.d/keypath-testing"
CURRENT_USER=$(whoami)

# New sudoers content with pkill support
SUDOERS_CONTENT="# KeyPath Testing - Passwordless sudo for specific wrapper scripts
# Generated for user: $CURRENT_USER

# Wrapper scripts for testing operations
$CURRENT_USER ALL=(ALL) NOPASSWD: /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Scripts/test-launchctl.sh
$CURRENT_USER ALL=(ALL) NOPASSWD: /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Scripts/test-process-manager.sh
$CURRENT_USER ALL=(ALL) NOPASSWD: /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Scripts/test-file-manager.sh

# Direct commands needed by wrapper scripts
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill *
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/launchctl
$CURRENT_USER ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/local/bin/kanata
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mkdir -p /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/mkdir -p /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/chown * /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/chown * /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod * /usr/local/etc/kanata*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/chmod * /var/log/keypath*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/cp * /Library/LaunchDaemons/com.keypath.*
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/rm /Library/LaunchDaemons/com.keypath.*"

echo "🔐 Updating sudoers file with pkill support..."

# Use osascript to write the sudoers file with admin privileges
osascript -e "do shell script \"echo '$SUDOERS_CONTENT' > $SUDOERS_FILE\" with administrator privileges"

# Validate the sudoers file
if osascript -e "do shell script \"visudo -c -f $SUDOERS_FILE\" with administrator privileges" >/dev/null 2>&1; then
    echo "✅ Sudoers file updated and validated successfully"
    echo "📍 Location: $SUDOERS_FILE"
else
    echo "❌ Sudoers validation failed"
    exit 1
fi

echo "🧪 Testing pkill permissions..."

# Test the new permissions
if sudo -n /usr/bin/pkill -f kanata 2>/dev/null; then
    echo "✅ pkill -f kanata works without password"
else 
    echo "❌ pkill -f kanata still requires password"
fi

if sudo -n /usr/bin/pkill -f karabiner_grabber 2>/dev/null; then
    echo "✅ pkill -f karabiner_grabber works without password"
else 
    echo "❌ pkill -f karabiner_grabber still requires password"
fi

echo "🎉 Sudoers update complete!"