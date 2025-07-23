#!/bin/bash

# Fix Kanata Service Script
# Ensures the correct cmd-enabled binary is used

set -e

echo "Fixing Kanata service configuration..."

# 1. Stop and unload existing service
echo "Stopping existing service..."
sudo launchctl kill TERM system/com.keypath.kanata 2>/dev/null || true
sudo launchctl unload /Library/LaunchDaemons/com.keypath.kanata.plist 2>/dev/null || true

# 2. Wait a moment
sleep 2

# 3. Load the service fresh
echo "Loading service with correct configuration..."
sudo launchctl load -w /Library/LaunchDaemons/com.keypath.kanata.plist

# 4. Start the service
echo "Starting Kanata service..."
sudo launchctl kickstart -k system/com.keypath.kanata

# 5. Check status
echo "Checking service status..."
sudo launchctl print system/com.keypath.kanata | grep -E "(state|program)"

echo "Done! Check /var/log/kanata.log for status"