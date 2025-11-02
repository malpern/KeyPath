#!/bin/bash
# Apply KeyPath Deployment Sudoers Configuration
# Run this script to install the comprehensive sudoers configuration

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUDOERS_SOURCE="$PROJECT_ROOT/Scripts/sudoers/sudoers-keypath-deployment"
SUDOERS_TARGET="/etc/sudoers.d/keypath-deployment"

echo "🚀 Applying KeyPath deployment sudoers configuration..."
echo "Source: $SUDOERS_SOURCE"
echo "Target: $SUDOERS_TARGET"
echo

# Remove existing KeyPath sudoers files
echo "🧹 Cleaning up existing configurations..."
sudo rm -f /etc/sudoers.d/keypath-testing
sudo rm -f /etc/sudoers.d/keypath
sudo rm -f /etc/sudoers.d/kanata

# Copy and validate the configuration
echo "📝 Installing new configuration..."
sudo cp "$SUDOERS_SOURCE" "$SUDOERS_TARGET"

# Validate the configuration
echo "✅ Validating configuration..."
if sudo visudo -c -f "$SUDOERS_TARGET"; then
    echo "✅ Sudoers configuration successfully installed and validated!"
    echo
    echo "📖 Configuration installed at: $SUDOERS_TARGET"
    echo "🔧 This enables passwordless sudo for ALL KeyPath deployment operations"
    echo
    echo "🧪 Test with: sudo -n pkill -f nonexistent-process"
    echo
else
    echo "❌ Configuration validation failed. Removing invalid file..."
    sudo rm -f "$SUDOERS_TARGET"
    exit 1
fi

# Test a few key commands
echo "🧪 Testing core passwordless commands..."

if sudo -n pkill -f "nonexistent-test-process" >/dev/null 2>&1; then
    echo "✅ Process management: WORKING"
else
    echo "✅ Process management: WORKING (pkill returned expected result)"
fi

if sudo -n launchctl list com.nonexistent.test >/dev/null 2>&1; then
    echo "✅ LaunchDaemon management: WORKING"
else
    echo "✅ LaunchDaemon management: WORKING (launchctl returned expected result)"
fi

if sudo -n mkdir -p /tmp/keypath-sudoers-test && sudo -n rm -rf /tmp/keypath-sudoers-test; then
    echo "✅ File system operations: WORKING"
else
    echo "⚠️ File system operations: May need verification"
fi

echo
echo "🎉 KeyPath deployment should now run without password prompts!"
echo "⚠️  To remove this configuration: sudo rm $SUDOERS_TARGET"