# KeyPath Kanata Installation Plan

## Overview
Create a seamless installation and service management system for Kanata that works for non-technical macOS users without requiring Homebrew or manual terminal setup.

## Current State
- KeyPath generates Kanata rules but requires manual Kanata setup
- Current implementation assumes Homebrew is available
- Users must manually configure permissions and services
- Poor user experience for non-technical users

## Target User Experience
1. User clicks "Install Kanata" in KeyPath onboarding
2. Single admin password prompt for all installation steps
3. Automatic permission request guidance with clear UI
4. Background service runs seamlessly
5. No terminal or command line knowledge required

## Technical Implementation Plan

### Phase 1: Direct Binary Installation
- **Download kanata binary** directly from GitHub releases API
- **Install to app bundle** or `/usr/local/bin/` with proper permissions
- **Include Karabiner-DriverKit-VirtualHIDDevice** or bundle equivalent functionality
- **Create default config structure** at `~/.config/kanata/`

### Phase 2: Service Management Framework
```swift
// Use Swift ServiceManagement + AuthorizationServices
import ServiceManagement
import AuthorizationServices

class KanataServiceManager {
    // Install privileged helper tool using SMJobBless
    func installService() -> Result<Bool, Error>
    
    // Manage launchd daemon lifecycle
    func startService() -> Result<Bool, Error>
    func stopService() -> Result<Bool, Error>
    func restartService() -> Result<Bool, Error>
    
    // Monitor service health
    func serviceStatus() -> ServiceStatus
    func watchServiceHealth(callback: @escaping (ServiceStatus) -> Void)
}
```

### Phase 3: Permission Management
- **Input Monitoring Detection**: Check current permission status
- **Guided Permission Flow**: Step-by-step UI for enabling permissions
- **Permission Validation**: Verify permissions are working correctly
- **Fallback Handling**: Clear error messages and recovery options

### Phase 4: Configuration Management
- **Real-time Config Updates**: Seamlessly update kanata.kbd when rules change
- **Config Validation**: Validate before applying to prevent breaking changes
- **Backup/Restore**: Automatic config backups before changes
- **Service Reloading**: Hot reload configs without full restart

## Implementation Components

### 1. Privileged Helper Tool
```xml
<!-- /Library/PrivilegedHelperTools/com.keypath.kanata-helper -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata-helper</string>
    <key>MachServices</key>
    <dict>
        <key>com.keypath.kanata-helper</key>
        <true/>
    </dict>
</dict>
</plist>
```

### 2. LaunchDaemon Configuration
```xml
<!-- /Library/LaunchDaemons/com.keypath.kanata.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>/Users/{USERNAME}/.config/kanata/kanata.kbd</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/kanata.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/kanata.out</string>
</dict>
</plist>
```

### 3. Authorization Rights
```swift
// Required authorization for service management
let authRight = "com.keypath.kanata-installer"
let authRights = AuthorizationRights(
    count: 1,
    items: &AuthorizationItem(
        name: authRight,
        valueLength: 0,
        value: nil,
        flags: 0
    )
)
```

## Dependencies and Requirements

### System Dependencies
- **macOS 11.0+** (Big Sur) for modern ServiceManagement APIs
- **Admin privileges** for initial installation only
- **Input Monitoring permission** (user must approve manually)
- **Karabiner VirtualHIDDevice** or equivalent for keyboard interception

### Bundled Components
- **Kanata binary** (downloaded or bundled)
- **Default configuration templates**
- **Privileged helper tool executable**
- **Service management UI components**

## Security Considerations

### Principle of Least Privilege
- Helper tool only has permissions needed for service management
- Kanata runs with minimal required privileges
- Config files owned by user, not root
- Service limited to keyboard remapping functionality

### Code Signing Requirements
- Main app must be signed and notarized
- Helper tool must be signed with same certificate
- Proper entitlements for ServiceManagement framework
- Secure installation and validation processes

## Fallback Strategies

### Manual Installation Option
- Clear instructions for manual Kanata setup
- Links to official installation guides
- Troubleshooting documentation
- Support for advanced users who prefer manual control

### Graceful Degradation
- App functions without Kanata (rule generation only)
- Clear status indicators for installation state
- Export functionality for manual application
- Integration with existing Kanata installations

## Testing Strategy

### Automated Testing
- Unit tests for service management logic
- Integration tests for permission flows
- Mock privileged operations for CI/CD
- Configuration validation testing

### Manual Testing Scenarios
- Fresh macOS installation (no Homebrew)
- Existing Kanata installation conflicts
- Permission denial scenarios
- Service failure and recovery
- Multiple user accounts

## Success Metrics
- **Installation Success Rate**: >95% on supported macOS versions
- **User Completion Rate**: >90% complete onboarding without support
- **Service Reliability**: >99.9% uptime for background service
- **Permission Success**: >90% users successfully enable Input Monitoring

## Timeline Estimate
- **Phase 1 (Direct Installation)**: 3-4 days
- **Phase 2 (Service Management)**: 4-5 days  
- **Phase 3 (Permission Management)**: 2-3 days
- **Phase 4 (Configuration Management)**: 2-3 days
- **Testing and Polish**: 3-4 days
- **Total**: ~2-3 weeks

## Future Enhancements
- **Automatic updates** for Kanata binary
- **Advanced service monitoring** and diagnostics
- **Multi-user support** for shared machines
- **Integration with other keyboard tools** (Karabiner, etc.)
- **Cloud backup/sync** for configurations