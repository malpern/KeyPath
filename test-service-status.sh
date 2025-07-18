#!/bin/bash

# Simple test to verify service status checking works

echo "Testing Kanata service status checking..."

LAUNCH_DAEMON_LABEL="com.keypath.kanata"

# Test 1: Check if service is loaded
echo "1. Checking if service is loaded..."
if launchctl print "system/$LAUNCH_DAEMON_LABEL" >/dev/null 2>&1; then
    echo "   ✅ Service is loaded"
    
    # Get detailed status
    echo "2. Getting detailed service status..."
    status_output=$(launchctl print "system/$LAUNCH_DAEMON_LABEL" 2>/dev/null)
    
    if echo "$status_output" | grep -q "state = running"; then
        echo "   ✅ Service is running"
    else
        echo "   ⚠️  Service is loaded but not running"
    fi
    
    # Show the status
    echo "3. Service details:"
    echo "$status_output" | grep -E "(state|pid|last exit code)"
    
else
    echo "   ✅ Service is not loaded (expected before installation)"
fi

echo
echo "Testing service management commands (dry run)..."

# Test command construction
echo "4. Start command: launchctl kickstart -k system/$LAUNCH_DAEMON_LABEL"
echo "5. Stop command: launchctl kill TERM system/$LAUNCH_DAEMON_LABEL"
echo "6. Status command: launchctl print system/$LAUNCH_DAEMON_LABEL"

echo
echo "Ready for actual installation!"