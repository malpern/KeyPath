#!/bin/bash
# Test script to reproduce Kanata TCP reload crash
# Temporarily disables safety monitors to test if crash still occurs

set -e

echo "=== Kanata TCP Reload Crash Test ==="
echo "This script will send rapid reload commands with wait=true"
echo "to test if the crash still occurs."
echo ""

# Check if kanata is running
if ! pgrep -f kanata > /dev/null; then
    echo "❌ Error: Kanata daemon is not running"
    exit 1
fi

KANATA_PID=$(pgrep -f kanata | head -1)
echo "✅ Kanata daemon running (PID: $KANATA_PID)"

# TCP port (default kanata TCP port)
TCP_PORT=37001

# Function to send reload command
send_reload() {
    local attempt=$1
    echo "[$attempt] Sending reload command with wait=true..."
    
    # Send reload command via TCP
    echo '{"Reload": {"wait": true, "timeout_ms": 5000}}' | nc -w 1 localhost $TCP_PORT > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "    ✅ Command sent successfully"
    else
        echo "    ❌ Failed to send command"
    fi
}

# Function to check if kanata crashed (PID changed)
check_crash() {
    local original_pid=$1
    local current_pid=$(pgrep -f kanata | head -1)
    
    if [ -z "$current_pid" ]; then
        echo "    🚨 Kanata process not found - CRASHED!"
        return 1
    fi
    
    if [ "$current_pid" != "$original_pid" ]; then
        echo "    🚨 PID changed ($original_pid -> $current_pid) - CRASHED AND RESTARTED!"
        return 1
    fi
    
    return 0
}

# Test parameters
MAX_ATTEMPTS=10
DELAY_BETWEEN_ATTEMPTS=3  # seconds

echo "Starting test: $MAX_ATTEMPTS reload attempts with ${DELAY_BETWEEN_ATTEMPTS}s delay"
echo "Monitoring for crashes..."
echo ""

ORIGINAL_PID=$KANATA_PID
CRASH_DETECTED=0

for i in $(seq 1 $MAX_ATTEMPTS); do
    echo "--- Attempt $i/$MAX_ATTEMPTS ---"
    send_reload $i
    
    # Wait a moment, then check for crash
    sleep 2
    
    if ! check_crash $ORIGINAL_PID; then
        CRASH_DETECTED=1
        echo ""
        echo "🚨 CRASH DETECTED on attempt $i!"
        echo "Check logs at: /var/log/com.keypath.kanata.stdout.log"
        break
    fi
    
    # Wait before next attempt
    if [ $i -lt $MAX_ATTEMPTS ]; then
        sleep $DELAY_BETWEEN_ATTEMPTS
    fi
done

echo ""
if [ $CRASH_DETECTED -eq 0 ]; then
    echo "✅ Test completed - no crashes detected"
    echo "   (This could mean the crash is fixed, or requires different conditions)"
else
    echo "❌ Crash reproduced!"
    echo "   Check logs for details:"
    echo "   tail -100 /var/log/com.keypath.kanata.stdout.log"
fi

