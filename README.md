# KeyPath - Simple Keyboard Remapping for macOS

<div align="center">
  <img src="https://github.com/user-attachments/assets/keypath-icon.png" alt="KeyPath" width="128" height="128"/>
  
  **Remap any key to any other key with a simple, native macOS app**
  
  [![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
  [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
</div>

KeyPath makes keyboard remapping on macOS simple and reliable. No complex configuration files, no command-line tools - just click to record your keys and save.

## ✨ What is KeyPath?

KeyPath is the easiest way to remap your keyboard on macOS. Whether you want to turn Caps Lock into Escape for Vim, create custom shortcuts, or fix a broken key, KeyPath makes it simple.

### Why Use KeyPath?

- **🎯 Dead Simple**: Click to record any key, click to set what it should do. That's it.
- **⚡ Instant Changes**: Your mappings work immediately - no restarts needed
- **🛡️ Safe & Reliable**: Built-in safety features prevent you from getting locked out
- **🎨 Native macOS App**: Looks and feels like it belongs on your Mac

## 🚀 Getting Started

### 1. Download & Install

Download the latest release from the [Releases page](https://github.com/yourusername/KeyPath/releases) or build from source:

```bash
git clone https://github.com/yourusername/KeyPath.git
cd KeyPath
./Scripts/build.sh
```

### 2. Launch KeyPath

Double-click KeyPath.app to launch. The setup wizard will guide you through everything.

### 3. Create Your First Mapping

1. Click the record button next to "Input Key"
2. Press the key you want to remap (e.g., Caps Lock)
3. Click the record button next to "Output Key"  
4. Press what you want it to become (e.g., Escape)
5. Click Save

That's it! Your key is now remapped.

## 🎁 Features

### For Everyone
- **Visual Key Recording** - See exactly what keys you're pressing
- **Instant Apply** - Changes work immediately, no restart needed
- **Safety First** - Emergency stop prevents getting locked out (Ctrl+Space+Esc)
- **Smart Setup** - Wizard handles all the technical stuff for you

### For Power Users  
- **Multi-Key Sequences** - Map one key to type multiple keys
- **Hot Reload** - Edit config files directly, changes apply instantly
- **System Integration** - Runs at startup, works everywhere
- **Extensive Logging** - Debug issues with detailed logs

## 📋 Common Examples

### Popular Remappings
- **Caps Lock → Escape** - Essential for Vim users
- **Right Cmd → Delete** - Easier reach for frequent deleters
- **F1-F12 → Media Keys** - Volume, brightness, playback control
- **Broken Key Workaround** - Remap a broken key to a working one

### Advanced Uses
- **Hyper Key** - Turn Caps Lock into Cmd+Ctrl+Alt+Shift
- **App Launchers** - Single key to launch favorite apps
- **Text Snippets** - Type your email with one key
- **Gaming** - Custom WASD alternatives

## 🛡️ Safety & Security

### Emergency Stop
If your keyboard becomes unresponsive, press **Ctrl + Space + Esc** simultaneously. This immediately disables all remappings.

### Permission Requirements
KeyPath needs two permissions to work:
1. **Input Monitoring** - To detect key presses
2. **Accessibility** - To send remapped keys

The setup wizard will guide you through granting these permissions.

### What KeyPath Does NOT Do
- ❌ No internet connection required or used
- ❌ No data collection or telemetry
- ❌ No modification of system files
- ❌ No kernel extensions

## 🔧 Troubleshooting

### KeyPath Won't Start?
1. Make sure you have macOS 13 or later
2. Check that Kanata is installed: `brew install kanata`
3. Run the setup wizard again from the File menu

### Keys Not Remapping?
1. Check the status indicator in the app
2. Make sure permissions are granted in System Settings
3. Try the "Fix Issues" button in the app

### Need More Help?
- Check the [FAQ](docs/FAQ.md)
- Read the [Debugging Guide](docs/DEBUGGING_KANATA.md)
- Open an [Issue](https://github.com/yourusername/KeyPath/issues)

## 🏗️ Requirements

### System Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

### Dependencies (Handled Automatically)
- **Kanata** - The remapping engine (installed via Homebrew)
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
./Scripts/build.sh
./Scripts/run-tests.sh

# Make your changes, then test again
swift test
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