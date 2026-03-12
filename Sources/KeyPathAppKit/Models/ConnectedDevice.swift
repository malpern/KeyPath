import Foundation

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
    var displayName: String {
        productKey
            .replacingOccurrences(of: " / Trackpad", with: "")
            .replacingOccurrences(of: "Karabiner-DriverKit-VirtualHIDDevice-", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Formatted vendor:product hex string, e.g. "05ac:0342"
    var vendorProductHex: String {
        String(format: "%04x:%04x", vendorID, productID)
    }
}
