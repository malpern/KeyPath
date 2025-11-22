#!/bin/bash

echo "Cleaning up old KeyPath services..."

# List of old service identifiers to remove
OLD_SERVICES=(
    "com.keypath.helper"
    "com.keypath.kanata"
    "com.keypath.kanata.helper"
    "com.keypath.kanata.helper.v2"
    "com.keypath.kanata.helper.v4"
    "com.keypath.kanata.xpc"
    "com.keypath.helperpoc.helper"
)

for service in "${OLD_SERVICES[@]}"; do
    echo "Attempting to remove service: $service"
    
    # Try to unload and remove from user domain first
    launchctl bootout gui/$(id -u) "$service" 2>/dev/null || true
    
    # Try to unload and remove from system domain
    sudo launchctl bootout system "$service" 2>/dev/null || true
    
    # Remove any plist files
    sudo rm -f "/Library/LaunchDaemons/${service}.plist" 2>/dev/null || true
    sudo rm -f "/System/Library/LaunchDaemons/${service}.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/${service}.plist" 2>/dev/null || true
done

echo "Cleanup complete. Checking remaining KeyPath services..."
launchctl print system | grep keypath || echo "No KeyPath services found in system domain"