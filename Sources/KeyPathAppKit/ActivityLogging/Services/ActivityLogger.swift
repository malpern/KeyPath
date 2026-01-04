import AppKit
import Foundation
import KeyPathCore

/// Protocol for observing keyboard events for activity logging
public protocol KeyboardActivityObserver: AnyObject {
    func didReceiveKeyEvent(_ keyPress: KeyPress)
}

/// Main activity logging service
/// Coordinates event capture, buffering, and storage
@MainActor
public final class ActivityLogger: ObservableObject, KeyboardActivityObserver {
    // MARK: - Published State

    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var eventCount: Int = 0
    @Published public private(set) var lastEventTime: Date?

    // MARK: - Singleton

    public static let shared = ActivityLogger()

    // MARK: - Private Properties

    private let storage = ActivityLogStorage.shared
    private var buffer: [ActivityEvent] = []
    private let maxBufferSize = 50
    private let flushInterval: TimeInterval = 30.0

    private var flushTimer: Timer?
    private let workspaceObservers = NotificationObserverManager()

    // MARK: - Initialization

    private init() {
        // Load initial state
        Task {
            eventCount = await storage.totalEventCount()
        }
    }

    // MARK: - Public Interface

    /// Enable activity logging after user consent
    public func enable() async {
        guard !isEnabled else { return }

        isEnabled = true
        startObservers()
        startFlushTimer()

        eventCount = await storage.totalEventCount()

        AppLogger.shared.log("📊 [ActivityLogger] Activity logging enabled")
    }

    /// Disable activity logging
    public func disable() async {
        guard isEnabled else { return }

        stopObservers()
        stopFlushTimer()

        // Flush remaining buffer
        await flush()

        isEnabled = false

        AppLogger.shared.log("📊 [ActivityLogger] Activity logging disabled")
    }

    /// Reset all activity data
    public func resetData() async throws {
        await disable()
        try await storage.clearAll()
        eventCount = 0
        lastEventTime = nil
        buffer.removeAll()

        AppLogger.shared.log("📊 [ActivityLogger] Activity data reset")
    }

    /// Manually flush the buffer to storage
    public func flush() async {
        guard !buffer.isEmpty else { return }

        let eventsToWrite = buffer
        buffer.removeAll()

        do {
            try await storage.append(eventsToWrite)
            AppLogger.shared.log("📊 [ActivityLogger] Flushed \(eventsToWrite.count) events to storage")
        } catch {
            // Re-add to buffer on failure
            buffer.insert(contentsOf: eventsToWrite, at: 0)
            AppLogger.shared.log("❌ [ActivityLogger] Flush failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Event Recording

    /// Record an app switch event
    public func recordAppSwitch(bundleIdentifier: String, appName: String) {
        guard isEnabled else { return }

        let event = ActivityEvent(
            type: .appSwitch,
            payload: .app(AppEventData(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                isLaunch: false
            ))
        )
        appendEvent(event)
    }

    /// Record an app launch event
    public func recordAppLaunch(bundleIdentifier: String, appName: String) {
        guard isEnabled else { return }

        let event = ActivityEvent(
            type: .appLaunch,
            payload: .app(AppEventData(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                isLaunch: true
            ))
        )
        appendEvent(event)
    }

    /// Record a KeyPath action event
    public func recordKeyPathAction(action: String, target: String?, uri: String) {
        guard isEnabled else { return }

        let event = ActivityEvent(
            type: .keyPathAction,
            payload: .action(ActionEventData(
                action: action,
                target: target,
                uri: uri
            ))
        )
        appendEvent(event)
    }

    // MARK: - KeyboardActivityObserver

    /// Called when a keyboard event is captured
    public nonisolated func didReceiveKeyEvent(_ keyPress: KeyPress) {
        // Only log events with modifiers (shortcuts, not typing)
        guard keyPress.modifiers.hasModifiers else { return }

        Task { @MainActor in
            guard isEnabled else { return }

            let event = ActivityEvent(
                type: .keyboardShortcut,
                payload: .shortcut(ShortcutEventData(
                    modifiers: ShortcutModifiers(from: keyPress.modifiers),
                    key: keyPress.baseKey,
                    keyCode: keyPress.keyCode
                ))
            )
            appendEvent(event)
        }
    }

    // MARK: - Private Helpers

    private func appendEvent(_ event: ActivityEvent) {
        buffer.append(event)
        eventCount += 1
        lastEventTime = event.timestamp

        // Auto-flush if buffer is full
        if buffer.count >= maxBufferSize {
            Task {
                await flush()
            }
        }
    }

    private func startObservers() {
        // Observe app activations (switches)
        workspaceObservers.observe(
            NSWorkspace.didActivateApplicationNotification,
            center: NSWorkspace.shared.notificationCenter
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleId = app.bundleIdentifier ?? "unknown"
            let appName = app.localizedName ?? "Unknown"
            Task { @MainActor [weak self] in
                self?.recordAppSwitch(bundleIdentifier: bundleId, appName: appName)
            }
        }

        // Observe app launches
        workspaceObservers.observe(
            NSWorkspace.didLaunchApplicationNotification,
            center: NSWorkspace.shared.notificationCenter
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleId = app.bundleIdentifier ?? "unknown"
            let appName = app.localizedName ?? "Unknown"
            Task { @MainActor [weak self] in
                self?.recordAppLaunch(bundleIdentifier: bundleId, appName: appName)
            }
        }

        AppLogger.shared.log("📊 [ActivityLogger] Started workspace observers")
    }

    private func stopObservers() {
        workspaceObservers.removeAll()
        AppLogger.shared.log("📊 [ActivityLogger] Stopped workspace observers")
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flush()
            }
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }
}

// MARK: - App Termination Handling

public extension ActivityLogger {
    /// Call this when app is about to terminate to flush remaining events
    func prepareForTermination() async {
        if isEnabled {
            await flush()
        }
    }
}
