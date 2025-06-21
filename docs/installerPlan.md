# KeyPath Kanata Installation Plan

## Overview
Create a seamless installation and service management system for Kanata that works for non-technical macOS users without requiring Homebrew or manual terminal setup.

## Key Challenges & Resolutions

1.  **Virtual Keyboard Driver Dependency**: The plan's biggest risk is managing the `Karabiner-DriverKit-VirtualHIDDevice`. This is a system extension requiring a complex, multi-step manual user approval process that cannot be automated.
    *   **Resolution**: We will bundle the driver but must create a dedicated, multi-step UI guide to walk the user through the macOS System Settings approval flow. We cannot achieve a "one-click" install for this component.

2.  **Service Architecture (`LaunchDaemon` vs. `LaunchAgent`)**: The initial plan proposed a `LaunchDaemon`, which runs as root and is system-global. A keyboard remapper is user-specific.
    *   **Resolution**: The architecture will be changed to use a `LaunchAgent`, which runs as the logged-in user. This is more secure, simpler, and correctly aligns with the tool's purpose, giving it natural access to the user's configuration files without permission issues.

3.  **Privileged Helper Tool Security**: The `SMJobBless` helper tool will run as root, making it a security-sensitive component.
    *   **Resolution**: The helper's scope will be strictly limited to installing, starting, and stopping the `LaunchAgent`. All communication will occur over a minimal, hardened XPC interface, and the main app will validate the helper's code signature before interacting with it.

4.  **Reliable Window Presentation from Menu Bar**: Guiding the user requires opening System Settings panes and ensuring they appear in the foreground. As highlighted in [this article](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items), menu bar apps cannot do this reliably without special workarounds.
    *   **Resolution**: We will implement the robust strategy of temporarily changing the app's activation policy from `.accessory` (menu bar only) to `.regular` (shows Dock icon) before programmatically opening a System Settings pane. This ensures the window gains focus. The policy will be reverted once the user flow is complete.

## Current State
- KeyPath generates Kanata rules but requires manual Kanata setup
- Current implementation assumes Homebrew is available
- Users must manually configure permissions and services
- Poor user experience for non-technical users

## Target User Experience
1.  User clicks "Install Kanata & Driver" in KeyPath onboarding.
2.  The app guides the user through two distinct manual approval steps:
    *   One administrator password prompt to authorize the service installation.
    *   A step-by-step guide to approve the virtual keyboard driver and Input Monitoring in System Settings.
3.  The background service runs seamlessly post-installation.
4.  No terminal or command line knowledge is required.

## Technical Implementation Plan

### Phase 1: Pre-flight Checks & Direct Binary Installation
- **Download kanata binary** directly from GitHub releases API and bundle it within `KeyPath.app/Contents/Resources/`.
- **Bundle the Karabiner VirtualHIDDevice** system extension.
- **Develop a robust UI guide** for the manual driver and permission approval process.
- **Create default config structure** at `~/.config/kanata/`.

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

#### Refined Permission & Driver Installation Flow

This flow combines the `SystemExtensions` framework with robust UI/UX best practices to guide the user through the complex, manual approval process.

1.  **Bundle the Driver**: The `Karabiner-DriverKit-VirtualHIDDevice.dext` must be located within the app bundle at `Contents/Library/SystemExtensions/`.
2.  **Check Status First**: On initiating the flow, the app will programmatically check the driver's status using the `SystemExtensions` framework.
    *   If **active**, the installation step is skipped.
    *   If **installed but pending approval**, the UI will jump directly to the guidance step.
    *   If **not installed**, proceed to the next step.
3.  **Request Activation**:
    *   The app will make an `OSSystemExtensionRequest` to ask macOS to install the bundled driver.
    *   Crucially, before making the request, the app will temporarily change its activation policy to `.regular` to ensure all system dialogs appear in the foreground.
4.  **Guide User Through Manual Approval**:
    *   The UI must now display a clear, visual guide (using screenshots or animations) showing the user exactly where to click in `System Settings > Privacy & Security` to find and approve the request.
    *   The app will listen for the result of the activation request and must handle all possible outcomes, including: `success`, `failure`, `reboot required`, and `pending user action`.
5.  **Confirm and Cleanup**:
    *   Upon detecting a successful activation, the UI will update to a success state.
    *   The app's activation policy will be reverted to `.accessory` to hide the Dock icon and restore normal behavior.

### Phase 4: Configuration Management
- **Real-time Config Updates**: Seamlessly update kanata.kbd when rules change
- **Config Validation**: Validate before applying to prevent breaking changes
- **Backup/Restore**: Automatic config backups before changes
- **Service Reloading**: Hot reload configs without full restart

## Implementation Components

### 1. Privileged Helper Tool
- The helper tool must be minimal and hardened.
- Exposes a narrow, secure XPC interface for service management only.
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

### 2. LaunchAgent Configuration (Corrected)
- The service will run as a `LaunchAgent` in the user context, not a system-wide `LaunchDaemon`. This is more secure and appropriate.
```xml
<!-- /Library/LaunchAgents/com.keypath.kanata.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/KeyPath.app/Contents/Resources/kanata</string>
        <string>--cfg</string>
        <string>~/.config/kanata/kanata.kbd</string>
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
- **Admin privileges** (user must provide password once)
- **Input Monitoring & System Extension approval** (user must approve manually via UI)
- **Bundled Karabiner VirtualHIDDevice** for keyboard interception

### Bundled Components
- **Kanata binary** (self-contained in app bundle)
- **Default configuration templates**
- **Privileged helper tool executable**
- **Service management UI components**

## Security Considerations

### Principle of Least Privilege
- Helper tool only has permissions needed for installing and managing the LaunchAgent.
- Kanata LaunchAgent runs with user-level privileges.
- Config files are owned and managed by the user.
- The app must validate the helper tool's signature before connecting.

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

## Timeline Estimate (Revised)
- **Phase 1 (Installation & Driver UI)**: 5-6 days
- **Phase 2 (Service Management)**: 4-5 days
- **Phase 3 (Permission Management)**: 2-3 days
- **Phase 4 (Configuration Management)**: 2-3 days
- **Testing and Polish**: 4-5 days
- **Total**: ~3-4 weeks

## Automated vs. Manual Tasks

This section clarifies the division of labor between automated development (tasks an AI assistant can perform) and the manual actions required by the end-user during installation.

### 🤖 Automated Development (AI-Assisted)
- **Code Generation**:
    - Write the Swift code for the `KanataServiceManager` to handle XPC communication and calls to `ServiceManagement`.
    - Generate the boilerplate for the privileged helper tool.
    - Create the `LaunchAgent` and helper tool `.plist` files.
- **Binary & Asset Management**:
    - Write scripts/code to download the Kanata binary and bundle it within the app.
    - Write code to create the `~/.config/kanata` directory and place a default configuration file.
- **Configuration Logic**:
    - Implement the file I/O for reading, writing, and backing up `kanata.kbd` files.
    - Write the logic to trigger a `launchctl` reload of the service when the configuration changes.

### 🧑‍💻 Manual User Actions (During Installation)
- **Administrator Authentication**: The user **must** manually enter their password when prompted by macOS to authorize the installation of the privileged helper tool. This is a non-bypassable system security feature.
- **System Settings Approval**: The user **must** manually navigate System Settings to grant two separate permissions:
    1.  **System Extension**: Approve the `Karabiner-DriverKit-VirtualHIDDevice`. This involves clicking "Allow" and may require a system restart.
    2.  **Input Monitoring**: Add the `KeyPath` application to the approved list to allow it to capture keyboard events.

## Future Enhancements
- **Automatic updates** for Kanata binary
- **Advanced service monitoring** and diagnostics
- **Multi-user support** for shared machines
- **Integration with other keyboard tools** (Karabiner, etc.)
- **Cloud backup/sync** for configurations