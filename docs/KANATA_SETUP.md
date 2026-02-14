# KeyPath Kanata Setup Guide

## 🎯 Overview

KeyPath uses a simplified Karabiner-Elements inspired architecture with system-level LaunchDaemon for reliable Kanata management and hot reload functionality.

## ✅ System Status

**All core functionality is implemented and tested:**

- ✅ **Config Generation** - Validated Kanata configs with proper key mapping
- ✅ **Service Management** - LaunchDaemon installation and control
- ✅ **Hot Reload** - Automatic config updates and service restart
- ✅ **Auto-launch** - System-level service management
- ✅ **Status Checking** - Real-time service monitoring

## 🚀 Installation

### Prerequisites
```bash
# Install Kanata
brew install kanata

# Build KeyPath
./build.sh

# Incremental local iteration (after first build)
./Scripts/quick-deploy.sh
```

### System Installation
```bash
# Install system-wide via CLI
sudo ./install-system.sh install
```

### Test Installation
```bash
# Run comprehensive tests
./test-kanata-system.sh

# Test hot reload
./test-hot-reload.sh

# Test service status
./test-service-status.sh
```

## 🔧 Architecture

### Components

1. **KeyPath.app** - SwiftUI application for recording keypaths
2. **KanataManager** - Service management and config generation
3. **LaunchDaemon** - System-level Kanata service at `/Library/LaunchDaemons/com.keypath.kanata.plist`
4. **Config File** - Kanata configuration at `/usr/local/etc/kanata/keypath.kbd`

### Data Flow

```
User records keypath
        ↓
KeyPath.app captures keys
        ↓
KanataManager.saveConfiguration()
        ↓
Generate valid Kanata config
        ↓
Write to /usr/local/etc/kanata/keypath.kbd
        ↓
KanataManager.restartKanata()
        ↓
launchctl kickstart -k system/com.keypath.kanata
        ↓
Kanata service restarts with new config
        ↓
New keypath is active immediately
```

## 📋 Service Management

### Manual Commands
```bash
# Start service
sudo launchctl kickstart -k system/com.keypath.kanata

# Stop service
sudo launchctl kill TERM system/com.keypath.kanata

# Check status
sudo launchctl print system/com.keypath.kanata

# View logs
tail -f /var/log/com.keypath.kanata.stdout.log
tail -f /var/log/com.keypath.kanata.stderr.log
```

### Programmatic Control
```swift
// In KanataManager
await startKanata()        // Start service
await stopKanata()         // Stop service  
await restartKanata()      // Restart service
await updateStatus()       // Check status
await isKanataRunning()    // Get running state
```

## 🔄 Hot Reload Process

### Automatic Hot Reload
1. **User Action**: Records new keypath in KeyPath.app
2. **Config Generation**: App generates valid Kanata config
3. **File Update**: Config saved to `/usr/local/etc/kanata/keypath.kbd`
4. **Service Restart**: `launchctl kickstart -k system/com.keypath.kanata`
5. **Immediate Effect**: New keypath is active within seconds

### Manual Hot Reload
```bash
# Edit config file
sudo nano /usr/local/etc/kanata/keypath.kbd

# Restart service to apply changes
sudo launchctl kickstart -k system/com.keypath.kanata
```

## 🧪 Testing

### Full Test Suite
```bash
# Run all tests
./test-kanata-system.sh
```

### Individual Tests
```bash
# Test config generation
./test-hot-reload.sh

# Test service management
./test-service-status.sh

# Test installation readiness
./test-installer.sh
```

## 📁 File Structure

```
KeyPath/
├── Sources/KeyPath/
│   ├── KanataManager.swift      # Service management
│   ├── ContentView.swift        # Main UI
│   ├── KeyboardCapture.swift    # Key capture
│   └── ...
├── build/
│   └── KeyPath.app             # Built application
├── install-system.sh           # System installer
├── uninstall.sh               # System uninstaller
├── test-kanata-system.sh      # Comprehensive tests
└── test-hot-reload.sh         # Hot reload tests
```

## 🛠️ Configuration

### LaunchDaemon Configuration
```xml
<!-- /Library/LaunchDaemons/com.keypath.kanata.plist -->
<key>ProgramArguments</key>
<array>
    <string>/opt/homebrew/bin/kanata</string>
    <string>--cfg</string>
    <string>/usr/local/etc/kanata/keypath.kbd</string>
</array>
<key>RunAtLoad</key>
<false/>
<key>KeepAlive</key>
<false/>
```

### Sample Kanata Config
```lisp
;; KeyPath Generated Configuration
;; Input: caps -> Output: escape

(defcfg
  process-unmapped-keys yes
)

(defsrc
  caps
)

(deflayer base
  esc
)
```

## 🔍 Troubleshooting

### Common Issues

1. **Service won't start**
   - Check Kanata installation: `which kanata`
   - Validate config: `kanata --cfg /usr/local/etc/kanata/keypath.kbd --check`
   - Check logs: `tail -f /var/log/com.keypath.kanata.stderr.log`

2. **Config invalid**
   - Run: `./test-hot-reload.sh`
   - Fix any validation errors
   - Use test configs as reference

3. **Hot reload not working**
   - Check service status: `sudo launchctl print system/com.keypath.kanata`
   - Restart service: `sudo launchctl kickstart -k system/com.keypath.kanata`
   - Check app permissions in System Preferences

## 🚀 Ready for Production

The system is fully tested and ready for production use:

- **Reliable**: No XPC timeouts or beach ball issues
- **Simple**: File-based configuration, no complex IPC
- **Fast**: Hot reload in seconds, not minutes
- **Stable**: System-level service management
- **Tested**: Comprehensive test suite validates all functionality

**Next Step**: Install the system and start using KeyPath for keypath recording!
