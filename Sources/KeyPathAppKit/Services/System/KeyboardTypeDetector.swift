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

    /// Detects the current keyboard type from the I/O Registry.
    /// Returns the keyboard type of the first keyboard found (typically the built-in one).
    /// Reads registry properties only, so it needs no privacy permission.
    static func detect() -> KeyboardType {
        let keyboards = RegistryKeyboards.current()
        guard !keyboards.isEmpty else {
            AppLogger.shared.log("⌨️ [KeyboardTypeDetector] No keyboard devices found")
            return .unknown
        }

        // Prefer an Apple keyboard (most reliable for laptop users), then any keyboard with type info.
        var appleKeyboardType: KeyboardType?
        var anyKeyboardType: KeyboardType?
        for keyboard in keyboards {
            guard let typeValue = keyboard.keyboardType else { continue }
            let type = keyboardTypeFromIOKit(typeValue)
            guard type != .unknown else { continue }
            if keyboard.vendorID == 0x05AC || keyboard.productName.lowercased().contains("apple internal") {
                appleKeyboardType = type
                break
            }
            anyKeyboardType = anyKeyboardType ?? type
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
