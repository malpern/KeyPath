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
    @ObservationIgnored private var layerObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var hrmTraceObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var actionObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var keyInputObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var holdActivatedObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var tapActivatedObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var oneShotActivatedObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var chordResolvedObserver: NotificationCenter.ObservationToken?
    @ObservationIgnored private var tapDanceResolvedObserver: NotificationCenter.ObservationToken?
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
        keyInputObserver = notificationCenter.addObserver(for: KanataObservedKeyInput.self) { [weak self] observation in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: observation.observedAt,
                kind: .keyInput(KeyInputPayload(
                    key: observation.key,
                    action: observation.action,
                    layer: nil,
                    kanataTimestamp: observation.kanataTimestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        layerObserver = notificationCenter.addObserver(for: KanataLayerChange.self) { [weak self] change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let layerName = change.layerName
                guard layerName.lowercased() != currentLayer.lowercased() else { return }
                currentLayer = layerName
                let event = KeystrokeTimelineEvent(
                    id: UUID(),
                    timestamp: Date(),
                    kind: .layerChanged(LayerChangePayload(layerName: layerName))
                )
                ingest(event)
            }
        }

        holdActivatedObserver = notificationCenter.addObserver(for: KanataHoldActivation.self) { [weak self] activation in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .holdActivated(TapHoldPayload(
                    key: activation.key, outputAction: activation.action,
                    reason: activation.reason, kanataTimestamp: activation.timestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        tapActivatedObserver = notificationCenter.addObserver(for: KanataTapActivation.self) { [weak self] activation in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .tapActivated(TapHoldPayload(
                    key: activation.key, outputAction: activation.action,
                    reason: activation.reason, kanataTimestamp: activation.timestamp
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        hrmTraceObserver = notificationCenter.addObserver(for: KanataHrmTraceEvent.self) { [weak self] trace in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let threshold = lookupThreshold(for: trace.key)
                let isNear = Self.computeNearThreshold(
                    latencyMs: trace.decideLatencyMs,
                    thresholdMs: threshold
                )
                let event = KeystrokeTimelineEvent(
                    id: UUID(),
                    timestamp: Date(),
                    kind: .hrmDecision(HrmDecisionPayload(
                        key: trace.key,
                        decision: trace.decision,
                        reason: trace.reason,
                        decideLatencyMs: trace.decideLatencyMs,
                        nextKey: trace.nextKey,
                        nextKeyHand: trace.nextKeyHand,
                        configuredThresholdMs: threshold,
                        isNearThreshold: isNear
                    ))
                )
                ingest(event)
            }
        }

        oneShotActivatedObserver = notificationCenter.addObserver(for: KanataOneShotActivation.self) { [weak self] activation in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .oneShotActivated(OneShotPayload(key: activation.key, modifiers: activation.modifiers))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        chordResolvedObserver = notificationCenter.addObserver(for: KanataChordResolution.self) { [weak self] resolution in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .chordResolved(ChordPayload(keys: resolution.keys, action: resolution.action))
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

        tapDanceResolvedObserver = notificationCenter.addObserver(for: KanataTapDanceResolution.self) { [weak self] resolution in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .tapDanceResolved(TapDancePayload(key: resolution.key, tapCount: resolution.tapCount, action: resolution.action))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        actionObserver = notificationCenter.addObserver(for: KanataActionDispatched.self) { [weak self] action in
            let event = KeystrokeTimelineEvent(
                id: UUID(),
                timestamp: Date(),
                kind: .actionDispatched(ActionDispatchedPayload(
                    action: action.uri.action,
                    target: action.uri.target ?? "",
                    uri: action.uri.url.absoluteString
                ))
            )
            Task { @MainActor [weak self] in
                self?.ingest(event)
            }
        }

        observers.observe(.installedPacksChanged, center: notificationCenter) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let installed = await InstalledPackTracker.shared.isInstalled(
                    packID: PackRegistry.keystrokeHistory.id
                )
                isRecording = installed
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
        case .keyInput, .tapActivated, .holdActivated, .chordResolved, .tapDanceResolved, .actionDispatched:
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

    #if DEBUG
        func flushPendingEventsForTesting() {
            batchTimer?.invalidate()
            batchTimer = nil
            flushPendingEvents()
        }
    #endif

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

    /// Apply the committed activation/deactivation of the app's pack.
    func applyPackState(_ installed: Bool) {
        isRecording = installed
        if !installed { clearEvents() }
    }

    func clearEvents() {
        rawEvents.removeAll()
        pendingEvents.removeAll()
        batchTimer?.invalidate()
        batchTimer = nil
        eventCount = 0
        segments = []
    }
}
