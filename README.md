# KeyPath - Simple Keyboard Remapping for macOS

<div align="center">
  <img src="https://github.com/user-attachments/assets/keypath-icon.png" alt="KeyPath" width="128" height="128"/>
  
  **Remap any key to any other key with a simple, native macOS app**
  
  [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
  [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
</div>

KeyPath makes keyboard remapping on macOS simple and reliable. Built on top of the powerful [Kanata](https://github.com/jtroo/kanata) engine, KeyPath provides a native macOS installer and interface that handles all the complex system setup, dependency management, and debugging that typically requires command-line expertise.

## ✨ What is KeyPath?

KeyPath is the easiest way to remap your keyboard on macOS. Whether you want to turn Caps Lock into Escape for Vim, create custom shortcuts, or fix a broken key, KeyPath makes it simple.

### Why Use KeyPath?

- **🎯 Dead Simple**: Click to record any key, click to set what it should do. That's it.
- **⚡ Instant Changes**: Your mappings work immediately - no restarts needed
- **🛡️ Safe & Reliable**: Built-in safety features prevent you from getting locked out
- **🎨 Native macOS App**: Looks and feels like it belongs on your Mac
- **🔧 Kanata Made Easy**: Harnesses the full power of Kanata without the complexity - no manual driver installation, permission debugging, or configuration file editing required

## 🚀 Getting Started

### 1. Download & Install

Download the latest release from the [Releases page](https://github.com/yourusername/KeyPath/releases) or build from source:

```bash
git clone https://github.com/yourusername/KeyPath.git
cd KeyPath
./Scripts/build-and-sign.sh
```

### 2. Launch KeyPath

Double-click KeyPath.app to launch. The setup wizard will guide you through everything.

### 3. Create Your First Mapping

1. Click the record button next to "Input Key"
2. Press what you want to trigger the mapping:
   - **Single key** (e.g., Caps Lock)
   - **Key combo** (e.g., Cmd+Space)
   - **Key sequence** (e.g., press A, then B, then C)
3. Click the record button next to "Output Key"  
4. Press what you want it to do:
   - **Single key** (e.g., Escape)
   - **Key combo** (e.g., Cmd+C for copy)
   - **Multiple keys** (e.g., type "hello world")
5. Click Save

That's it! Your mapping is now active.

## 🚀 Powered by Kanata

KeyPath is built on top of [Kanata](https://github.com/jtroo/kanata), a powerful cross-platform keyboard remapping engine. While Kanata is incredibly capable, setting it up on macOS traditionally requires significant technical expertise:

### What KeyPath's Installer Handles For You

**Complex System Dependencies:**
- Automatically installs and manages the Karabiner VirtualHID driver
- Handles code signing and notarization for all components
- Manages launchd services and daemon lifecycle
- Resolves TCC (Transparency, Consent, Control) permission issues

**Advanced Debugging & Diagnostics:**
- Built-in system state detection and conflict resolution
- Automatic log analysis and error interpretation  
- Real-time UDP communication monitoring and authentication
- Visual permission status with automated fix suggestions

**Seamless Kanata Integration:**
- Bundles a properly signed Kanata binary for macOS
- Generates Kanata configuration files automatically via AI
- Provides hot-reload capability without service restarts
- Handles complex key sequence and modifier mappings

**Normally, using Kanata on macOS requires:**
- Manual driver installation via command line
- Understanding launchd, SMJobBless, and system service management
- Debugging TCC permissions and Input Monitoring issues
- Writing complex Kanata configuration syntax by hand
- Resolving signing and notarization conflicts

**KeyPath eliminates all of this complexity** while preserving Kanata's full power and flexibility. You get enterprise-grade keyboard remapping with consumer-grade ease of use.

## 🎁 Features

### For Everyone
- **Flexible Input** - Record single keys, combos (Cmd+C), or sequences (A→B→C)
- **Flexible Output** - Map to single keys, combos, or entire phrases
- **Visual Recording** - See exactly what keys you're pressing
- **Instant Apply** - Changes work immediately, no restart needed
- **Safety First** - Emergency stop prevents getting locked out (Ctrl+Space+Esc)
- **Smart Setup** - Wizard handles all the technical stuff for you

### For Power Users  
- **Complex Mappings** - Chain multiple actions from a single trigger
- **Hot Reload** - Edit config files directly, changes apply instantly via UDP
- **System Integration** - Runs at startup, works everywhere
- **Extensive Logging** - Debug issues with detailed logs

## 📋 Common Examples

### Popular Remappings
- **Caps Lock → Escape** - Essential for Vim users
- **Right Cmd → Delete** - Easier reach for frequent deleters
- **F1-F12 → Media Keys** - Volume, brightness, playback control
- **Broken Key Workaround** - Remap a broken key to a working one

### Advanced Uses
- **Hyper Key** - Turn Caps Lock into Cmd+Ctrl+Alt+Shift combo
- **App Launchers** - Map key sequences to launch favorite apps
- **Text Snippets** - Type your email address with a key combo
- **Gaming** - Create custom key combinations for complex moves
- **Workflows** - Map one key to perform multiple actions in sequence

## 🛡️ Safety & Security

### Emergency Stop
If your keyboard becomes unresponsive, press **Ctrl + Space + Esc** simultaneously. This immediately disables all remappings.

### Permission Requirements
KeyPath needs two permissions to work:
1. **Input Monitoring** - To detect key presses
2. **Accessibility** - To send remapped keys

The setup wizard will guide you through granting these permissions.

### What KeyPath Does NOT Do
- ❌ No internet connection required (offline by default; optional AI config generation contacts Anthropic if ANTHROPIC_API_KEY is present)
- ❌ No data collection or telemetry
- ❌ No modification of system files
- ❌ No kernel extensions

## 🔧 Troubleshooting

### KeyPath Won't Start?
1. Make sure you have macOS 14 or later
2. Run the setup wizard again from the File menu
3. Check system logs: `tail -f /var/log/kanata.log`

### Keys Not Remapping?
1. Check the status indicator in the app
2. Make sure permissions are granted in System Settings
3. Try the "Fix Issues" button in the app

### Need More Help?
- Check the [FAQ](docs/FAQ.md)
- Read the [Debugging Guide](docs/DEBUGGING_KANATA.md)
- Investigate helper install errors: [SMAppService Codesigning Error (-67028)](docs/troubleshooting-helper.md)
- Open an [Issue](https://github.com/yourusername/KeyPath/issues)

### Xcode 26 beta test runner crash (Swift 6.2)

If you're using Xcode 26.0 beta (Swift 6.2), `swift test` can crash with SIGABRT after all tests pass due to a beta test runtime cleanup bug. Use the workaround runner:

```bash
./run-tests-workaround.sh
```

Our main runners already use this workaround: `./run-tests.sh` and `./Scripts/run-tests.sh`. For CI, call the workaround script directly until a fixed beta is available.

## 🏗️ Requirements

### System Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

### Dependencies (Handled Automatically)
- **Kanata** - The remapping engine (bundled with app)
- **Karabiner VirtualHID Driver** - For system-level key events

The setup wizard will check for these and help you install them if needed.

## 🚫 Uninstallation

To completely remove KeyPath:

1. Open KeyPath
2. Go to File → Uninstall KeyPath
3. Follow the prompts

Or manually:
```bash
sudo ./Scripts/uninstall.sh
```

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Quick Start for Contributors
```bash
# Clone the repo
git clone https://github.com/yourusername/KeyPath.git
cd KeyPath

# Build and test
swift build
swift test

# Production build
./Scripts/build-and-sign.sh
```

## 📚 Documentation

- **[Architecture Overview](ARCHITECTURE.md)** - Technical details for developers
- **[Debugging Guide](docs/DEBUGGING_KANATA.md)** - Advanced troubleshooting
- **[FAQ](docs/FAQ.md)** - Frequently asked questions


## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- **[Kanata](https://github.com/jtroo/kanata)** - The powerful remapping engine
- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** - VirtualHID driver
- **SwiftUI** - For the native macOS experience

---

<div align="center">
  <strong>Made with ❤️ for the macOS community</strong>
  
  If KeyPath helps you, consider starring the repo!
</div>
