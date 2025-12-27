import Carbon
import Combine
import Foundation
import KeyPathCore

/// Detects the current input source/IME state.
/// Primarily used to show Japanese input mode (hiragana/katakana/alphanumeric) in the overlay.
@MainActor
public final class InputSourceDetector: ObservableObject {
    public static let shared = InputSourceDetector()

    /// Current input source identifier (e.g., "com.apple.inputmethod.Kotoeri.Japanese")
    @Published public private(set) var inputSourceID: String = ""

    /// Whether a Japanese input method is currently active
    @Published public private(set) var isJapaneseInputActive: Bool = false

    /// The current Japanese input mode (if Japanese IME is active)
    @Published public private(set) var japaneseMode: JapaneseInputMode = .unknown

    /// Display character for the current input mode (あ, ア, A, or nil)
    public var modeIndicator: String? {
        guard isJapaneseInputActive else { return nil }
        return japaneseMode.indicator
    }

    /// Reference count for monitoring - allows multiple callers to share the observer
    private var monitoringCount = 0

    private init() {
        refresh()
    }

    /// Start monitoring input source changes.
    /// Uses reference counting - each call must be balanced with stopMonitoring().
    public func startMonitoring() {
        monitoringCount += 1
        guard monitoringCount == 1 else { return }

        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let detector = Unmanaged<InputSourceDetector>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in
                    detector.refresh()
                }
            },
            "AppleSelectedInputSourcesChangedNotification" as CFString,
            nil,
            .deliverImmediately
        )

        AppLogger.shared.log("🌐 [InputSourceDetector] Started monitoring input source changes")
    }

    /// Stop monitoring input source changes.
    /// Uses reference counting - only removes observer when all callers have stopped.
    public func stopMonitoring() {
        guard monitoringCount > 0 else { return }
        monitoringCount -= 1
        guard monitoringCount == 0 else { return }

        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, nil, nil)

        AppLogger.shared.log("🌐 [InputSourceDetector] Stopped monitoring input source changes")
    }

    /// Refresh the current input source state
    public func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            inputSourceID = ""
            isJapaneseInputActive = false
            japaneseMode = .unknown
            return
        }

        // Get input source ID
        let newID: String = if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        } else {
            ""
        }

        // Only log and update if changed
        guard newID != inputSourceID else { return }

        inputSourceID = newID

        // Detect if Japanese IME is active
        let isJapanese = newID.contains("Kotoeri") ||
            newID.contains("ATOK") ||
            newID.contains("Japanese") ||
            newID.contains("Mozc")

        isJapaneseInputActive = isJapanese

        if isJapanese {
            japaneseMode = JapaneseInputMode.detect(from: newID)
            AppLogger.shared.log("🇯🇵 [InputSourceDetector] Japanese mode: \(japaneseMode.rawValue) (\(japaneseMode.indicator ?? "?"))")
        } else {
            japaneseMode = .unknown
            AppLogger.shared.debug("🌐 [InputSourceDetector] Input source: \(newID)")
        }
    }
}

/// Japanese input mode
public enum JapaneseInputMode: String {
    case hiragana
    case katakana
    case alphanumeric
    case unknown

    /// Detect mode from input source ID
    public static func detect(from inputSourceID: String) -> JapaneseInputMode {
        // Check for specific mode indicators in the input source ID
        // Note: "RomajiTyping" is the input method variant, not the mode - ignore it
        let lowercased = inputSourceID.lowercased()

        if lowercased.contains("hiragana") {
            return .hiragana
        } else if lowercased.contains("katakana") {
            return .katakana
        } else if lowercased.contains("alphanumeric") {
            return .alphanumeric
        } else if lowercased.contains("japanese") || lowercased.contains("kotoeri") {
            // Default Japanese mode is typically hiragana
            return .hiragana
        }

        return .unknown
    }

    /// Visual indicator for the mode
    public var indicator: String? {
        switch self {
        case .hiragana:
            "あ"
        case .katakana:
            "ア"
        case .alphanumeric:
            "A"
        case .unknown:
            nil
        }
    }

    /// Localized display name
    public var displayName: String {
        switch self {
        case .hiragana:
            "Hiragana"
        case .katakana:
            "Katakana"
        case .alphanumeric:
            "Alphanumeric"
        case .unknown:
            "Unknown"
        }
    }
}
