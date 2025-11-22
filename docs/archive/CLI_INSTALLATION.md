# CLI Installation and Usage

KeyPath supports both GUI and CLI modes. You can install and run either one.

## Installing KeyPath via CLI

**To install KeyPath using the CLI** (before KeyPath is installed):

```bash
# Option 1: Use the installer script (easiest)
./Scripts/install-via-cli.sh

# Option 2: Build and run manually
swift build --target KeyPath
.build/arm64-apple-macosx/debug/KeyPath install
```

The installer script builds KeyPath and runs the CLI to perform installation. After installation, you can use the installed app bundle for CLI commands.

## Two Ways to Use the CLI

### Option 1: Integrated CLI (Recommended)
The CLI is built into the KeyPath app bundle. After installing KeyPath.app, you can run CLI commands:

```bash
# Run CLI commands via the app bundle
/Applications/KeyPath.app/Contents/MacOS/KeyPath status
/Applications/KeyPath.app/Contents/MacOS/KeyPath install
/Applications/KeyPath.app/Contents/MacOS/KeyPath uninstall
/Applications/KeyPath.app/Contents/MacOS/KeyPath help

# Or create a symlink for convenience
sudo ln -s /Applications/KeyPath.app/Contents/MacOS/KeyPath /usr/local/bin/keypath-cli
keypath-cli status
```

**Advantages:**
- ✅ Full functionality (uses InstallerEngine, SystemValidator)
- ✅ Single installation
- ✅ Always in sync with GUI

**Note:** When running from the build directory (`.build/...`), there may be initialization timing issues. Use the installed app bundle for best results.

### Option 2: Standalone CLI Executable (Future)
A separate `keypath-cli` executable can be built, but currently requires refactoring to extract `InstallerEngine` and `SystemValidator` to a shared library.

**To enable standalone CLI:**
1. Move `InstallerEngine` and `SystemValidator` to `KeyPathWizardCore` or a new shared library
2. Move `InstallerEngineTypes.swift` (InstallIntent, etc.) to the shared library
3. Update `Package.swift` to make these accessible to `KeyPathCLI` target

**Current Status:** The standalone CLI target exists but cannot access required components.

## Available Commands

```bash
keypath-cli status              # Check system status and wizard readiness
keypath-cli install             # Install KeyPath services and components
keypath-cli repair              # Repair broken or unhealthy services
keypath-cli uninstall           # Uninstall KeyPath (preserves config)
keypath-cli uninstall --delete-config  # Uninstall and delete config
keypath-cli inspect             # Inspect system state (dry-run)
keypath-cli help                # Show help message
```

## Installation

### GUI App
1. Build: `swift build --target KeyPath`
2. Install: Copy `KeyPath.app` to `/Applications/`
3. Run: Double-click or `open -a KeyPath`

### CLI (Integrated)
1. Install KeyPath.app (see above)
2. Create symlink (optional):
   ```bash
   sudo ln -s /Applications/KeyPath.app/Contents/MacOS/KeyPath /usr/local/bin/keypath-cli
   ```
3. Run: `keypath-cli status`

## Current Limitations

- **Build directory execution:** Running CLI from `.build/arm64-apple-macosx/debug/KeyPath` may have timing issues with SwiftUI initialization. Use the installed app bundle.
- **Standalone CLI:** Requires refactoring to extract shared components (see Option 2 above).

## Future Improvements

1. Extract `InstallerEngine` and `SystemValidator` to `KeyPathWizardCore`
2. Enable standalone CLI executable
3. Add CLI to Homebrew/formula for easy installation
4. Create installer script that sets up symlink automatically

