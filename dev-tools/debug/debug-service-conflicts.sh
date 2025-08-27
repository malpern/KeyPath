#!/bin/bash

echo "🔍 Checking for existing LaunchDaemon service conflicts..."

services=("com.keypath.kanata" "com.keypath.karabiner-vhiddaemon" "com.keypath.karabiner-vhidmanager")

echo "📝 Checking if services are already registered..."
for service in "${services[@]}"; do
    echo "Checking $service:"
    
    # Check if service is listed
    if launchctl list | grep -q "$service"; then
        echo "  ✅ Service IS REGISTERED in launchctl list"
        # Get details
        launchctl list "$service" 2>/dev/null || echo "  ⚠️  Could not get service details"
    else
        echo "  ❌ Service NOT REGISTERED in launchctl list"
    fi
    
    # Check if plist file exists in LaunchDaemons
    plist_path="/Library/LaunchDaemons/$service.plist"
    if [[ -f "$plist_path" ]]; then
        echo "  ✅ Plist file EXISTS: $plist_path"
        # Check permissions
        ls -la "$plist_path"
    else
        echo "  ❌ Plist file MISSING: $plist_path"
    fi
    
    echo ""
done

echo "🔍 Checking system domain bootstrap state..."

# Try to check what's in the system domain
echo "Listing system domain services..."
launchctl print system | grep -E "(keypath|karabiner)" || echo "No KeyPath/Karabiner services found in system domain"

echo ""
echo "🔍 Checking for bootstrap history issues..."

# Check if there are any obvious conflicts
echo "Looking for related services that might conflict..."
launchctl list | grep -E "(karabiner|keypath)" || echo "No related services found"

echo ""
echo "🔧 Debug complete!"