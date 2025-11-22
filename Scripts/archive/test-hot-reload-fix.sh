#!/bin/bash

# Test the hot reload fix by monitoring logs and making config changes

echo "🧪 Testing Hot Reload Fix"
echo "========================"
echo ""

# Monitor both KeyPath logs and Kanata logs
echo "Starting log monitoring..."
echo "Watch for:"
echo "  1. 'Enabling fallback restart' - KeyPath detects config change"
echo "  2. 'Performing fallback restart' - KeyPath applies fix after 500ms"
echo "  3. 'Live reload successful' - Kanata service restarts successfully"
echo ""

# Start monitoring in background
tail -f /var/log/kanata.log | grep -E "reload|Live|restart|Config.*changed" &
KANATA_PID=$!

echo "Logs monitoring started. Make a config change now..."
echo "Press Ctrl+C to stop monitoring"
echo ""

# Wait for user to interrupt
trap 'echo ""; echo "Stopping log monitoring..."; kill $KANATA_PID 2>/dev/null; exit 0' INT

# Keep script running
while true; do
    sleep 1
done