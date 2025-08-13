#!/bin/bash

echo "🧹 Clearing all large KeyPath log files..."

# Clear system kanata log (requires sudo)
echo "📊 Checking system kanata log..."
if [ -f "/var/log/kanata.log" ]; then
    LOG_SIZE=$(stat -f%z "/var/log/kanata.log" 2>/dev/null || echo "0")
    LOG_SIZE_MB=$((LOG_SIZE / 1024 / 1024))
    echo "Current kanata.log size: ${LOG_SIZE_MB}MB"
    
    if [ "$LOG_SIZE_MB" -gt 0 ]; then
        echo "🚨 Clearing system kanata log..."
        sudo truncate -s 0 /var/log/kanata.log
        echo "✅ Cleared /var/log/kanata.log"
    fi
else
    echo "ℹ️  No system kanata.log found"
fi

# Clear user KeyPath logs
echo "📁 Checking user KeyPath logs..."
KEYPATH_LOG_DIR="$HOME/Library/Logs/KeyPath"
if [ -d "$KEYPATH_LOG_DIR" ]; then
    echo "Finding large log files..."
    find "$KEYPATH_LOG_DIR" -name "*.log" -size +10M -exec ls -lh {} \;
    echo "Clearing large log files..."
    find "$KEYPATH_LOG_DIR" -name "*.log" -size +10M -exec truncate -s 0 {} \; -exec echo "✅ Cleared {}" \;
else
    echo "ℹ️  No KeyPath user log directory found"
fi

echo "🎯 All log cleanup complete!"
echo "The new logging system will now keep logs under control."