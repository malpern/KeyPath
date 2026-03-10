import Foundation

public struct ExperimentalHostPassthruInputEvent: Equatable, Sendable {
    public let value: UInt64
    public let usagePage: UInt32
    public let usage: UInt32

    public init(value: UInt64, usagePage: UInt32, usage: UInt32) {
        self.value = value
        self.usagePage = usagePage
        self.usage = usage
    }
}

public enum ExperimentalHostPassthruInputMapper {
    private static let keyboardUsagePage: UInt32 = 0x07

    // Minimal US ANSI virtual-keycode -> HID usage mapping for experimental host capture.
    private static let keyboardUsages: [Int64: UInt32] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A, 6: 0x1D, 7: 0x1B,
        8: 0x06, 9: 0x19, 11: 0x05, 12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15,
        16: 0x1C, 17: 0x17, 18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23,
        23: 0x22, 24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D, 28: 0x25, 29: 0x27,
        30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13, 36: 0x28,
        37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31, 43: 0x2B,
        44: 0x2C, 45: 0x38, 46: 0x10, 47: 0x37, 48: 0x2B, 49: 0x2C, 50: 0x35,
        51: 0x2A, 53: 0x29, 55: 0xE3, 56: 0xE1, 57: 0x39, 58: 0xE2, 59: 0xE0,
        60: 0xE5, 61: 0xE6, 62: 0xE4, 63: 0x3F, 64: 0x53, 65: 0x54, 67: 0x55,
        69: 0x57, 71: 0x46, 72: 0x5F, 73: 0x60, 74: 0x5C, 75: 0x56, 76: 0x58,
        78: 0x57, 79: 0x5D, 80: 0x5E, 81: 0x59, 82: 0x62, 83: 0x63, 84: 0x64,
        85: 0x65, 86: 0x61, 87: 0x66, 88: 0x67, 89: 0x5A, 91: 0x5B, 92: 0x5C,
        96: 0x3E, 97: 0x3F, 98: 0x40, 99: 0x3D, 100: 0x41, 101: 0x42, 103: 0x44,
        105: 0x47, 106: 0x68, 107: 0x46, 109: 0x43, 111: 0x45, 113: 0x49,
        114: 0x4C, 115: 0x4A, 116: 0x4B, 117: 0x4C, 118: 0x3C, 119: 0x4D,
        120: 0x3B, 121: 0x4E, 122: 0x3A, 123: 0x50, 124: 0x4F, 125: 0x51,
        126: 0x52
    ]

    public static func eventForKeyCode(_ keyCode: Int64, isKeyDown: Bool) -> ExperimentalHostPassthruInputEvent? {
        guard let usage = keyboardUsages[keyCode] else {
            return nil
        }

        return ExperimentalHostPassthruInputEvent(
            value: isKeyDown ? 1 : 0,
            usagePage: keyboardUsagePage,
            usage: usage
        )
    }
}
