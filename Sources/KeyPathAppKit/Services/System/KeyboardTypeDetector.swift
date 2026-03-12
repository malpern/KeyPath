import Foundation
import IOKit
import IOKit.hid
import KeyPathCore

/// Detects the physical keyboard type (ANSI, ISO, JIS) from IOKit.
/// Used to set smart defaults for the overlay keyboard layout on first launch.
enum KeyboardTypeDetector {
    /// Physical keyboard type as reported by macOS
    enum KeyboardType: String {
        case ansi = "ANSI"
        case iso = "ISO"
        case jis = "JIS"
        case unknown = "Unknown"
    }

    /// Detects the current keyboard type from IOKit HID.
    /// Returns the keyboard type of the first keyboard found (typically the built-in one).
    static func detect() -> KeyboardType {
        // Create HID manager to find keyboard devices
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match keyboard devices
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        // Get all matching devices
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            AppLogger.shared.log("⌨️ [KeyboardTypeDetector] No keyboard devices found")
            return .unknown
        }

        // Look for Apple internal keyboard first (most reliable for laptop users)
        // Then fall back to any keyboard with type info
        var appleKeyboardType: KeyboardType?
        var anyKeyboardType: KeyboardType?

        for device in devices {
            // Get vendor ID to check if it's Apple
            let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let isApple = vendorID == 0x05AC

            // Get keyboard type property
            if let typeValue = IOHIDDeviceGetProperty(device, "KeyboardType" as CFString) as? Int {
                let type = keyboardTypeFromIOKit(typeValue)

                if isApple, type != .unknown {
                    appleKeyboardType = type
                    break // Found Apple keyboard with valid type, use it
                } else if type != .unknown {
                    anyKeyboardType = type
                }
            }
        }

        let result = appleKeyboardType ?? anyKeyboardType ?? .unknown
        AppLogger.shared.log("⌨️ [KeyboardTypeDetector] Detected keyboard type: \(result.rawValue)")
        return result
    }

    /// Maps IOKit keyboard type constants to our enum.
    /// See: IOHIDKeyboardTypes.h for the full list
    private static func keyboardTypeFromIOKit(_ type: Int) -> KeyboardType {
        // From IOKit/hid/IOHIDKeyboardTypes.h:
        // - ANSI types: 4, 5, 40, 41 (various ANSI keyboards)
        // - ISO types: 6, 7, 42, 43
        // - JIS types: 8, 9, 44, 45
        switch type {
        case 4, 5, 40, 41:
            .ansi
        case 6, 7, 42, 43:
            .iso
        case 8, 9, 44, 45:
            .jis
        default:
            // Type 0-3 are generic/unknown, others are less common
            type > 0 ? .ansi : .unknown // Default to ANSI for unknown positive types
        }
    }

    /// Returns the recommended PhysicalLayout ID for the detected keyboard type.
    static func recommendedLayoutId() -> String {
        switch detect() {
        case .jis:
            "macbook-jis"
        case .iso:
            "macbook-iso"
        case .ansi, .unknown:
            LayoutPreferences.defaultLayoutId
        }
    }
}
