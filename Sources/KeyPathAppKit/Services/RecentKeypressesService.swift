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

    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    private init() {
        setupObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupObservers() {
        // Listen for key input events
        let keyObserver = NotificationCenter.default.addObserver(
            forName: .kanataKeyInput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, isRecording else { return }

            if let userInfo = notification.userInfo,
               let key = userInfo["key"] as? String,
               let action = userInfo["action"] as? String {
                addEvent(key: key, action: action)
            }
        }
        observers.append(keyObserver)

        // Listen for layer changes
        let layerObserver = NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            if let userInfo = notification.userInfo,
               let layerName = userInfo["layerName"] as? String {
                currentLayer = layerName
            }
        }
        observers.append(layerObserver)
    }

    private func addEvent(key: String, action: String) {
        let event = KeypressEvent(
            key: key,
            action: action,
            timestamp: Date(),
            layer: currentLayer
        )

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
