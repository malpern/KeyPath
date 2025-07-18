# KeyPath - Simplified Keyboard Remapping for macOS

KeyPath is a macOS application that provides simple keyboard remapping using Kanata. It features a clean SwiftUI interface and a reliable system-level service architecture inspired by Karabiner-Elements.

## 🎯 Features

- **Simple Interface**: Clean SwiftUI app for recording keypaths
- **System-Level Service**: Reliable LaunchDaemon architecture
- **Hot Reload**: Instant config updates without manual restarts
- **Kanata Integration**: Powered by the robust Kanata keyboard remapper
- **No XPC Complexity**: File-based configuration for maximum reliability

## 🚀 Quick Start

### Prerequisites
- macOS 13.0 or later
- Kanata installed via Homebrew: `brew install kanata`

### Installation
1. **Build the app**:
   ```bash
   ./build.sh
   ```

2. **Install the system service**:
   ```bash
   sudo ./install-system.sh
   ```

3. **Launch the app**:
   ```bash
   open /Applications/KeyPath.app
   ```

4. **Grant Accessibility permissions** in System Preferences > Security & Privacy > Accessibility

## 📱 Usage

1. **Record a keypath**:
   - Click "Record Input" and press a key (e.g., Caps Lock)
   - Enter the desired output key (e.g., "escape")
   - Click "Save KeyPath"

2. **The service automatically updates** and applies the new mapping

3. **Monitor status** in the app interface

## 🔧 Architecture

KeyPath uses a simplified architecture inspired by Karabiner-Elements:

- **KeyPath.app**: SwiftUI frontend for recording keypaths
- **System LaunchDaemon**: Runs Kanata as a system service
- **File-based Config**: Direct config file updates (no XPC)
- **Hot Reload**: Automatic service restart on config changes

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
tail -f /var/log/kanata.log
```

### Programmatic Control
The `KanataManager` class provides async methods:
- `startKanata()` - Start the service
- `stopKanata()` - Stop the service
- `restartKanata()` - Restart the service
- `isKanataRunning()` - Check if running

## 🧪 Testing

### Run All Tests
```bash
./run-tests.sh
```

### Individual Test Suites
```bash
# Unit tests
swift test

# Integration tests
./test-kanata-system.sh
./test-hot-reload.sh
./test-service-status.sh
./test-installer.sh
```

### Test Coverage
- **Unit Tests**: 13/13 passing (100%)
- **Integration Tests**: 4/4 passing (100%)
- **System Validation**: Complete
- **Performance Benchmarks**: Established

## 🛠️ Development

### Build System
- **Swift Package Manager**: Modern Swift toolchain
- **XCTest**: Comprehensive unit testing
- **Shell Scripts**: Integration and system testing

### Project Structure
```
KeyPath/
├── Sources/KeyPath/
│   ├── App.swift                 # Main app entry point
│   ├── ContentView.swift         # Main UI
│   ├── KanataManager.swift       # Service management
│   ├── KeyboardCapture.swift     # Key capture logic
│   ├── SettingsView.swift        # Settings interface
│   └── InstallerView.swift       # Installation UI
├── Tests/KeyPathTests/
│   └── KeyPathTests.swift        # Unit tests
├── build.sh                      # Build script
├── install-system.sh             # System installer
├── uninstall.sh                  # Uninstaller
├── test-*.sh                     # Test suites
└── run-tests.sh                  # Test runner
```

## 📊 Key Mappings

KeyPath supports standard key names:
- **Special keys**: `caps`, `space`, `tab`, `escape`, `return`, `delete`
- **Letters**: `a-z`
- **Numbers**: `0-9`
- **Sequences**: Multi-character outputs become macros

## 🔍 Troubleshooting

### Common Issues

1. **Service won't start**:
   - Check Kanata installation: `which kanata`
   - Validate config: `kanata --cfg /usr/local/etc/kanata/keypath.kbd --check`
   - Check logs: `tail -f /var/log/kanata.log`

2. **App can't record keys**:
   - Grant Accessibility permissions in System Preferences
   - Restart the app after granting permissions

3. **Config not updating**:
   - Check service status: `sudo launchctl print system/com.keypath.kanata`
   - Restart service: `sudo launchctl kickstart -k system/com.keypath.kanata`

### Debug Mode
Enable detailed logging in the config file:
```lisp
(defcfg
  process-unmapped-keys yes
  ;; Add debug options here
)
```

## 🚫 Uninstallation

To completely remove KeyPath:
```bash
sudo ./uninstall.sh
```

This removes:
- LaunchDaemon service
- Configuration files
- KeyPath app
- Log files

## 🏗️ Architecture Benefits

### vs. Complex XPC Approach
- **❌ XPC**: Timeout issues, beach balls, complex debugging
- **✅ KeyPath**: Simple file-based, reliable, fast hot reload

### vs. Karabiner-Elements
- **Similar**: System-level service, file-based config
- **Different**: Focused on simplicity, Kanata backend, Swift UI

## 📄 License

This project is provided as-is for educational and personal use.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Run the test suite: `./run-tests.sh`
5. Submit a pull request

## 🔗 Related Projects

- **Kanata**: The keyboard remapping engine
- **Karabiner-Elements**: Inspiration for the architecture
- **Swift Package Manager**: Build system