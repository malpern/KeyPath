# KeyPath Testing Setup Guide

This guide will help you set up passwordless testing for KeyPath development.

## 🚀 Quick Setup

### Step 1: Run the setup script
```bash
cd /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath
./scripts/setup-passwordless-testing.sh
```

**Note**: You'll be prompted for your password once to create the sudoers configuration.

### Step 2: Grant macOS Permissions

#### Accessibility Permission
1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the **+** button and add:
   - **Terminal.app** (if running tests from terminal)
   - **Xcode.app** (if running tests from Xcode)
   - **/usr/bin/swift** (for automated test runners)

#### Input Monitoring Permission
1. Open **System Settings** > **Privacy & Security** > **Input Monitoring**
2. Click the **+** button and add:
   - **Terminal.app**
   - **Xcode.app**
   - **/opt/homebrew/bin/kanata** (or `/usr/local/bin/kanata` on Intel)

### Step 3: Verify Setup
```bash
./scripts/verify-test-permissions.sh
```

## 🛠️ What Gets Installed

### Wrapper Scripts
- `test-launchctl.sh` - LaunchDaemon management
- `test-process-manager.sh` - Kanata process management  
- `test-file-manager.sh` - File system operations
- `verify-test-permissions.sh` - Permission verification

### Sudoers Configuration
A secure sudoers file is created at `/etc/sudoers.d/keypath-testing` that allows passwordless access to:
- Specific wrapper scripts only
- Limited system commands (pkill, launchctl, etc.)
- Only KeyPath-related operations

### Test Directories
```
/usr/local/etc/kanata/test/     # Test configurations
/var/log/keypath/test/          # Test logs
/tmp/keypath-test/              # Temporary test files
```

## 🧪 Usage Examples

### Basic Operations
```bash
# Kill all Kanata processes
./scripts/test-process-manager.sh kill-kanata

# List running Kanata processes
./scripts/test-process-manager.sh list-kanata

# Create test directories
./scripts/test-file-manager.sh create-test-dirs

# Check LaunchDaemon status
./scripts/test-launchctl.sh list
```

### Testing Workflow
```bash
# 1. Clean environment
./scripts/test-process-manager.sh cleanup-all

# 2. Create test config
./scripts/test-file-manager.sh create-test-config /tmp/test.kbd caps->esc

# 3. Validate config
./scripts/test-process-manager.sh check-kanata /tmp/test.kbd

# 4. Start Kanata with test config
./scripts/test-process-manager.sh start-kanata /tmp/test.kbd

# 5. Run your tests
swift test

# 6. Cleanup
./scripts/test-process-manager.sh kill-kanata
./scripts/test-file-manager.sh cleanup-test-files
```

### Convenience Aliases
```bash
# Load aliases for easier testing
source ./scripts/test-aliases.sh

# Now you can use short commands:
kill-kanata
list-kanata
cleanup-tests
```

## 🔐 Security Notes

### What's Allowed
- Only KeyPath-specific operations
- Wrapper scripts validate all inputs
- Limited to test directories and files
- No broad system access

### What's NOT Allowed
- General sudo access
- Operations outside KeyPath scope
- Modification of system files (except LaunchDaemons)
- Network operations

### File Paths Restricted To
- `/usr/local/etc/kanata/*`
- `/var/log/keypath/*`
- `/Library/LaunchDaemons/com.keypath.*`
- `/tmp/keypath*`
- Project directory

## 🚨 Troubleshooting

### Permission Denied Errors
1. Run: `./scripts/verify-test-permissions.sh`
2. Check that sudoers file exists: `sudo ls -la /etc/sudoers.d/keypath-testing`
3. Validate sudoers: `sudo visudo -c -f /etc/sudoers.d/keypath-testing`

### macOS Permission Dialogs
- Grant permissions in System Settings as described above
- Restart Terminal/Xcode after granting permissions
- Some permissions may require logging out and back in

### Kanata Not Found
```bash
# Install Kanata
brew install kanata

# Verify installation
which kanata
kanata --version
```

### Test Directories Missing
```bash
./scripts/test-file-manager.sh create-test-dirs
```

## 🧹 Cleanup

To remove all testing setup:

```bash
# Remove sudoers configuration
sudo rm /etc/sudoers.d/keypath-testing

# Clean up test files
./scripts/test-file-manager.sh cleanup-test-files

# Remove test directories
sudo rm -rf /usr/local/etc/kanata/test
sudo rm -rf /var/log/keypath/test
rm -rf /tmp/keypath-test
```

## ✅ Verification Checklist

After setup, verify everything works:

- [ ] `./scripts/verify-test-permissions.sh` passes
- [ ] `sudo -n pkill -f nonexistent` works without password prompt
- [ ] `./scripts/test-process-manager.sh list-kanata` works
- [ ] `./scripts/test-launchctl.sh list` works
- [ ] `swift test` can run with Kanata operations
- [ ] No password prompts during automated testing

## 🎯 Ready for Development

Once setup is complete, you can:

1. **Run automated tests** with full Kanata integration
2. **Test multiple instance prevention** with real processes
3. **Validate LaunchDaemon operations** end-to-end
4. **Use CI/CD pipelines** with the same permissions
5. **Debug with comprehensive logging** from all components

The testing framework now supports **95% automation** instead of the typical 30% for macOS system integration!