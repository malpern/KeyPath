#!/bin/bash

echo "🔧 Fixing Kanata service installation..."
echo ""

# Remove the broken empty plist file
echo "🗑️ Removing broken plist file..."
sudo rm -f /Library/LaunchDaemons/com.keypath.kanata.plist

# Create plist in temp location first
TEMP_PLIST="/tmp/com.keypath.kanata.plist"
echo "📄 Creating new plist file..."

cat > "$TEMP_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>Program</key>
    <string>/usr/local/bin/kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>/Users/malpern/.config/keypath/keypath.kbd</string>
        <string>--port</string>
        <string>37000</string>
        <string>--watch</string>
        <string>--debug</string>
        <string>--log-layer-changes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kanata.log</string>
</dict>
</plist>
EOF

# Verify the temp plist is valid
echo "🔍 Validating plist syntax..."
if plutil -lint "$TEMP_PLIST"; then
    echo "✅ Plist syntax is valid"
else
    echo "❌ Plist syntax error"
    exit 1
fi

# Copy to LaunchDaemons with proper permissions
echo "📋 Installing plist to LaunchDaemons..."
sudo cp "$TEMP_PLIST" /Library/LaunchDaemons/com.keypath.kanata.plist
sudo chown root:wheel /Library/LaunchDaemons/com.keypath.kanata.plist
sudo chmod 644 /Library/LaunchDaemons/com.keypath.kanata.plist

# Clean up temp file
rm "$TEMP_PLIST"

# Verify the installed plist
echo "🔍 Verifying installed plist..."
if plutil -lint /Library/LaunchDaemons/com.keypath.kanata.plist; then
    echo "✅ Installed plist is valid"
    ls -la /Library/LaunchDaemons/com.keypath.kanata.plist
else
    echo "❌ Installed plist is invalid"
    exit 1
fi

# Load and start the service
echo "🚀 Loading service..."
sudo launchctl load /Library/LaunchDaemons/com.keypath.kanata.plist

echo "🔄 Starting service..."
sudo launchctl kickstart -k system/com.keypath.kanata

echo ""
echo "⏱️ Waiting for service to start..."
sleep 3

# Verify everything is working
echo ""
echo "🔍 Final verification:"
echo ""

# Check service status
if sudo launchctl print system/com.keypath.kanata >/dev/null 2>&1; then
    echo "✅ Service is loaded and managed by launchctl"
    
    # Get service details
    SERVICE_INFO=$(sudo launchctl print system/com.keypath.kanata | grep -E "(state|pid)")
    echo "   $SERVICE_INFO"
else
    echo "❌ Service is not loaded in launchctl"
fi

# Check if kanata process is running
KANATA_PROC=$(ps aux | grep "/usr/local/bin/kanata" | grep -v grep)
if [[ -n "$KANATA_PROC" ]]; then
    echo "✅ Kanata process is running:"
    echo "   $KANATA_PROC"
    
    # Check if it has the --port argument
    if echo "$KANATA_PROC" | grep -q "\--port 37000"; then
        echo "✅ Process includes --port 37000 argument"
    else
        echo "❌ Process missing --port 37000 argument"
    fi
else
    echo "❌ Kanata process not found"
fi

# Check TCP server
if lsof -i :37000 >/dev/null 2>&1; then
    echo "✅ TCP server is listening on port 37000:"
    lsof -i :37000
else
    echo "❌ TCP server not listening on port 37000"
fi

echo ""
echo "📝 To check logs: tail -f /var/log/kanata.log"
echo "🔧 To restart: sudo launchctl kickstart -k system/com.keypath.kanata"