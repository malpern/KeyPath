import Foundation
import KeyPathCore
import Observation

/// Tracks recent keypresses from Kanata TCP events for debugging and visualization.
@Observable
@MainActor
final class RecentKeypressesService {
    static let shared = RecentKeypressesService()

    /// Maximum number of events to keep in history
    private let maxEvents = 100

    /// A single keypress event
    struct KeypressEvent: Identifiable {
        let id = UUID()
        let key: String
        let action: String // "press", "release", "repeat"
        let timestamp: Date
        let layer: String?
        let listenerSessionID: Int?
        let kanataTimestamp: UInt64?

        var displayKey: String {
            // Capitalize first letter for display
            key.prefix(1).uppercased() + key.dropFirst()
        }

        var isPress: Bool {
            action == "press"
        }

        var isRelease: Bool {
            action == "release"
        }

        var timeAgo: String {
            let seconds = Date().timeIntervalSince(timestamp)
            if seconds < 1 {
                return "now"
            } else if seconds < 60 {
                return "\(Int(seconds))s ago"
            } else {
                return "\(Int(seconds / 60))m ago"
            }
        }
    }

    /// Recent keypress events (newest first)
    private(set) var events: [KeypressEvent] = []

    /// Current layer name (for context)
    private(set) var currentLayer: String = "base"

    /// Whether recording is enabled
    var isRecording: Bool = true

    /// Tracks consecutive same-key presses for duplicate detection
    @ObservationIgnored private var consecutiveKeyCount: Int = 0
    @ObservationIgnored private var lastConsecutiveKey: String?
    @ObservationIgnored private var consecutiveKeyStartTime: Date?
    /// Stores timestamps of each consecutive press for detailed timing analysis
    @ObservationIgnored private var consecutivePressTimestamps: [Date] = []
    /// Tracks if we saw a release between presses (helps diagnose cause)
    @ObservationIgnored private var sawReleaseBetweenPresses: Bool = false
    @ObservationIgnored private var lastKeyAction: String?

    @ObservationIgnored private let observers = NotificationObserverManager()
    @ObservationIgnored private let notificationCenter: NotificationCenter

    private init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        setupObservers()
    }

    private func setupObservers() {
        // Listen for key input events
        observers.observe(.kanataKeyInput, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let key = userInfo?["key"] as? String
            let action = userInfo?["action"] as? String
            let metadata = KeypressObservationMetadata.from(userInfo: userInfo)
            Task { @MainActor [weak self] in
                guard let self, isRecording, let key, let action else { return }
                addEvent(key: key, action: action, metadata: metadata)
            }
        }

        // Listen for layer changes
        observers.observe(.kanataLayerChanged, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let layerName = userInfo?["layerName"] as? String
            Task { @MainActor [weak self] in
                guard let self, let layerName else { return }
                currentLayer = layerName
            }
        }
    }

    #if DEBUG
        static func makeTestInstance(notificationCenter: NotificationCenter = NotificationCenter()) -> RecentKeypressesService {
            RecentKeypressesService(notificationCenter: notificationCenter)
        }
    #endif

    private func addEvent(key: String, action: String, metadata: KeypressObservationMetadata = .init(listenerSessionID: nil, kanataTimestamp: nil, observedAt: nil)) {
        let event = KeypressEvent(
            key: key,
            action: action,
            timestamp: Date(),
            layer: currentLayer,
            listenerSessionID: metadata.listenerSessionID,
            kanataTimestamp: metadata.kanataTimestamp
        )

        // DEDUPLICATION: Check last 10 events for duplicate (key, action, layer) within window
        // This prevents TCP duplicates while allowing legitimate double letters like "tt" in "letter"
        let deduplicationWindow: TimeInterval = 0.1 // 100ms
        let now = event.timestamp

        if let duplicate = events.prefix(10).first(where: { recent in
            recent.key == event.key &&
                recent.action == event.action &&
                recent.layer == event.layer &&
                now.timeIntervalSince(recent.timestamp) < deduplicationWindow
        }) {
            let millisDiff = Int(now.timeIntervalSince(duplicate.timestamp) * 1000)
            AppLogger.shared.info("🚫 [Keypresses] Skipping duplicate: \(key) \(action) within \(millisDiff)ms")
            return
        }

        // DIAGNOSTIC: Track consecutive same-key presses to detect unwanted duplicates
        detectConsecutiveKeyPresses(key: key, action: action, timestamp: now, layer: currentLayer)

        events.insert(event, at: 0)

        // Trim to max size
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
    }

    /// Keys that are commonly held/repeated intentionally — ignore for duplicate detection
    private static let ignoredKeysForDuplicateDetection: Set<String> = [
        "backspace", "delete", "left", "right", "up", "down",
        "home", "end", "pageup", "pagedown",
        "leftshift", "rightshift", "leftctrl", "rightctrl",
        "leftalt", "rightalt", "leftmeta", "rightmeta",
        "tab", "escape", "caps", "numlock", "space",
        "enter", "return",
    ]

    /// Detects and logs when the same key is pressed 3+ times consecutively within a short window
    /// This helps diagnose unwanted duplicate keystrokes (driver/hardware issues)
    private func detectConsecutiveKeyPresses(key: String, action: String, timestamp: Date, layer: String) {
        // Skip keys that are commonly held/repeated intentionally
        if Self.ignoredKeysForDuplicateDetection.contains(key.lowercased()) {
            return
        }

        // Window for considering keys "consecutive" - 500ms between presses
        let consecutiveWindow: TimeInterval = 0.5

        // Track release events for the current key being monitored
        if key == lastConsecutiveKey, action == "release" {
            sawReleaseBetweenPresses = true
            lastKeyAction = action
            return
        }

        // Only count "press" actions for duplicate detection
        guard action == "press" else {
            lastKeyAction = action
            return
        }

        if key == lastConsecutiveKey,
           let startTime = consecutiveKeyStartTime,
           let lastTimestamp = consecutivePressTimestamps.last,
           timestamp.timeIntervalSince(lastTimestamp) < consecutiveWindow
        {
            // Same key pressed again within window
            consecutiveKeyCount += 1
            consecutivePressTimestamps.append(timestamp)

            if consecutiveKeyCount >= 3 {
                let totalMs = Int(timestamp.timeIntervalSince(startTime) * 1000)

                // Calculate individual intervals for detailed analysis
                var intervals: [Int] = []
                for i in 1 ..< consecutivePressTimestamps.count {
                    let intervalMs = Int(consecutivePressTimestamps[i].timeIntervalSince(consecutivePressTimestamps[i - 1]) * 1000)
                    intervals.append(intervalMs)
                }
                let intervalsStr = intervals.map { "\($0)ms" }.joined(separator: ", ")

                // Determine likely cause based on pattern
                let diagnosis: String
                let avgInterval = totalMs / (consecutiveKeyCount - 1)
                if !sawReleaseBetweenPresses {
                    diagnosis = "NO RELEASE events between presses → likely driver sending duplicate press events"
                } else if avgInterval < 30 {
                    diagnosis = "Very fast intervals (<30ms) with releases → possible Karabiner VHID double-reporting"
                } else if intervals.allSatisfy({ abs($0 - avgInterval) < 10 }) {
                    diagnosis = "Consistent intervals → might be OS key repeat (check rapid-event-delay)"
                } else {
                    diagnosis = "Irregular intervals with releases → unclear cause, may be hardware"
                }

                AppLogger.shared.info(
                    """
                    ⚠️ [DUPLICATE DETECTION] Key '\(key)' pressed \(consecutiveKeyCount)x in \(totalMs)ms
                       Layer: \(layer)
                       Intervals: [\(intervalsStr)]
                       Releases between presses: \(sawReleaseBetweenPresses ? "YES" : "NO")
                       Diagnosis: \(diagnosis)
                    """
                )
            }
        } else {
            // Different key or too long since last press - reset tracking
            lastConsecutiveKey = key
            consecutiveKeyCount = 1
            consecutiveKeyStartTime = timestamp
            consecutivePressTimestamps = [timestamp]
            sawReleaseBetweenPresses = false
        }
        lastKeyAction = action
    }

    /// Clear all events
    func clearEvents() {
        events.removeAll()
    }

    /// Toggle recording on/off
    func toggleRecording() {
        isRecording.toggle()
    }
}
