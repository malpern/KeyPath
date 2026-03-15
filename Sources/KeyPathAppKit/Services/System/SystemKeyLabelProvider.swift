import Carbon
import Foundation
import KeyPathCore
import Observation

/// Provides dynamic key labels from the current macOS input source using UCKeyTranslate.
/// Updates automatically when the input source changes (triggered by InputSourceDetector).
@MainActor
@Observable
public final class SystemKeyLabelProvider {
    public static let shared = SystemKeyLabelProvider()

    /// Base character per keyCode (no modifiers)
    public private(set) var currentLabels: [UInt16: String] = [:]

    /// Shifted character per keyCode
    public private(set) var currentShiftLabels: [UInt16: String] = [:]

    /// Display name of the current input source (e.g., "French", "German", "U.S.")
    public private(set) var inputSourceName: String = ""

    /// Testable label provider (defaults to production UCKeyTranslate wrapper)
    @ObservationIgnored var labelProvider: KeyLabelQuerying = UCKeyTranslateLabelProvider()

    private init() {
        refresh()
    }

    /// Re-query labels from the current input source.
    /// Called by InputSourceDetector on input source change.
    public func refresh() {
        // Get input source name
        inputSourceName = Self.currentInputSourceName()

        // Query labels for keyCodes 0–127
        let keyCodes = (0 ... 127).map { UInt16($0) }
        let results = labelProvider.labels(for: keyCodes)

        var base: [UInt16: String] = [:]
        var shifted: [UInt16: String] = [:]

        for (keyCode, pair) in results {
            if !pair.base.isEmpty {
                base[keyCode] = pair.base
            }
            if !pair.shifted.isEmpty {
                shifted[keyCode] = pair.shifted
            }
        }

        currentLabels = base
        currentShiftLabels = shifted

        AppLogger.shared.debug("🌐 [SystemKeyLabelProvider] Refreshed \(base.count) labels for '\(inputSourceName)'")
    }

    /// Get the display name of the current keyboard input source
    private static func currentInputSourceName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        return ""
    }
}

// MARK: - Production UCKeyTranslate Implementation

/// Production implementation that queries macOS UCKeyTranslate for key labels.
struct UCKeyTranslateLabelProvider: KeyLabelQuerying, Sendable {
    func labels(for keyCodes: [UInt16]) -> [UInt16: (base: String, shifted: String)] {
        // Get keyboard layout data from current input source
        guard let layoutData = Self.currentLayoutData() else {
            return [:]
        }

        let keyboardLayout = unsafeBitCast(
            CFDataGetBytePtr(layoutData),
            to: UnsafePointer<UCKeyboardLayout>.self
        )

        var results: [UInt16: (base: String, shifted: String)] = [:]

        for keyCode in keyCodes {
            // Skip modifier-only keyCodes — these return empty from UCKeyTranslate
            // and should keep their PhysicalKey.label symbols (⇧, ⌘, ⌥, ⌃)
            if Self.modifierKeyCodes.contains(keyCode) {
                continue
            }

            let base = Self.translate(
                keyCode: keyCode,
                modifiers: 0,
                layout: keyboardLayout
            )
            let shifted = Self.translate(
                keyCode: keyCode,
                modifiers: UInt32(Self.shiftKey >> 8),
                layout: keyboardLayout
            )

            if !base.isEmpty || !shifted.isEmpty {
                // Uppercase single-letter results for display consistency
                let displayBase = base.count == 1 ? base.uppercased() : base
                let displayShifted = shifted.count == 1 ? shifted.uppercased() : shifted
                results[keyCode] = (base: displayBase, shifted: displayShifted)
            }
        }

        return results
    }

    /// Modifier-only keyCodes that UCKeyTranslate returns empty for
    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63 // rcmd, lcmd, lshift, capslock, lopt, lctrl, rshift, ropt, rctrl, fn
    ]

    /// Shift key modifier flag for UCKeyTranslate
    private static let shiftKey: UInt32 = 0x0200 // kCGEventFlagMaskShift >> 16

    /// Get the UCKeyboardLayout data from the current input source
    private static func currentLayoutData() -> CFData? {
        // Try current keyboard input source first
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        {
            return Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        }

        // Fallback for IMEs (Japanese, Chinese, Korean) — get underlying physical layout
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        {
            return Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        }

        return nil
    }

    /// Translate a single keyCode to its character using UCKeyTranslate
    private static func translate(
        keyCode: UInt16,
        modifiers: UInt32,
        layout: UnsafePointer<UCKeyboardLayout>
    ) -> String {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else {
            return ""
        }

        let result = String(utf16CodeUnits: chars, count: length)

        // Filter out control characters and non-printable results
        if result.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
            return ""
        }

        return result
    }
}
