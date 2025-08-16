#!/bin/bash

# Monitor Kanata hot reload events and play sound feedback
# Usage: ./monitor-hot-reload.sh [sound_file]

SOUND_FILE="${1:-/System/Library/Sounds/Tink.aiff}"
LOG_FILE="/var/log/kanata.log"

echo "🎧 Monitoring Kanata hot reload events..."
echo "🔊 Sound file: $SOUND_FILE"
echo "📝 Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

# Follow the log file and play sound on reload events
tail -f "$LOG_FILE" | while read line; do
    # Check for reload trigger
    if echo "$line" | grep -q "Config file changed.*triggering reload"; then
        timestamp=$(echo "$line" | grep -o '^[0-9:.\[\]m ]*')
        echo "🔄 [$timestamp] Config change detected"
        
        # Play a quick sound for reload start
        afplay "$SOUND_FILE" &
    fi
    
    # Check for successful reload (multiple patterns)
    if echo "$line" | grep -qE "(Live reload successful|reload.*complete|Configuration loaded|reloaded successfully)"; then
        timestamp=$(echo "$line" | grep -o '^[0-9:.\[\]m ]*')
        echo "✅ [$timestamp] Hot reload successful!"
        
        # Play a different sound for success
        afplay "/System/Library/Sounds/Glass.aiff" &
    fi
    
    # Check for reload errors
    if echo "$line" | grep -qi "reload.*error\|reload.*fail"; then
        timestamp=$(echo "$line" | grep -o '^[0-9:.\[\]m ]*')
        echo "❌ [$timestamp] Hot reload failed!"
        
        # Play error sound
        afplay "/System/Library/Sounds/Basso.aiff" &
    fi
done