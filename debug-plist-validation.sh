#!/bin/bash

echo "🔍 Debugging LaunchDaemon plist validation..."

# Test if we can validate the generated plists
echo "📝 Testing plist generation..."

# Create temp plists using the same method as KeyPath
TEMP_DIR="/tmp"
KANATA_TEMP="$TEMP_DIR/com.keypath.kanata.plist"
VHID_DAEMON_TEMP="$TEMP_DIR/com.keypath.karabiner-vhiddaemon.plist"
VHID_MANAGER_TEMP="$TEMP_DIR/com.keypath.karabiner-vhidmanager.plist"

# Generate the same plists that KeyPath generates
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
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
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
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/karabiner-vhid-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/karabiner-vhid-daemon.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
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
        <string>activate</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/karabiner-vhid-manager.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/karabiner-vhid-manager.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
</dict>
</plist>
EOF

# Test plist validation
echo "🔍 Testing plist syntax validation..."

for plist in "$KANATA_TEMP" "$VHID_DAEMON_TEMP" "$VHID_MANAGER_TEMP"; do
    name=$(basename "$plist")
    echo "Testing $name..."
    if plutil -lint "$plist" >/dev/null 2>&1; then
        echo "  ✅ $name: Valid XML plist"
    else
        echo "  ❌ $name: Invalid XML plist"
        plutil -lint "$plist"
    fi
done

# Test if binaries exist
echo ""
echo "🔍 Testing if binary paths exist..."

binaries=(
    "/usr/local/bin/kanata"
    "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
)

for binary in "${binaries[@]}"; do
    if [[ -x "$binary" ]]; then
        echo "  ✅ $binary: EXISTS and executable"
    elif [[ -f "$binary" ]]; then
        echo "  ⚠️  $binary: EXISTS but not executable"
    else
        echo "  ❌ $binary: MISSING"
    fi
done

# Test simple bootstrap (this will likely fail without sudo, but show the error)
echo ""
echo "🔍 Testing launchctl bootstrap (may require admin privileges)..."
echo "This will likely fail with permission errors, but shows the actual error message:"

for plist in "$KANATA_TEMP" "$VHID_DAEMON_TEMP" "$VHID_MANAGER_TEMP"; do
    name=$(basename "$plist")
    echo "Testing bootstrap for $name..."
    launchctl bootstrap system "$plist" 2>&1 || echo "  (Expected to fail without admin privileges)"
done

# Cleanup
rm -f "$KANATA_TEMP" "$VHID_DAEMON_TEMP" "$VHID_MANAGER_TEMP"

echo "🔧 Debug complete!"