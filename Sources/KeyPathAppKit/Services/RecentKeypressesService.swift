import Foundation
import KeyPathCore

/// Tracks recent keypresses from Kanata TCP events for debugging and visualization.
@MainActor
final class RecentKeypressesService: ObservableObject {
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
    @Published private(set) var events: [KeypressEvent] = []

    /// Current layer name (for context)
    @Published private(set) var currentLayer: String = "base"

    /// Whether recording is enabled
    @Published var isRecording: Bool = true

    private let observers = NotificationObserverManager()

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Listen for key input events
        observers.observe(.kanataKeyInput) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let key = userInfo?["key"] as? String
            let action = userInfo?["action"] as? String
            Task { @MainActor [weak self] in
                guard let self, isRecording, let key, let action else { return }
                addEvent(key: key, action: action)
            }
        }

        // Listen for layer changes
        observers.observe(.kanataLayerChanged) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let layerName = userInfo?["layerName"] as? String
            Task { @MainActor [weak self] in
                guard let self, let layerName else { return }
                currentLayer = layerName
            }
        }
    }

    private func addEvent(key: String, action: String) {
        let event = KeypressEvent(
            key: key,
            action: action,
            timestamp: Date(),
            layer: currentLayer
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
            AppLogger.shared.debug("🚫 [Keypresses] Skipping duplicate: \(key) \(action) within \(millisDiff)ms")
            return
        }

        events.insert(event, at: 0)

        // Trim to max size
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
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
