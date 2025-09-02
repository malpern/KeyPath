#!/bin/bash

# Script to test KeyPath keyboard recording
echo "🤖 Testing KeyPath keyboard recording functionality..."

# Check if KeyPath is running
if ! pgrep -f "KeyPath" > /dev/null; then
    echo "🤖 KeyPath not running - launching it..."
    open -a KeyPath
    sleep 3
fi

echo "🤖 KeyPath should be running. Now let's check the current logs..."

# Clear the terminal and show current log status
echo "🤖 Current KeyPath log status:"
echo "📊 Log file size: $(du -h ~/Library/Logs/KeyPath/keypath-debug.log | cut -f1)"
echo "📅 Last log entry: $(tail -1 ~/Library/Logs/KeyPath/keypath-debug.log | cut -d']' -f1-2)"

echo ""
echo "🤖 Now I'll monitor logs in real-time while you test recording..."
echo "🤖 Instructions:"
echo "   1. Click in the Input Key field in KeyPath"
echo "   2. Click the record button (🎯 icon)"
echo "   3. Press a key (like 'a' or space)"
echo "   4. Watch for log messages below"
echo ""
echo "🤖 Monitoring logs (Press Ctrl+C to stop)..."
echo "=================================="

# Monitor logs in real-time, filtering for KeyboardCapture events
tail -f ~/Library/Logs/KeyPath/keypath-debug.log | grep --line-buffered -E "(KeyboardCapture|🎯|🔍|✅|❌|RecordingSection|startRecording)"