#!/bin/bash

echo "🔧 Installing Kanata service with TCP support..."
echo "You will be prompted for your admin password."
echo ""

# Prompt for password upfront
echo "Please enter your admin password:"
read -s PASSWORD

# Function to run sudo commands with password
run_sudo() {
    echo "$PASSWORD" | sudo -S "$@"
}

# Remove existing service if it exists
if [[ -f "/Library/LaunchDaemons/com.keypath.kanata.plist" ]]; then
    echo "🔄 Removing existing service..."
    echo "$PASSWORD" | sudo -S launchctl unload /Library/LaunchDaemons/com.keypath.kanata.plist 2>/dev/null || true
    echo "$PASSWORD" | sudo -S rm /Library/LaunchDaemons/com.keypath.kanata.plist
fi

# Create the new plist with TCP support
echo "📄 Creating LaunchDaemon plist with TCP server (port 37000)..."
cat << 'EOF' | echo "$PASSWORD" | sudo -S tee /Library/LaunchDaemons/com.keypath.kanata.plist > /dev/null
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

# Set proper ownership and permissions
echo "$PASSWORD" | sudo -S chown root:wheel /Library/LaunchDaemons/com.keypath.kanata.plist
echo "$PASSWORD" | sudo -S chmod 644 /Library/LaunchDaemons/com.keypath.kanata.plist

echo "✅ LaunchDaemon plist created successfully"

# Load the service
echo "🚀 Loading and starting the service..."
echo "$PASSWORD" | sudo -S launchctl load /Library/LaunchDaemons/com.keypath.kanata.plist
echo "$PASSWORD" | sudo -S launchctl kickstart -k system/com.keypath.kanata

echo ""
echo "🎯 Installation complete!"
echo ""

# Clear password from memory
unset PASSWORD

# Wait for service to start
sleep 3

# Verify the installation
echo "🔍 Verification:"
echo ""

# Check if actual kanata process is running (not Cursor extension)
KANATA_PROC=$(ps aux | grep "/usr/local/bin/kanata" | grep -v grep)
if [[ -n "$KANATA_PROC" ]]; then
    echo "✅ Kanata process is running:"
    echo "   $KANATA_PROC"
else
    echo "❌ Kanata process not running"
fi

# Check TCP server
if lsof -i :37000 >/dev/null 2>&1; then
    echo "✅ TCP server listening on port 37000:"
    lsof -i :37000
else
    echo "❌ TCP server not listening on port 37000"
    echo "   (May take a moment to start up)"
fi

echo ""
echo "📝 Check recent logs: tail -5 /var/log/kanata.log"