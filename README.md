# KeyPath - Simple Keyboard Remapping for macOS

<div align="center">
  <img src="https://github.com/user-attachments/assets/keypath-icon.png" alt="KeyPath" width="128" height="128"/>
  
  **Remap any key to any other key with a simple, native macOS app**
  
  [![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
  [![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
</div>

---

## 🎯 What is KeyPath?

**KeyPath is Kanata made easy for macOS.**

[Kanata](https://github.com/jtroo/kanata) is a powerful, cross-platform keyboard remapping engine that can transform your keyboard into exactly what you need. However, using Kanata on macOS requires navigating a maze of technical challenges:

- **Driver installation** via command line
- **Permission debugging** (TCC, Input Monitoring, Accessibility)
- **Service management** (launchd, LaunchDaemons, SMJobBless)
- **Configuration syntax** written by hand in Kanata's DSL
- **Code signing & notarization** for system-level access
- **Debugging** when things go wrong

**KeyPath eliminates all of this complexity** while preserving Kanata's full power. You get enterprise-grade keyboard remapping with consumer-grade ease of use.

### The Problem KeyPath Solves

**Before KeyPath:** To remap keys on macOS with Kanata, you need to:
1. Install the Karabiner VirtualHID driver manually
2. Understand macOS security frameworks (TCC)
3. Configure launchd services with root privileges
4. Write Kanata configuration files in a custom syntax
5. Debug permission issues, service conflicts, and connectivity problems
6. Handle code signing and notarization for system components

**With KeyPath:** Click record, press keys, click save. Done.

KeyPath is a **complete macOS integration layer** that:
- ✅ Handles all system setup automatically
- ✅ Provides a beautiful, native SwiftUI interface
- ✅ Manages permissions, services, and drivers
- ✅ Generates Kanata configurations from visual recordings
- ✅ Offers intelligent troubleshooting and diagnostics
- ✅ Ensures reliable operation with proper system integration

---

## ✨ Why Use KeyPath?

### 🎯 Dead Simple Workflow
**No configuration files, no command line, no technical knowledge required.**

1. Click "Record Input"
2. Press the key(s) you want to remap
3. Click "Record Output"  
4. Press what you want it to do
5. Click Save

Your remapping is active immediately—no restart, no manual service management, no file editing.

### ⚡ Instant & Reliable
- **Hot reload** - Changes apply instantly via UDP communication
- **System integration** - Runs as LaunchDaemon, works at boot time
- **Crash recovery** - Automatic service restart and conflict resolution
- **Health monitoring** - Real-time status checks and diagnostics

### 🛡️ Safe & Secure
- **Emergency stop** - Press `Ctrl + Space + Esc` to immediately disable all remappings
- **Permission wizard** - Guided setup handles all macOS security requirements
- **Conflict detection** - Automatically detects and resolves system conflicts
- **No telemetry** - Works completely offline, no data collection

### 🎨 Native macOS Experience
- **Beautiful SwiftUI interface** with Liquid Glass design (macOS 15+)
- **System Settings integration** - Follows macOS design patterns
- **Proper signing & notarization** - Works with macOS security features
- **Accessibility support** - Respects macOS accessibility settings

### 🔧 Enterprise-Grade Architecture
Built on proven patterns (inspired by Karabiner-Elements):
- **LaunchDaemon architecture** - Reliable system-level service management
- **SMAppService-managed daemon** - Kanata always runs via SMAppService; KeyPath auto-reinstalls the service if it disappears, so helper restarts never fall back to legacy plists
- **File-based configuration** - Simple, debuggable, hot-reloadable
- **Single source of truth** - PermissionOracle prevents inconsistent state
- **State-driven wizard** - Handles 50+ edge cases automatically

---

## 🚀 Getting Started

### Installation

**Option 1: Download Release** (Recommended)
1. Download from the [Releases page](https://github.com/malpern/KeyPath/releases)
2. Open `KeyPath.app`
3. Follow the setup wizard

**Option 2: Build from Source**
```bash
git clone https://github.com/malpern/KeyPath.git
cd KeyPath

# Canonical build (builds, signs, notarizes, deploys to ~/Applications, restarts app)
./build.sh
```

The build script automatically:
- Compiles the Swift package
- Signs all components with Developer ID
- Notarizes the app bundle
- Verifies the bundled SMAppService plist points at `kanata-launcher` (no legacy launchctl fallback)
- Installs to `~/Applications/`
- Restarts the app

### First Launch

When you first launch KeyPath, the **Installation Wizard** will guide you through:

1. **Permission Setup** - Grants Input Monitoring and Accessibility permissions
2. **Driver Installation** - Installs Karabiner VirtualHID driver if needed
3. **Service Configuration** - Sets up LaunchDaemon services
4. **System Validation** - Verifies everything is working correctly

The wizard handles all technical setup automatically and provides one-click fixes for common issues.

### Create Your First Mapping

1. **Record Input**: Click the record button next to "Input Key"
   - Press a single key (e.g., Caps Lock)
   - Or a key combo (e.g., Cmd+Space)
   - Or a sequence (e.g., press A, then B, then C)

2. **Record Output**: Click the record button next to "Output Key"
   - Press what you want it to do (e.g., Escape)
   - Or a combo (e.g., Cmd+C for copy)
   - Or type multiple keys (e.g., "hello world")

3. **Save**: Click Save - your mapping is now active!

---

## 🎁 Features

### For Everyone

| Feature | Description |
|---------|-------------|
| **Flexible Input** | Record single keys, combos (Cmd+C), or sequences (A→B→C) |
| **Flexible Output** | Map to single keys, combos, or entire phrases |
| **Visual Recording** | See exactly what keys you're pressing in real-time |
| **Instant Apply** | Changes work immediately - no restart needed |
| **Safety Features** | Emergency stop (`Ctrl+Space+Esc`) prevents getting locked out |
| **Smart Setup** | Installation wizard handles all technical setup automatically |
| **Native macOS UI** | Beautiful SwiftUI interface with Liquid Glass design (macOS 15+) |

### For Power Users

| Feature | Description |
|---------|-------------|
| **Complex Mappings** | Chain multiple actions from a single trigger |
| **Hot Reload** | Edit config files directly, changes apply instantly via UDP |
| **System Integration** | Runs as LaunchDaemon at startup, works everywhere |
| **Extensive Logging** | Debug issues with detailed logs and diagnostics |
| **Full Kanata Power** | Access to all of Kanata's remapping capabilities |
| **Configuration Access** | Edit Kanata configs directly if needed |
| **Service Health Dashboard** | Visual helper/SMAppService/driver status with one-click fixes |

---

## 📋 Common Use Cases

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

---

## 🏗️ Architecture & Technical Details

### What Makes KeyPath Different

KeyPath isn't just a wrapper around Kanata—it's a **complete macOS integration layer** that solves real problems:

#### 1. **Intelligent Permission Management**
- **PermissionOracle** - Single source of truth for all permission detection
- Handles macOS TCC (Transparency, Consent, Control) complexity
- Detects permission issues before they cause problems
- Provides one-click fixes for common permission problems

#### 2. **Automated System Setup**
- Installs and manages Karabiner VirtualHID driver
- Handles code signing and notarization for all components
- Manages LaunchDaemon services and lifecycle
- Resolves conflicts with other keyboard remappers automatically

#### 3. **Visual Configuration Generation**
- Converts visual key recordings into valid Kanata configuration
- Handles complex modifier combinations and sequences
- Generates optimized Kanata configs automatically
- No need to learn Kanata's configuration syntax

#### 4. **Reliable Service Management**
- LaunchDaemon architecture ensures remappings work at boot time
- Automatic crash recovery and conflict resolution
- Health monitoring with real-time status checks
- Hot reload via UDP for instant configuration updates
- SMAppService-managed Kanata daemon with a packaged launcher guarantees absolute config paths and Login Items approval flow

#### 5. **Comprehensive Diagnostics**
- Built-in system state detection
- Automatic log analysis and error interpretation
- Visual permission status with fix suggestions
- Real-time service health monitoring

### Technical Stack

- **Swift 6.0** - Modern Swift concurrency (async/await, actors)
- **SwiftUI** - Native macOS UI with Liquid Glass design
- **Kanata** - Cross-platform keyboard remapping engine
- **LaunchDaemon** - System-level service management
- **Karabiner VirtualHID** - macOS HID driver for system-level remapping

---

## 🛡️ Safety & Security

### Emergency Stop

If your keyboard becomes unresponsive, press **Ctrl + Space + Esc** simultaneously. This immediately disables all remappings and restores normal keyboard functionality.

### Permission Requirements

KeyPath needs two macOS permissions to work:

1. **Input Monitoring** - To detect key presses
2. **Accessibility** - To send remapped keys

The setup wizard guides you through granting these permissions with one-click access to System Settings.

### Kanata binary location (LaunchDaemon)
For stable TCC permissions, LaunchDaemon services use the system-installed kanata binary:

```
/Library/KeyPath/bin/kanata
```

The helper keeps this binary updated from the bundled copy when needed and ensures proper ownership/permissions. The bundled binary inside `KeyPath.app` is not used by LaunchDaemons.

### What KeyPath Does NOT Do
- ❌ No internet connection required (offline by default; optional AI config generation contacts Anthropic if ANTHROPIC_API_KEY is present)
- ❌ No data collection or telemetry
- ❌ No modification of system files
- ❌ No kernel extensions

## 🔧 Troubleshooting

### KeyPath Won't Start?

1. **Check macOS version** - Requires macOS 15.0 (Sequoia) or later
2. **Run setup wizard** - Go to File → Run Setup Wizard
3. **Check logs** - View system logs: `tail -f /var/log/kanata.log`

### Keys Not Remapping?

1. **Check status indicator** - Look for green checkmarks in the app
2. **Verify permissions** - Ensure permissions granted in System Settings
3. **Use Fix Issues** - Click "Fix Issues" button in the app for automated fixes

### Need More Help?

- 📖 [FAQ](docs/FAQ.md) - Frequently asked questions
- 🐛 [Debugging Guide](docs/DEBUGGING_KANATA.md) - Advanced troubleshooting
- 🔧 [Helper Troubleshooting](docs/troubleshooting-helper.md) - SMAppService issues
- 💬 [GitHub Issues](https://github.com/malpern/KeyPath/issues) - Report bugs or ask questions

### Developer Notes

**Xcode 26 beta test runner crash (Swift 6.2)**

If you're using Xcode 26.0 beta, `swift test` can crash with SIGABRT after tests pass. Use the workaround:

```bash
./run-tests-workaround.sh
```

Our main test runners (`./run-tests.sh` and `./Scripts/run-tests.sh`) already include this workaround.

---

## 🏗️ Requirements

### System Requirements

- **macOS 15.0 (Sequoia) or later**
- **Apple Silicon or Intel Mac**

### Dependencies (Handled Automatically)

- **Kanata** - The remapping engine (bundled with app)
- **Karabiner VirtualHID Driver** - For system-level key events

The setup wizard automatically checks for these and helps you install them if needed.

---

## 🚫 Uninstallation

### Recommended Method

1. Open KeyPath
2. Choose **File → Uninstall KeyPath…** (you can also open **Settings → Advanced → Uninstall KeyPath…**)
3. Confirm the admin prompt and let the bundled uninstaller remove LaunchDaemons, helper tools, and the app bundle.

### Manual Uninstallation

```bash
sudo ./Scripts/uninstall.sh
# or for automation:
sudo ./Scripts/uninstall.sh --assume-yes
```

This removes:
- LaunchDaemon services
- System binaries
- Configuration files
- Application bundle

When running outside the repository, the same script is bundled at `KeyPath.app/Contents/Resources/uninstall.sh` and can be invoked directly.

---

## 🤝 Contributing

We welcome contributions! KeyPath is designed to make keyboard remapping accessible to everyone, and contributions help make it better.

### Quick Start for Contributors

```bash
# Clone the repository
git clone https://github.com/malpern/KeyPath.git
cd KeyPath

# Build and test (development)
swift build
swift test

# Production-like build & deploy (recommended for real testing)
./build.sh
mkdir -p ~/Applications && cp -R dist/KeyPath.app ~/Applications/
osascript -e 'tell application "KeyPath" to quit' || true
open ~/Applications/KeyPath.app
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines, architecture overview, and contribution patterns.

---

## 📚 Documentation

- **[Architecture Overview](ARCHITECTURE.md)** - Deep dive into system design and architecture decisions
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to KeyPath
- **[Debugging Guide](docs/DEBUGGING_KANATA.md)** - Advanced troubleshooting and diagnostics
- **[FAQ](docs/FAQ.md)** - Frequently asked questions

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🧪 Tests

- **Unit & integration tests:** `./Scripts/run-tests-safe.sh` – configures an isolated module cache (`.build-ci/ModuleCache.noindex`) so SwiftPM never tries to write to `~/.cache` (which can be blocked on shared machines).
- **Full developer suite:** `./run-tests.sh` – wraps the safe runner and then executes the higher-level integration scripts.
- **CI-full replicator:** `CI_INTEGRATION_TESTS=true ./run-core-tests.sh` – runs the Unit, Core, and IntegrationTestSuite buckets defined in `run-core-tests.sh`; by default the CI runs with `CI_INTEGRATION_TESTS=false`, so set this flag manually (or adjust CI) when you need the deeper installer/privileged coverage to execute alongside unit/core tests.
- **SMAppService sanity check:** `./Scripts/verify-kanata-plist.sh` – use before distributing a build (CI runs it against `Sources/KeyPath/com.keypath.kanata.plist`).

If `swift test` ever complains about `~/.cache/clang/ModuleCache`, just use the safe runner above or pass `-Xcc -fmodules-cache-path=$(pwd)/.build/ModuleCache.noindex` manually.

---

## 🙏 Acknowledgments

KeyPath stands on the shoulders of giants:

- **[Kanata](https://github.com/jtroo/kanata)** - The powerful keyboard remapping engine that powers KeyPath
- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** - VirtualHID driver and architectural inspiration
- **SwiftUI** - For the beautiful, native macOS experience
- **macOS Security Team** - For the robust security frameworks that make safe keyboard remapping possible

---

<div align="center">
  <strong>Made with ❤️ for the macOS community</strong>
  
  <p>If KeyPath helps you, consider ⭐ starring the repo!</p>
  
  <p><em>KeyPath makes Kanata's power accessible to everyone—no command line required.</em></p>
</div>
