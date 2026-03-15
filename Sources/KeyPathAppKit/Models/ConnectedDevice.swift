import Foundation

enum DeviceDisplayNameFormatter {
    static func format(_ productKey: String) -> String {
        productKey
            .replacingOccurrences(of: " / Trackpad", with: "")
            .replacingOccurrences(of: "/ Trackpad", with: "")
            .replacingOccurrences(of: "/Trackpad", with: "")
            .replacingOccurrences(of: "Karabiner-DriverKit-VirtualHIDDevice-", with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
    }
}

/// A physical keyboard device detected by Kanata's `--list` command.
struct ConnectedDevice: Codable, Identifiable, Hashable, Sendable {
    /// Stable-ish identifier from kanata output, e.g. "0x1234ABCD"
    let hash: String
    /// USB Vendor ID
    let vendorID: Int
    /// USB Product ID
    let productID: Int
    /// IOKit product name, e.g. "Apple Internal Keyboard / Trackpad"
    let productKey: String
    /// True if the product key indicates a VirtualHID device
    let isVirtualHID: Bool

    var id: String {
        hash
    }

    /// Cleaned-up product name for display in the UI.
    /// Falls back to the device hash when the product key is empty.
    var displayName: String {
        let formatted = DeviceDisplayNameFormatter.format(productKey)
        return formatted.isEmpty ? "Device \(hash.suffix(8))" : formatted
    }

    /// Formatted vendor:product hex string, e.g. "05ac:0342"
    var vendorProductHex: String {
        String(format: "%04x:%04x", vendorID, productID)
    }

    /// True if this device appears to be a trackpad with no keyboard functionality.
    /// These are filtered out of the keyboard picker since they can't produce key events.
    var isTrackpadOnly: Bool {
        let lower = productKey.lowercased()
        return lower.contains("trackpad") && !lower.contains("keyboard")
    }

    /// SF Symbol name for this device type.
    /// Apple internal keyboards (vendor 0x05AC) use `laptopcomputer`;
    /// all external keyboards use `keyboard`.
    var sfSymbolName: String {
        vendorID == 0x05AC ? "laptopcomputer" : "keyboard"
    }
}
