import Foundation
import IOKit
import IOKit.hid

/// Reads connected keyboards from the I/O Registry.
///
/// Identifying a keyboard needs only its registry properties (name, vendor and
/// product IDs), which macOS publishes to every process. Opening the device
/// through `IOHIDManager` is what requires Input Monitoring, so this never opens
/// one and needs no privacy permission.
enum RegistryKeyboards {
    /// A keyboard's identity as read from its registry entry.
    struct Entry: Sendable, Equatable {
        let registryID: UInt64
        let vendorID: Int
        let productID: Int
        let productName: String
        let keyboardType: Int?
    }

    /// Generic Desktop (0x01) / Keyboard (0x06).
    private static let keyboardUsagePage = 1
    private static let keyboardUsage = 6

    /// Matching dictionary for every HID device; keyboards are filtered in code
    /// because a device lists its usages in `DeviceUsagePairs`, which a
    /// matching dictionary cannot test for membership.
    static func hidDeviceMatching() -> CFMutableDictionary {
        IOServiceMatching("IOHIDDevice")
    }

    /// Every keyboard currently in the registry.
    static func current() -> [Entry] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, hidDeviceMatching(), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        return drain(iterator)
    }

    /// Reads and releases every service in the iterator, keeping keyboards.
    static func drain(_ iterator: io_iterator_t) -> [Entry] {
        var entries: [Entry] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let entry = entry(for: service) { entries.append(entry) }
            IOObjectRelease(service)
        }
        return entries
    }

    /// Registry IDs of the services in the iterator, releasing each.
    static func drainIDs(_ iterator: io_iterator_t) -> [UInt64] {
        var ids: [UInt64] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { ids.append(id) }
            IOObjectRelease(service)
        }
        return ids
    }

    static func entry(for service: io_service_t) -> Entry? {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }
        let pairs = (property(kIOHIDDeviceUsagePairsKey) as? [[String: Any]]) ?? []
        let usages = pairs.map {
            ($0[kIOHIDDeviceUsagePageKey] as? Int ?? -1, $0[kIOHIDDeviceUsageKey] as? Int ?? -1)
        }
        let primary = (property(kIOHIDPrimaryUsagePageKey) as? Int ?? -1, property(kIOHIDPrimaryUsageKey) as? Int ?? -1)
        guard isKeyboard(usages: usages, primary: primary) else { return nil }

        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &registryID)
        let keyboardType = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "KeyboardType" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) as? Int
        return Entry(
            registryID: registryID,
            vendorID: property(kIOHIDVendorIDKey) as? Int ?? 0,
            productID: property(kIOHIDProductIDKey) as? Int ?? 0,
            productName: property(kIOHIDProductKey) as? String ?? "Unknown Keyboard",
            keyboardType: keyboardType
        )
    }

    static func isKeyboard(usages: [(Int, Int)], primary: (Int, Int)) -> Bool {
        let keyboard = (keyboardUsagePage, keyboardUsage)
        return usages.contains { $0 == keyboard } || primary == keyboard
    }
}
