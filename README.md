# KeyPath - Simplified Keyboard Remapping for macOS

<div align="center">
  <!-- <img src="docs/images/keypath-main.png" alt="KeyPath Main Interface" width="600"/> -->
  
  *Simple, elegant keyboard remapping for macOS*
</div>

KeyPath is a modern macOS application that makes keyboard remapping effortless. Built with SwiftUI and powered by [Kanata](https://github.com/jtroo/kanata), it offers a clean, intuitive interface for creating custom key mappings without the complexity of traditional solutions.

## ✨ Why KeyPath?

**Simple & Intuitive**: Record any key combination with a single click. No complex configuration files to learn.

**Reliable**: Built on Kanata's proven keyboard engine with a streamlined architecture inspired by Karabiner-Elements.

**Fast**: Hot-reload configuration changes instantly. No manual service restarts required.

**Native**: Pure SwiftUI interface that feels at home on macOS with proper system integration.

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
   ./Scripts/build.sh
   ```

2. **Install the system service**:
   ```bash
   sudo ./Scripts/reinstall-kanata.sh
   ```

3. **Launch the app**:
   ```bash
   open /Applications/KeyPath.app
   ```

4. **Grant Accessibility permissions** in System Preferences > Security & Privacy > Accessibility

## 📱 How It Works

### Main Interface
<!-- Screenshots coming soon! -->
<!-- <img src="docs/images/keypath-main.png" alt="KeyPath Main Interface" width="500"/> -->

**Creating a Key Mapping:**
1. **Record Input Key**: Click the play button and press any key (e.g., Caps Lock)
2. **Record Output Key**: Click the second play button and press your desired output (e.g., Escape)  
3. **Save**: Click "Save" to instantly apply the mapping

### Settings & Monitoring
<!-- <img src="docs/images/keypath-settings.png" alt="KeyPath Settings" width="500"/> -->

**Real-time Status Display:**
- **Kanata Service**: Shows if the core remapping engine is running
- **Karabiner Daemon**: Indicates virtual HID device driver status
- **Installation**: Confirms system integration is complete

**Service Control**: Use the settings panel to start, stop, or restart the remapping service as needed.

## 💡 Common Use Cases

- **Caps Lock → Escape**: Perfect for Vim users
- **Function Keys**: Remap F1-F12 to media controls or shortcuts  
- **Arrow Keys**: Create custom navigation with HJKL or WASD
- **Special Characters**: Easy access to symbols and accented characters
- **Application Shortcuts**: Map single keys to complex application commands

## 🔧 Architecture

KeyPath uses a simplified architecture inspired by Karabiner-Elements:

- **KeyPath.app**: SwiftUI frontend for recording keypaths
- **System LaunchDaemon**: Runs Kanata as a system service
- **File-based Config**: Direct config file updates (no XPC)
- **Hot Reload**: Automatic service restart on config changes

## 📁 Project Structure

```
KeyPath/
├── Sources/KeyPath/           # Core SwiftUI application
├── Tests/                     # Unit and integration tests
│   ├── KeyPathTests/         # Swift test suites
│   └── fixtures/             # Test configuration files
├── Scripts/                   # Build, test, and maintenance scripts
├── dev-tools/                 # Development and debugging utilities
├── docs/                      # Documentation and troubleshooting guides
└── dist/                      # Build artifacts (generated)
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
./Scripts/run-tests.sh
```

### Individual Test Suites
```bash
# Unit tests
swift test

# Integration tests
./Scripts/test-hot-reload.sh
./Scripts/test-service-status.sh
./Scripts/test-installer.sh
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
├── Sources/KeyPath/           # Core SwiftUI application
├── Tests/                     # Unit and integration tests
│   ├── KeyPathTests/         # Swift test suites
│   └── fixtures/             # Test configuration files
├── Scripts/                   # Build, test, and maintenance scripts
├── dev-tools/                 # Development and debugging utilities
├── docs/                      # Documentation and troubleshooting guides
└── dist/                      # Build artifacts (generated)
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
   - Validate config: `kanata --cfg "~/Library/Application Support/KeyPath/keypath.kbd" --check`
   - Check logs: View in app or check system logs

2. **App can't record keys**:
   - Grant Accessibility permissions in System Preferences
   - Restart the app after granting permissions

3. **Config not updating**:
   - Use the Settings panel to restart the service
   - Check if Kanata process is running: `pgrep kanata`

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
sudo ./Scripts/uninstall.sh
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
4. Run the test suite: `./Scripts/run-tests.sh`
5. Submit a pull request

## 🙏 Acknowledgments

- **[Kanata](https://github.com/jtroo/kanata)**: The powerful keyboard remapping engine that powers KeyPath
- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)**: Inspiration for the system-level architecture
- **Apple's SwiftUI**: Making native macOS interfaces beautiful and responsive

## 📈 Status

- ✅ **Stable**: Production-ready with comprehensive test coverage
- 🚀 **Active**: Regular updates and improvements  
- 🏠 **Native**: Built specifically for macOS with system integration
- 🔒 **Secure**: Minimal privileges, transparent operation

---

<div align="center">
  <strong>Made with ❤️ for macOS keyboard enthusiasts</strong>
</div>