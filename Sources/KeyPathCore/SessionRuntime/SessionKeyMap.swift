import Foundation

/// Physical macOS virtual key codes to USB keyboard usages, independent of the
/// active character layout. Fn and most consumer keys remain unmapped: session
/// events cannot represent every HID key or identify its source device. The
/// media keys macOS carries as system-defined events are the exception, as
/// outputs (`mediaKeyType(forUsage:)`).
public enum SessionKeyMap {
    public static let keyboardPage: UInt32 = 7
    public static let consumerPage: UInt32 = 0x0C

    /// Consumer-page usages the worker posts as `NSEvent` system-defined
    /// (subtype 8) media events, by their `NX_KEYTYPE_*` code. The bridge's
    /// output rule accepts exactly these (`CONSUMER_OUTPUT_CODES` in
    /// session_config.rs); see docs/architecture/driverless-media-keys.md §2.
    public static let consumerUsageToMediaKeyType: [UInt32: Int] = [
        0xE9: 0, // volume up      NX_KEYTYPE_SOUND_UP
        0xEA: 1, // volume down    NX_KEYTYPE_SOUND_DOWN
        0x6F: 2, // brightness up  NX_KEYTYPE_BRIGHTNESS_UP
        0x70: 3, // brightness down
        0xE2: 7, // mute           NX_KEYTYPE_MUTE
        0xCD: 16, // play/pause    NX_KEYTYPE_PLAY
        0xB5: 17, // next          NX_KEYTYPE_NEXT
        0xB6: 18, // previous      NX_KEYTYPE_PREVIOUS
        0xB3: 19, // fast-forward  NX_KEYTYPE_FAST
        0xB4: 20 // rewind         NX_KEYTYPE_REWIND
    ]

    public static func mediaKeyType(forUsage usage: UInt32) -> Int? {
        consumerUsageToMediaKeyType[usage]
    }

    private static let mediaKeyTypeToConsumerUsage = Dictionary(
        uniqueKeysWithValues: consumerUsageToMediaKeyType.map { ($0.value, $0.key) }
    )

    /// The consumer-page input a macOS system-defined media event carries, as
    /// Kanata's (usage, value): 1 down, 0 up, 2 a hardware repeat. nil for any
    /// other subtype or a key outside the table. data1 holds the NX key type in
    /// bits 16–23, 0xA (down) or 0xB (up) in bits 8–15, and the repeat flag in
    /// bit 0 (docs/architecture/driverless-media-keys.md §1).
    public static func mediaInput(subtype: Int16, data1: Int) -> (usage: UInt32, value: UInt64)? {
        guard subtype == 8, let usage = mediaKeyTypeToConsumerUsage[(data1 >> 16) & 0xFF] else { return nil }
        switch (data1 >> 8) & 0xFF {
        case 0xA: return (usage, data1 & 1 == 1 ? 2 : 1)
        case 0xB: return (usage, 0)
        default: return nil
        }
    }

    public static let keyCodeToUsage: [UInt16: UInt32] = [
        0: 4, 1: 22, 2: 7, 3: 9, 4: 11, 5: 10,
        6: 29, 7: 27, 8: 6, 9: 25, 10: 100, 11: 5,
        12: 20, 13: 26, 14: 8, 15: 21, 16: 28, 17: 23,
        18: 30, 19: 31, 20: 32, 21: 33, 22: 35, 23: 34,
        24: 46, 25: 38, 26: 36, 27: 45, 28: 37, 29: 39,
        30: 48, 31: 18, 32: 24, 33: 47, 34: 12, 35: 19,
        36: 40, 37: 15, 38: 13, 39: 52, 40: 14, 41: 51,
        42: 49, 43: 54, 44: 56, 45: 17, 46: 16, 47: 55,
        48: 43, 49: 44, 50: 53, 51: 42, 53: 41,
        54: 231, 55: 227, 56: 225, 57: 57, 58: 226,
        59: 224, 60: 229, 61: 230, 62: 228,
        64: 108, 65: 99, 67: 85, 69: 87, 71: 83,
        75: 84, 76: 88, 78: 86, 79: 109, 80: 110, 81: 103,
        82: 98, 83: 89, 84: 90, 85: 91, 86: 92, 87: 93,
        88: 94, 89: 95, 90: 111, 91: 96, 92: 97,
        93: 137, 94: 135, 95: 133, 96: 62, 97: 63,
        98: 64, 99: 60, 100: 65, 101: 66, 102: 145,
        103: 68, 104: 144, 105: 104, 106: 107, 107: 105,
        109: 67, 111: 69, 113: 106, 114: 73, 115: 74,
        116: 75, 117: 76, 118: 61, 119: 77, 120: 59,
        121: 78, 122: 58, 123: 80, 124: 79, 125: 81, 126: 82
    ]

    private static let usageToKeyCode = Dictionary(
        uniqueKeysWithValues: keyCodeToUsage.map { ($0.value, $0.key) }
    )

    public static func keyCode(forUsage usage: UInt32) -> UInt16? {
        usageToKeyCode[usage]
    }

    public static func isModifier(_ usage: UInt32) -> Bool {
        (224 ... 231).contains(usage)
    }

    /// CGEvent modifier flags: device-specific bits distinguish a left release
    /// while its right counterpart stays held. Aggregate bits accompany them.
    public static func modifierFlags(for usage: UInt32) -> UInt64 {
        switch usage {
        case 224: (1 << 18) | 0x1
        case 225: (1 << 17) | 0x2
        case 226: (1 << 19) | 0x20
        case 227: (1 << 20) | 0x8
        case 228: (1 << 18) | 0x2000
        case 229: (1 << 17) | 0x4
        case 230: (1 << 19) | 0x40
        case 231: (1 << 20) | 0x10
        default: 0
        }
    }

    public static func deviceModifierFlag(for usage: UInt32) -> UInt64 {
        modifierFlags(for: usage) & 0xFFFF
    }
}
