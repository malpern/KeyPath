#!/bin/bash

# Debug script to test the LaunchDaemon installation command
# This replicates what KeyPath runs internally

set -e
set -x  # Enable command echoing

echo "🔧 Testing LaunchDaemon installation command..."

# Simulate the same variables KeyPath would use
LAUNCH_DAEMONS_PATH="/Library/LaunchDaemons"
KANATA_SERVICE_ID="com.keypath.kanata"
VHID_DAEMON_SERVICE_ID="com.keypath.karabiner-vhiddaemon"  
VHID_MANAGER_SERVICE_ID="com.keypath.karabiner-vhidmanager"
USER_CONFIG_DIR="$HOME/.config/keypath"
USER_CONFIG_PATH="$HOME/.config/keypath/keypath.kbd"
CURRENT_USERNAME=$(whoami)

# Create temporary plist files (simulate what KeyPath does)
TEMP_DIR="/tmp"
KANATA_TEMP="$TEMP_DIR/$KANATA_SERVICE_ID.plist"
VHID_DAEMON_TEMP="$TEMP_DIR/$VHID_DAEMON_SERVICE_ID.plist"
VHID_MANAGER_TEMP="$TEMP_DIR/$VHID_MANAGER_SERVICE_ID.plist"

# Create mock plist files
cat > "$KANATA_TEMP" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>/Users/malpern/.config/keypath/keypath.kbd</string>
    </array>
</dict>
</plist>
EOF

cat > "$VHID_DAEMON_TEMP" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.karabiner-vhiddaemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon</string>
    </array>
</dict>
</plist>
EOF

cat > "$VHID_MANAGER_TEMP" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.karabiner-vhidmanager</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager</string>
    </array>
</dict>
</plist>
EOF

# Set up final paths
KANATA_FINAL="$LAUNCH_DAEMONS_PATH/$KANATA_SERVICE_ID.plist"
VHID_DAEMON_FINAL="$LAUNCH_DAEMONS_PATH/$VHID_DAEMON_SERVICE_ID.plist"
VHID_MANAGER_FINAL="$LAUNCH_DAEMONS_PATH/$VHID_MANAGER_SERVICE_ID.plist"

# Create the default config content
DEFAULT_CONFIG_CONTENT="        ;; Default KeyPath configuration
        (defcfg
          process-unmapped-keys no
        )

        (defsrc)
        (deflayer base)
        "

echo "🔧 About to run the problematic command..."

# This is the exact command that KeyPath runs
sudo bash -c "
echo 'Installing LaunchDaemon services and configuration...' && \
mkdir -p '$LAUNCH_DAEMONS_PATH' && \
cp '$KANATA_TEMP' '$KANATA_FINAL' && chown root:wheel '$KANATA_FINAL' && chmod 644 '$KANATA_FINAL' && \
cp '$VHID_DAEMON_TEMP' '$VHID_DAEMON_FINAL' && chown root:wheel '$VHID_DAEMON_FINAL' && chmod 644 '$VHID_DAEMON_FINAL' && \
cp '$VHID_MANAGER_TEMP' '$VHID_MANAGER_FINAL' && chown root:wheel '$VHID_MANAGER_FINAL' && chmod 644 '$VHID_MANAGER_FINAL' && \
sudo -u '$CURRENT_USERNAME' mkdir -p '$USER_CONFIG_DIR' && \
if [ ! -f '$USER_CONFIG_PATH' ]; then sudo -u '$CURRENT_USERNAME' cat > '$USER_CONFIG_PATH' << 'KEYPATH_CONFIG_EOF'
$DEFAULT_CONFIG_CONTENT
KEYPATH_CONFIG_EOF
fi && \
launchctl bootstrap system '$KANATA_FINAL' 2>/dev/null || echo 'Kanata service already loaded' && \
launchctl bootstrap system '$VHID_DAEMON_FINAL' 2>/dev/null || echo 'VHID daemon already loaded' && \
launchctl bootstrap system '$VHID_MANAGER_FINAL' 2>/dev/null || echo 'VHID manager already loaded' && \
echo 'Installation completed successfully'
"

echo "✅ Command completed!"

# Check if config file was created correctly
echo "🔍 Checking if config file was created..."
if [ -f "$USER_CONFIG_PATH" ]; then
    echo "✅ Config file exists at: $USER_CONFIG_PATH"
    echo "Contents:"
    cat "$USER_CONFIG_PATH"
else
    echo "❌ Config file does not exist at: $USER_CONFIG_PATH"
fi

# Clean up temp files
rm -f "$KANATA_TEMP" "$VHID_DAEMON_TEMP" "$VHID_MANAGER_TEMP"

echo "🔧 Debug script completed!"