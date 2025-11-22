#!/bin/bash

echo "🔍 Testing KeyPath ↔ Kanata Service Connection"
echo "=============================================="
echo ""

# 1. Check what processes exist
echo "1. Process Analysis:"
echo "-------------------"
KANATA_PROCS=$(ps aux | grep -E "[k]anata.*--cfg" | wc -l | tr -d ' ')
echo "   Kanata processes running: $KANATA_PROCS"

if [ "$KANATA_PROCS" -gt 0 ]; then
    echo "   Process details:"
    ps aux | grep -E "[k]anata.*--cfg" | while read line; do
        echo "     $line"
    done
fi

echo ""

# 2. Check launchctl service status
echo "2. LaunchDaemon Service Status:"
echo "------------------------------"
if sudo -n launchctl print system/com.keypath.kanata >/dev/null 2>&1; then
    echo "   ✅ LaunchDaemon exists: com.keypath.kanata"
    SERVICE_STATE=$(sudo -n launchctl print system/com.keypath.kanata 2>/dev/null | grep "state = " | awk '{print $3}')
    echo "   Service state: $SERVICE_STATE"
    
    SERVICE_PID=$(sudo -n launchctl print system/com.keypath.kanata 2>/dev/null | grep "pid = " | awk '{print $3}')
    echo "   Service PID: $SERVICE_PID"
else
    echo "   ❌ LaunchDaemon not found or not accessible"
fi

echo ""

# 3. Check TCP connectivity
echo "3. TCP Server Status:"
echo "--------------------"
if nc -z localhost 37000 2>/dev/null; then
    echo "   ✅ TCP server responding on port 37000"
    LAYER_NAMES=$(echo '{"RequestLayerNames": {}}' | nc -w 2 localhost 37000 2>/dev/null | grep LayerNames)
    echo "   Current layers: $LAYER_NAMES"
else
    echo "   ❌ TCP server not responding on port 37000"
fi

echo ""

# 4. Check config file location and timestamps
echo "4. Configuration File Status:"
echo "----------------------------"
CONFIG_PATH="/Users/malpern/.config/keypath/keypath.kbd"
if [ -f "$CONFIG_PATH" ]; then
    echo "   ✅ Config file exists: $CONFIG_PATH"
    echo "   File size: $(wc -c < "$CONFIG_PATH") bytes"
    echo "   Last modified: $(stat -f "%Sm" "$CONFIG_PATH")"
else
    echo "   ❌ Config file not found: $CONFIG_PATH"
fi

echo ""

# 5. Check KeyPath app status
echo "5. KeyPath App Status:"
echo "---------------------"
KEYPATH_PROCS=$(ps aux | grep -E "[K]eyPath\.app" | wc -l | tr -d ' ')
echo "   KeyPath processes running: $KEYPATH_PROCS"

if [ "$KEYPATH_PROCS" -gt 0 ]; then
    KEYPATH_PID=$(ps aux | grep -E "[K]eyPath\.app" | awk '{print $2}' | head -1)
    echo "   KeyPath PID: $KEYPATH_PID"
fi

echo ""

# 6. Connection Assessment
echo "6. Connection Assessment:"
echo "------------------------"

# Check if process PID matches service PID
if [ "$KANATA_PROCS" -eq 1 ] && [ -n "$SERVICE_PID" ]; then
    ACTUAL_PID=$(ps aux | grep -E "[k]anata.*--cfg" | awk '{print $2}')
    if [ "$SERVICE_PID" = "$ACTUAL_PID" ]; then
        echo "   ✅ Process PID matches LaunchDaemon PID ($SERVICE_PID)"
        echo "   ✅ SERVICE MANAGEMENT: Connected"
    else
        echo "   ❌ Process PID ($ACTUAL_PID) ≠ LaunchDaemon PID ($SERVICE_PID)"
        echo "   ❌ SERVICE MANAGEMENT: Disconnected"
    fi
elif [ "$KANATA_PROCS" -eq 0 ]; then
    echo "   ❌ No Kanata processes running"
    echo "   ❌ SERVICE MANAGEMENT: Missing"
elif [ "$KANATA_PROCS" -gt 1 ]; then
    echo "   ❌ Multiple Kanata processes running"
    echo "   ❌ SERVICE MANAGEMENT: Conflicted"
else
    echo "   ❌ Cannot determine service connection"
    echo "   ❌ SERVICE MANAGEMENT: Unknown"
fi

echo ""
echo "🔧 To test KeyPath's control over the service, try:"
echo "   1. Make a config change in KeyPath app"
echo "   2. Check if this script shows PID changes"
echo "   3. Check if TCP reload happens automatically"