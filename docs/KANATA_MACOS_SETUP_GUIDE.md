# Kanata Setup and Debugging Guide for macOS

This guide covers the complete process of installing, configuring, and debugging Kanata keyboard remapper on macOS, including solutions to common issues encountered during setup.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Development Setup](#development-setup)

## Prerequisites

### System Requirements
- macOS 13.0 (Ventura) or later
- Apple Developer ID certificate for code signing (required for system-level access)
- Administrator privileges

### Required Dependencies
1. **Karabiner-DriverKit-VirtualHIDDevice** (Essential!)
2. **Rust toolchain** (if compiling from source)
3. **Homebrew** (optional, for easy installation)

## Installation

### Option 1: Install via Homebrew
```bash
brew install kanata
```

### Option 2: Compile from Source (Recommended for latest features)

#### 1. Install Rust
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

#### 2. Clone and compile Kanata
```bash
git clone https://github.com/jtroo/kanata.git
cd kanata
cargo build --release --features "cmd,tcp_server,watch"
```

#### 3. Install the binary
```bash
sudo cp target/release/kanata /usr/local/bin/kanata
```

#### 4. Code sign the binary (CRITICAL for macOS security)
```bash
# Replace with your Developer ID
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
sudo codesign --force \
    --options=runtime \
    --sign "$SIGNING_IDENTITY" \
    --identifier "com.yourapp.kanata" \
    --timestamp \
    /usr/local/bin/kanata
```

### Installing Karabiner-DriverKit-VirtualHIDDevice

This is **absolutely essential** - Kanata cannot function without it.

#### 1. Download the driver
- Visit: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases
- Download the latest `.pkg` file (e.g., `Karabiner-DriverKit-VirtualHIDDevice-6.0.0.pkg`)

#### 2. Install the package
- Double-click the `.pkg` file and follow the installer

#### 3. Activate the driver
```bash
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

#### 4. Approve the system extension
- Go to **System Settings > Privacy & Security > Login Items & Extensions**
- Click **"By Category"** tab
- Find **"Driver Extensions"** section  
- Approve **"Karabiner-DriverKit-VirtualHIDDevice"**

#### 5. Start the daemon (CRITICAL!)
```bash
sudo "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon" > /dev/null 2>&1 &
```

**Note:** The daemon MUST be running for Kanata to work. Without it, you'll get TCP connection errors and an unresponsive keyboard.

## Configuration

### Permissions Setup

#### 1. Grant TCC Permissions
Kanata needs both Input Monitoring and Accessibility permissions:

- **System Settings > Privacy & Security > Input Monitoring**
  - Add `/usr/local/bin/kanata`
- **System Settings > Privacy & Security > Accessibility** 
  - Add `/usr/local/bin/kanata`

#### 2. Terminal/Shell Permissions
Your terminal (Terminal.app, Ghostty, etc.) also needs:
- **System Settings > Privacy & Security > Input Monitoring**
  - Add your terminal application

### Basic Configuration File

Create a configuration file (e.g., `keypath.kbd`):

```lisp
;; Basic Kanata configuration
(defcfg
  process-unmapped-keys no
  danger-enable-cmd yes
)

(defsrc
  caps
)

(deflayer base
  esc
)
```

### Running Kanata

```bash
# Basic usage
sudo /usr/local/bin/kanata --cfg /path/to/your/config.kbd

# With hot reload (watches for config changes)
sudo /usr/local/bin/kanata --cfg /path/to/your/config.kbd --watch

# With debug output
sudo /usr/local/bin/kanata --debug --cfg /path/to/your/config.kbd
```

## Troubleshooting

### Diagnostic Commands

#### Check Kanata Installation
```bash
which kanata
/usr/local/bin/kanata --version
codesign -d -vvv /usr/local/bin/kanata
```

#### Check Driver Status
```bash
# System extension status
systemextensionsctl list | grep -i karabiner

# Driver activation status
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager
```

#### Check Daemon Status
```bash
# Check if daemon is running
ps aux | grep "VirtualHIDDevice-Daemon" | grep -v grep

# Check for conflicting processes
ps aux | grep -i karabiner | grep -v grep
ps aux | grep -i kanata | grep -v grep
```

#### Check Permissions
```bash
# Check TCC database
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT service, client, auth_value FROM access WHERE client LIKE '%kanata%';"

# Should show:
# kTCCServiceAccessibility|/usr/local/bin/kanata|2
# kTCCServiceListenEvent|/usr/local/bin/kanata|2
```

### Debug Mode
```bash
# Enable debug logging
sudo /usr/local/bin/kanata --debug --cfg /path/to/config.kbd

# Enable trace logging (most verbose)
sudo /usr/local/bin/kanata --trace --cfg /path/to/config.kbd
```

## Common Issues and Solutions

### 1. "IOHIDDeviceOpen error: (iokit/common) privilege violation"

**Symptoms:**
- Kanata starts but keyboard becomes unresponsive
- Error message about privilege violation

**Causes:**
- Kanata binary not properly code-signed
- Missing TCC permissions
- Binary replaced without updating permissions

**Solutions:**
1. **Re-sign the binary:**
   ```bash
   sudo codesign --force --options=runtime --sign "Developer ID Application: Your Name" --timestamp /usr/local/bin/kanata
   ```

2. **Reset TCC permissions:**
   - Remove kanata from Input Monitoring and Accessibility
   - Re-add it to both sections
   - Restart your terminal

3. **Restart the system** (sometimes required for TCC changes)

### 2. "connect_failed asio.system:61" (Connection Refused)

**Symptoms:**
- Endless `connect_failed asio.system:61` messages
- Keyboard becomes unresponsive
- Kanata appears to start but doesn't function

**Root Cause:**
The Karabiner-VirtualHIDDevice-Daemon is not running. This daemon provides the TCP interface that Kanata uses to communicate with the virtual HID device.

**Solution:**
```bash
# Start the daemon
sudo "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon" > /dev/null 2>&1 &

# Verify it's running
ps aux | grep "VirtualHIDDevice-Daemon" | grep -v grep
```

### 3. "Karabiner-VirtualHIDDevice driver is not activated"

**Symptoms:**
- Clear error message about driver not being activated
- Kanata fails to start

**Solution:**
1. **Activate the driver:**
   ```bash
   /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
   ```

2. **Approve in System Settings:**
   - System Settings > Privacy & Security > Login Items & Extensions
   - "By Category" tab > "Driver Extensions"
   - Approve "Karabiner-DriverKit-VirtualHIDDevice"

### 4. "error: unexpected argument '--watch' found"

**Symptoms:**
- `--watch` flag not recognized
- Using older version of Kanata

**Solution:**
- You're running an older version (1.8.x) that doesn't support `--watch`
- Upgrade to Kanata 1.9.0+ or remove the `--watch` flag

### 5. Keyboard Unresponsive After Starting Kanata

**Emergency Exit:**
- Press `Ctrl+Space+Escape` to force-quit Kanata
- This is Kanata's built-in emergency exit

**Causes & Solutions:**
1. **Daemon not running** → Start the Karabiner daemon (see solution #2)
2. **Invalid configuration** → Validate config with `kanata --cfg config.kbd --check`
3. **Permission issues** → Check TCC permissions and code signing

### 6. Permission Denied When Installing Binary

**Solution:**
```bash
# Make sure you have the right permissions
sudo chown $(whoami) /usr/local/bin/kanata
# Or use sudo for the copy operation
sudo cp target/release/kanata /usr/local/bin/kanata
```

## Development Setup

### Compiling with Specific Features

```bash
# Minimal build (no TCP server)
cargo build --release --no-default-features --features "cmd,watch"

# Full featured build
cargo build --release --features "cmd,tcp_server,watch,zippychord"

# Debug build with symbols
cargo build --features "cmd,tcp_server,watch"
```

### Testing Different Versions

```bash
# Checkout specific version
git tag --sort=-version:refname | head -10
git checkout v1.8.1

# Build and test
cargo build --release
./target/release/kanata --version
```

### Debugging Build Issues

```bash
# Check dependencies
cargo tree | grep -i tcp

# Clean build
cargo clean
cargo build --release

# Check what features are enabled
cargo build --release --features "cmd,watch" -v
```

## Architecture Notes

### How It All Works Together

1. **Karabiner-DriverKit-VirtualHIDDevice**: System extension that provides virtual HID devices
2. **Karabiner-VirtualHIDDevice-Daemon**: User-space daemon that manages the virtual devices
3. **Kanata**: Connects to the daemon via TCP to send keyboard events

### Key Files and Locations

- **Kanata binary**: `/usr/local/bin/kanata`
- **Driver location**: `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/`
- **Daemon binary**: `Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon`
- **System extension**: `/Library/SystemExtensions/*/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext/`
- **TCC database**: `/Library/Application Support/com.apple.TCC/TCC.db`

## Automation Scripts

### Auto-start Daemon Script

Create a script to automatically start the daemon:

```bash
#!/bin/bash
# start-karabiner-daemon.sh

DAEMON_PATH="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

# Check if daemon is already running
if ! pgrep -f "VirtualHIDDevice-Daemon" > /dev/null; then
    echo "Starting Karabiner daemon..."
    sudo "$DAEMON_PATH" > /dev/null 2>&1 &
    sleep 2
    if pgrep -f "VirtualHIDDevice-Daemon" > /dev/null; then
        echo "✅ Daemon started successfully"
    else
        echo "❌ Failed to start daemon"
        exit 1
    fi
else
    echo "✅ Daemon already running"
fi
```

### Complete Setup Verification Script

```bash
#!/bin/bash
# verify-kanata-setup.sh

echo "=== Kanata Setup Verification ==="

# Check kanata binary
if command -v kanata &> /dev/null; then
    echo "✅ Kanata binary found: $(which kanata)"
    echo "   Version: $(kanata --version)"
else
    echo "❌ Kanata binary not found"
fi

# Check code signing
echo "📝 Code signing status:"
codesign -d -vvv /usr/local/bin/kanata 2>&1 | grep -E "Signature|TeamIdentifier|Identifier"

# Check driver
echo "🔌 Driver status:"
systemextensionsctl list | grep -i karabiner || echo "❌ Driver not found"

# Check daemon
if pgrep -f "VirtualHIDDevice-Daemon" > /dev/null; then
    echo "✅ Karabiner daemon is running"
else
    echo "❌ Karabiner daemon is NOT running"
fi

# Check permissions
echo "🔐 TCC permissions:"
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT service, client, auth_value FROM access WHERE client LIKE '%kanata%';" 2>/dev/null || echo "❌ No TCC permissions found"

echo "=== Verification Complete ==="
```

## Conclusion

The key insight from our debugging: **Kanata requires the Karabiner-VirtualHIDDevice-Daemon to be running**. Most issues stem from:

1. Missing or improperly signed binary
2. Missing TCC permissions  
3. Daemon not running
4. Driver not activated

Always start troubleshooting by ensuring the daemon is running and the driver is properly activated. The TCP connection errors are almost always related to the daemon not being available.

## Resources

- [Kanata GitHub Repository](https://github.com/jtroo/kanata)
- [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
- [Kanata Configuration Guide](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)
- [macOS Code Signing Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)