#!/bin/bash

echo "🧹 Clearing large log files..."

# Clear system kanata log (if exists and is large)
if [ -f "/var/log/kanata.log" ]; then
    LOG_SIZE=$(stat -f%z "/var/log/kanata.log" 2>/dev/null || echo "0")
    LOG_SIZE_MB=$((LOG_SIZE / 1024 / 1024))
    echo "📊 Current kanata.log size: ${LOG_SIZE_MB}MB"
    
    if [ "$LOG_SIZE_MB" -gt 10 ]; then
        echo "🚨 Log file is large (${LOG_SIZE_MB}MB), clearing..."
        sudo truncate -s 0 /var/log/kanata.log
        echo "✅ Cleared /var/log/kanata.log"
    else
        echo "✅ kanata.log size is acceptable (${LOG_SIZE_MB}MB)"
    fi
else
    echo "ℹ️  No system kanata.log found"
fi

# Clear user KeyPath logs (if they exist and are large)
KEYPATH_LOG_DIR="$HOME/Library/Logs/KeyPath"
if [ -d "$KEYPATH_LOG_DIR" ]; then
    echo "📁 Checking KeyPath user logs..."
    find "$KEYPATH_LOG_DIR" -name "*.log" -size +10M -exec ls -lh {} \; -exec truncate -s 0 {} \; -exec echo "✅ Cleared {}" \;
else
    echo "ℹ️  No KeyPath user log directory found"
fi

echo "🎯 Log cleanup complete!"