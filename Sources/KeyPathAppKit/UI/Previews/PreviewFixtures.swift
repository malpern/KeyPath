#if DEBUG
    import Foundation
    import KeyPathCore
    import KeyPathWizardCore

    /// Shared deterministic fixtures used by SwiftUI previews.
    enum PreviewFixtures {
        static let customRulesPopulated: [CustomRule] = [
            CustomRule(title: "Home Row Down", input: "j", output: "down", isEnabled: true, notes: "Vim navigation"),
            CustomRule(title: "Home Row Up", input: "k", output: "up", isEnabled: true),
            CustomRule(title: "Legacy Escape", input: "caps", output: "esc", isEnabled: false),
        ]

        /// Rules with device overrides for previewing the per-device grouping.
        static let customRulesWithDeviceOverrides: [CustomRule] = customRulesPopulated + [
            CustomRule(
                title: "Kinesis: Caps → Ctrl",
                input: "caps",
                output: "caps",
                isEnabled: true,
                deviceOverrides: [DeviceKeyOverride(deviceHash: "0xDEADBEEF", output: "lctl")]
            ),
            CustomRule(
                title: "Kinesis: Tab → Hyper",
                input: "tab",
                output: "tab",
                isEnabled: true,
                deviceOverrides: [DeviceKeyOverride(deviceHash: "0xDEADBEEF", output: "lmet")]
            ),
            CustomRule(
                title: "Moonlander: A → Ctrl",
                input: "a",
                output: "a",
                isEnabled: true,
                deviceOverrides: [DeviceKeyOverride(deviceHash: "0xCAFEBABE", output: "lctl")]
            ),
        ]

        static let appKeymapsPopulated: [AppKeymap] = [
            AppKeymap(
                mapping: AppKeyMapping(bundleIdentifier: "com.apple.Safari", displayName: "Safari", virtualKeyName: "vk_safari"),
                overrides: [
                    AppKeyOverride(inputKey: "j", outputAction: "down"),
                    AppKeyOverride(inputKey: "k", outputAction: "up")
                ]
            ),
            AppKeymap(
                mapping: AppKeyMapping(bundleIdentifier: "com.openai.chat", displayName: "ChatGPT", virtualKeyName: "vk_chatgpt"),
                overrides: [
                    AppKeyOverride(inputKey: "h", outputAction: "left")
                ]
            )
        ]

        // MARK: - Connected Devices (fake data for UI development)
        // TODO: Remove once macOS multi-device support lands upstream:
        //   - psych3r/driverkit#15 (macOS multi-device DriverKit support)
        //   - jtroo/kanata#1974 (Kanata device-switch support)
        // Tracked by: https://github.com/malpern/KeyPath/issues/254

        static let connectedDevices: [ConnectedDevice] = [
            ConnectedDevice(
                hash: "0xABCD1234",
                vendorID: 0x05AC,
                productID: 0x0342,
                productKey: "Apple Internal Keyboard / Trackpad",
                isVirtualHID: false
            ),
            ConnectedDevice(
                hash: "0xDEADBEEF",
                vendorID: 0x29EA,
                productID: 0x0041,
                productKey: "Kinesis Advantage360 Pro",
                isVirtualHID: false
            ),
            ConnectedDevice(
                hash: "0xCAFEBABE",
                vendorID: 0x1209,
                productID: 0x4173,
                productKey: "ZSA Moonlander Mark I",
                isVirtualHID: false
            ),
            ConnectedDevice(
                hash: "0x00FF00FF",
                vendorID: 0x1532,
                productID: 0x0084,
                productKey: "Karabiner-DriverKit-VirtualHIDDevice-VirtualHIDKeyboard",
                isVirtualHID: true
            ),
        ]

        /// Physical devices only (excludes VirtualHID). Convenience for UI previews.
        static var physicalDevices: [ConnectedDevice] {
            connectedDevices.filter { !$0.isVirtualHID }
        }

        /// Prime the shared device cache with fake devices for previews.
        /// Call this in preview `.task` or `.onAppear` blocks.
        static func primeDeviceCache() {
            DeviceSelectionCache.shared.updateConnectedDevices(connectedDevices)
        }

        static var noIssues: [WizardIssue] {
            []
        }

        static func permissionIssue(_ permission: PermissionRequirement, title: String, description: String) -> WizardIssue {
            WizardIssue(
                identifier: .permission(permission),
                severity: .critical,
                category: .permissions,
                title: title,
                description: description,
                autoFixAction: nil,
                userAction: "Grant permission in System Settings"
            )
        }
    }
#endif
