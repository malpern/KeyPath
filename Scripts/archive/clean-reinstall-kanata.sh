#!/bin/bash

# Comprehensive Kanata Clean Reinstall Script
# This script removes all existing Kanata installations and performs a clean reinstall

set -e

echo "🧹 Starting comprehensive Kanata cleanup and reinstall..."

# 1. Stop any running Kanata services
echo "📱 Stopping Kanata services..."
sudo launchctl bootout system /Library/LaunchDaemons/com.keypath.kanata.plist 2>/dev/null || echo "  No system service to stop"
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.keypath.kanata.plist 2>/dev/null || echo "  No user service to stop"

# 2. Kill any running Kanata processes
echo "🔪 Killing any running Kanata processes..."
sudo pkill -f kanata 2>/dev/null || echo "  No running processes found"

# 3. Remove LaunchDaemon/Agent files
echo "🗑️  Removing LaunchDaemon and LaunchAgent files..."
sudo rm -f /Library/LaunchDaemons/com.keypath.kanata.plist
rm -f ~/Library/LaunchAgents/com.keypath.kanata.plist

# 4. Remove Homebrew Kanata installation
echo "🍺 Removing Homebrew Kanata installation..."
brew uninstall kanata 2>/dev/null || echo "  Kanata not installed via Homebrew"

# 5. Remove custom compiled Kanata
echo "🔨 Removing custom compiled Kanata..."
sudo rm -f /usr/local/bin/kanata-cmd
sudo rm -f /usr/local/bin/kanata

# 6. Remove configuration files
echo "📝 Removing configuration files..."
sudo rm -rf /usr/local/etc/kanata
rm -f ~/safe-test.kbd ~/test-f13.kbd ~/test-caps.kbd

# 7. Remove any cached permissions (requires reboot for full effect)
echo "🔐 Note: Some cached permissions may require a system reboot to clear"

# 8. Check for Karabiner-Elements and warn if present
echo "🔍 Checking for Karabiner-Elements..."
if ls /Applications/Karabiner-Elements.app 2>/dev/null || ls ~/Applications/Karabiner-Elements.app 2>/dev/null; then
    echo "⚠️  WARNING: Karabiner-Elements is installed. This may conflict with Kanata."
    echo "   Consider uninstalling it if you experience issues."
    echo "   To uninstall: rm -rf /Applications/Karabiner-Elements.app"
fi

# 9. Verify Karabiner VirtualHID driver is present
echo "🔌 Checking for Karabiner VirtualHID driver..."
if ps aux | grep -q "Karabiner-DriverKit-VirtualHIDDevice"; then
    echo "✅ Karabiner VirtualHID driver is running"
else
    echo "❌ Karabiner VirtualHID driver not found!"
    echo "   You'll need to install it from: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases"
fi

echo ""
echo "🏁 Cleanup complete!"
echo ""
echo "🔄 Next steps for reinstall:"
echo "1. Install latest Kanata with CMD support"
echo "2. Create clean configuration"
echo "3. Set up proper permissions"
echo "4. Test with minimal configuration"
echo ""
echo "Run this script with: ./clean-reinstall-kanata.sh"