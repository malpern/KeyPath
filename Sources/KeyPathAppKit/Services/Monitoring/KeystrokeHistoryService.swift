import AppKit
import Foundation
import KeyPathCore
import Observation

@Observable
@MainActor
final class KeystrokeHistoryService {
    static let shared = KeystrokeHistoryService()

    private let maxEvents = 2000
    private let deduplicationWindow: TimeInterval = 0.1
    private let batchInterval: TimeInterval = 0.1

    private(set) var segments: [TimelineSegment] = []
    private(set) var currentLayer: String = "base"
    private(set) var eventCount: Int = 0
    var isRecording: Bool = false

    @ObservationIgnored private var rawEvents: [KeystrokeTimelineEvent] = []
    @ObservationIgnored private var pendingEvents: [KeystrokeTimelineEvent] = []
    @ObservationIgnored private var batchTimer: Timer?
    @ObservationIgnored private let observers = NotificationObserverManager()
    @ObservationIgnored private let workspaceObservers = NotificationObserverManager()
    @ObservationIgnored private var currentAppBundleId: String?
    @ObservationIgnored private var currentAppName: String?
    @ObservationIgnored private var lastTypedAppBundleId: String?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored var thresholdLookup: (() -> (baseMs: Int, offsets: [String: Int]))?

    private init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        setupObservers()
        Task { @MainActor in
            self.isRecording = await InstalledPackTracker.shared.isInstalled(
                packID: PackRegistry.keystrokeHistory.id
            )
        }
    }

    #if DEBUG
        static func makeTestInstance(
            notificationCenter: NotificationCenter = NotificationCenter()
        ) -> KeystrokeHistoryService {
            let instance = KeystrokeHistoryService(notificationCenter: notificationCenter)
            instance.isRecording = true
            return instance
        }
    #endif

    // MARK: - Notification Observers

    private func setupObservers() {
        observers.observe(.kanataKeyInput, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let actionStr = userInfo?["action"] as? String,
                  let action = KanataKeyAction(rawValue: actionStr.lowercased())
            else { return }
            let metadata = KeypressObservationMetadata.from(userInfo: userInfo)
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: metadata.observedAt ?? Date(),
                kind: .keyInput(KeyInputPayload(
                    key: key,
                    action: action,
                    layer: nil,
                    kanataTimestamp: metadata.kanataTimestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        observers.observe(.kanataLayerChanged, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            guard let layerName = notification.userInfo?["layerName"] as? String else { return }
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .layerChanged(LayerChangePayload(layerName: layerName))
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentLayer = layerName
                ingest(event)
            }
        }

        observers.observe(.kanataHoldActivated, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let action = userInfo?["action"] as? String
            else { return }
            let reason = userInfo?["reason"] as? String
            let timestamp = (userInfo?["kanataTimestamp"] as? UInt64) ?? 0
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .holdActivated(TapHoldPayload(
                    key: key,
                    outputAction: action,
                    reason: reason,
                    kanataTimestamp: timestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        observers.observe(.kanataTapActivated, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let action = userInfo?["action"] as? String
            else { return }
            let reason = userInfo?["reason"] as? String
            let timestamp = (userInfo?["kanataTimestamp"] as? UInt64) ?? 0
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .tapActivated(TapHoldPayload(
                    key: key,
                    outputAction: action,
                    reason: reason,
                    kanataTimestamp: timestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        observers.observe(.kanataHrmTrace, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let decisionStr = userInfo?["decision"] as? String,
                  let decision = KanataHrmDecision(rawValue: decisionStr),
                  let reasonStr = userInfo?["reason"] as? String,
                  let reason = KanataHrmDecisionReason(rawValue: reasonStr)
            else { return }
            let latencyMs = userInfo?["decideLatencyMs"] as? Int
            let nextKey = userInfo?["nextKey"] as? String
            let nextKeyHandStr = userInfo?["nextKeyHand"] as? String
            let nextKeyHand = nextKeyHandStr.flatMap { KanataHrmKeyHand(rawValue: $0) }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let threshold = lookupThreshold(for: key)
                let isNear = Self.computeNearThreshold(
                    latencyMs: latencyMs,
                    thresholdMs: threshold
                )
                let event = KeystrokeTimelineEvent(
                    id: UUID(),
                    timestamp: Date(),
                    kind: .hrmDecision(HrmDecisionPayload(
                        key: key,
                        decision: decision,
                        reason: reason,
                        decideLatencyMs: latencyMs,
                        nextKey: nextKey,
                        nextKeyHand: nextKeyHand,
                        configuredThresholdMs: threshold,
                        isNearThreshold: isNear
                    ))
                )
                ingest(event)
            }
        }

        observers.observe(.kanataOneShotActivated, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let modifiers = userInfo?["modifiers"] as? String
            else { return }
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .oneShotActivated(OneShotPayload(key: key, modifiers: modifiers))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        observers.observe(.kanataChordResolved, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let keys = userInfo?["keys"] as? String,
                  let action = userInfo?["action"] as? String
            else { return }
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .chordResolved(ChordPayload(keys: keys, action: action))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        workspaceObservers.observe(
            NSWorkspace.didActivateApplicationNotification,
            center: NSWorkspace.shared.notificationCenter
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier
            else { return }
            let appName = app.localizedName ?? bundleId
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentAppBundleId = bundleId
                currentAppName = appName
            }
        }

        observers.observe(.kanataTapDanceResolved, center: notificationCenter) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            guard let key = userInfo?["key"] as? String,
                  let tapCount = userInfo?["tapCount"] as? UInt8,
                  let action = userInfo?["action"] as? String
            else { return }
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .tapDanceResolved(TapDancePayload(key: key, tapCount: tapCount, action: action))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }
    }

    // MARK: - Event Ingestion

    private func ingest(_ event: KeystrokeTimelineEvent) {
        guard isRecording else { return }

        if case let .keyInput(payload) = event.kind {
            if isDuplicate(key: payload.key, action: payload.action, timestamp: event.timestamp) {
                return
            }
        }

        // Insert app context divider when first keystroke arrives in a different app
        if isKeystrokeEvent(event),
           let appId = currentAppBundleId,
           appId != lastTypedAppBundleId
        {
            lastTypedAppBundleId = appId
            let appEvent = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: event.timestamp,
                kind: .appChanged(AppChangedPayload(
                    appName: currentAppName ?? appId,
                    bundleIdentifier: appId
                ))
            )
            pendingEvents.append(appEvent)
        }

        pendingEvents.append(event)
        scheduleBatchFlush()
    }

    private func isKeystrokeEvent(_ event: KeystrokeTimelineEvent) -> Bool {
        switch event.kind {
        case .keyInput, .tapActivated, .holdActivated, .chordResolved, .tapDanceResolved:
            true
        case .layerChanged, .hrmDecision, .oneShotActivated, .appChanged:
            false
        }
    }

    private func isDuplicate(key: String, action: KanataKeyAction, timestamp: Date) -> Bool {
        let cutoff = timestamp.addingTimeInterval(-deduplicationWindow)
        return rawEvents.suffix(10).contains { existing in
            if case let .keyInput(payload) = existing.kind {
                return payload.key == key &&
                    payload.action == action &&
                    existing.timestamp > cutoff
            }
            return false
        }
    }

    private func scheduleBatchFlush() {
        guard batchTimer == nil else { return }
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPendingEvents()
            }
        }
    }

    private func flushPendingEvents() {
        batchTimer = nil
        guard !pendingEvents.isEmpty else { return }

        let layerAtFlush = currentLayer
        let enriched = pendingEvents.map { event -> KeystrokeTimelineEvent in
            if case let .keyInput(payload) = event.kind, payload.layer == nil {
                return KeystrokeTimelineEvent(
                    id: event.id,
                    timestamp: event.timestamp,
                    kind: .keyInput(KeyInputPayload(
                        key: payload.key,
                        action: payload.action,
                        layer: layerAtFlush,
                        kanataTimestamp: payload.kanataTimestamp
                    ))
                )
            }
            return event
        }

        rawEvents.append(contentsOf: enriched)
        pendingEvents.removeAll()

        if rawEvents.count > maxEvents {
            rawEvents.removeFirst(rawEvents.count - maxEvents)
        }

        eventCount = rawEvents.count
        rebuildSegments()
    }

    // MARK: - Threshold Lookup

    private func lookupThreshold(for key: String) -> Int? {
        guard let lookup = thresholdLookup else { return nil }
        let config = lookup()
        let offset = config.offsets[key] ?? 0
        return config.baseMs + offset
    }

    static func computeNearThreshold(latencyMs: Int?, thresholdMs: Int?) -> Bool {
        guard let latency = latencyMs, let threshold = thresholdMs else { return false }
        return abs(latency - threshold) <= HrmDecisionPayload.nearThresholdMarginMs
    }

    // MARK: - Segment Rebuild

    private func rebuildSegments() {
        segments = TimelineGrouper.group(rawEvents, currentLayer: currentLayer)
    }

    // MARK: - Public API

    func clearEvents() {
        rawEvents.removeAll()
        pendingEvents.removeAll()
        batchTimer?.invalidate()
        batchTimer = nil
        eventCount = 0
        segments = []
    }
}
