#!/bin/bash

# Kanata v1.9.0 Reinstall Script with CMD Support
# This script installs the latest stable Kanata with CMD key support

set -e

echo "🚀 Installing Kanata v1.9.0 with CMD support..."

# 1. Install Karabiner VirtualHID driver if not present
echo "🔌 Checking Karabiner VirtualHID driver..."
if ! ps aux | grep -q "Karabiner-DriverKit-VirtualHIDDevice"; then
    echo "❌ Karabiner VirtualHID driver not found!"
    echo "   Please install it manually from:"
    echo "   https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases"
    echo "   Download and install the latest .dmg file, then restart this script."
    exit 1
else
    echo "✅ Karabiner VirtualHID driver is running"
fi

# 2. Download and compile Kanata v1.9.0 with CMD support
echo "📥 Downloading and compiling Kanata v1.9.0..."
cd /tmp
rm -rf kanata-build 2>/dev/null || true
mkdir kanata-build
cd kanata-build

# Clone the repository
git clone https://github.com/jtroo/kanata.git .
git checkout v1.9.0

# Compile with CMD support
echo "🔨 Compiling with CMD support..."
cargo build --release --features cmd

# Install the binary
echo "📦 Installing Kanata binary..."
sudo cp target/release/kanata /usr/local/bin/kanata-cmd
sudo chmod +x /usr/local/bin/kanata-cmd

# 3. Create configuration directory
echo "📁 Creating configuration directory..."
sudo mkdir -p /usr/local/etc/kanata

# 4. Create minimal safe test configuration
echo "📝 Creating safe test configuration..."
sudo tee /usr/local/etc/kanata/safe-test.kbd > /dev/null << 'EOF'
;; Safe test configuration for Kanata
;; Maps F13 key to F14 - very safe for testing

(defsrc
  f13
)

(deflayer base
  f14
)

;; Process unmapped keys to prevent system freeze
(defcfg
  process-unmapped-keys no
  log-layer-changes no
)
EOF

# 5. Create KeyPath configuration template
echo "📝 Creating KeyPath configuration template..."
sudo tee /usr/local/etc/kanata/keypath.kbd > /dev/null << 'EOF'
;; KeyPath configuration template
;; This will be overwritten by the KeyPath app

(defsrc
  caps
)

(deflayer base
  esc
)

;; Safety configuration
(defcfg
  process-unmapped-keys no
  log-layer-changes no
)
EOF

# 6. Set proper permissions
echo "🔐 Setting permissions..."
sudo chown root:wheel /usr/local/bin/kanata-cmd
sudo chown -R root:wheel /usr/local/etc/kanata

# 7. Create LaunchDaemon for system service
echo "🚀 Creating LaunchDaemon..."
sudo tee /Library/LaunchDaemons/com.keypath.kanata.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata-cmd</string>
        <string>--cfg</string>
        <string>/usr/local/etc/kanata/keypath.kbd</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/kanata.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/kanata.err</string>
</dict>
</plist>
EOF

sudo chown root:wheel /Library/LaunchDaemons/com.keypath.kanata.plist
sudo chmod 644 /Library/LaunchDaemons/com.keypath.kanata.plist

# 8. Test the installation
echo "🧪 Testing installation..."
/usr/local/bin/kanata-cmd --version

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Grant permissions to /usr/local/bin/kanata-cmd in:"
echo "   - System Settings > Privacy & Security > Accessibility"
echo "   - System Settings > Privacy & Security > Input Monitoring"
echo "2. Test with: sudo /usr/local/bin/kanata-cmd --cfg /usr/local/etc/kanata/safe-test.kbd"
echo "3. Use KeyPath app to create your custom mappings"
echo ""
echo "⚠️  Remember: On macOS Sequoia beta, there may still be compatibility issues"

# Cleanup
cd /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath
rm -rf /tmp/kanata-build