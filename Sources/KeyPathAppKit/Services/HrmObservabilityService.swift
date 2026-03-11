import Foundation
import KeyPathCore
import Observation

/// Session-scoped HRM telemetry aggregation and conservative tuning guidance.
@Observable
@MainActor
final class HrmObservabilityService {
    static let shared = HrmObservabilityService()

    enum AvailabilityState: String, Sendable {
        case unknown
        case supported
        case unsupported
        case disabledInRuntimeConfig

        var displayName: String {
            switch self {
            case .unknown: "Unknown"
            case .supported: "Supported"
            case .unsupported: "Unsupported"
            case .disabledInRuntimeConfig: "Disabled in runtime config"
            }
        }
    }

    enum CalibrationState: Equatable, Sendable {
        case idle
        case running
        case completed
        case failed(String)
    }

    struct ReasonSummary: Identifiable, Equatable, Sendable {
        let reason: KanataHrmDecisionReason
        let count: Int

        var id: String { reason.rawValue }
    }

    struct KeyBreakdown: Identifiable, Equatable, Sendable {
        let key: String
        let decisions: Int
        let tapCount: Int
        let holdCount: Int
        let avgLatencyMs: Int
        let topReason: KanataHrmDecisionReason?

        var id: String { key }
    }

    struct TimingRecommendation: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let details: String
        let holdDelayDeltaMs: Int
        let tapWindowDeltaMs: Int
        let tapOffsetDeltaMsByKey: [String: Int]
        let holdOffsetDeltaMsByKey: [String: Int]

        var hasEffect: Bool {
            holdDelayDeltaMs != 0 || tapWindowDeltaMs != 0 || !tapOffsetDeltaMsByKey.isEmpty || !holdOffsetDeltaMsByKey.isEmpty
        }
    }

    private struct TraceNotificationPayload: Sendable {
        let schemaVersion: Int
        let key: String
        let decision: KanataHrmDecision
        let reason: KanataHrmDecisionReason
        let decideLatencyMs: Int?
        let nextKey: String?
        let nextKeyHand: KanataHrmKeyHand?
    }

    private(set) var availability: AvailabilityState = .unknown
    private(set) var advertisedCapabilities: Set<String> = []
    private(set) var latestStats: KanataHrmStatsSnapshot?
    private(set) var recentTraceEvents: [KanataHrmTraceEvent] = []
    private(set) var topReasons: [ReasonSummary] = []
    private(set) var perKeyBreakdown: [KeyBreakdown] = []
    private(set) var recommendations: [TimingRecommendation] = []
    private(set) var calibrationState: CalibrationState = .idle
    private(set) var calibrationRemainingSeconds: Int = 0
    private(set) var calibrationStartedAt: Date?
    private(set) var calibrationFinishedAt: Date?

    var supportsHrmStats: Bool {
        advertisedCapabilities.contains("hrm-stats")
    }

    var supportsHrmTrace: Bool {
        advertisedCapabilities.contains("hrm-trace")
    }

    @ObservationIgnored private let observers = NotificationObserverManager()
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var monitoringPort: Int?
    @ObservationIgnored private var statsPollTask: Task<Void, Never>?
    @ObservationIgnored private var calibrationTask: Task<Void, Never>?
    @ObservationIgnored private var breakdownRebuildTask: Task<Void, Never>?
    @ObservationIgnored private var statsConsecutiveFailureCount = 0
    @ObservationIgnored private var calibrationRunToken = UUID()
    @ObservationIgnored private var didLogTraceTruncation = false

    private let maxTraceEvents = 1_000
    private let statsPollInterval: Duration = .seconds(5)
    private let maxStatsPollInterval: Duration = .seconds(60)
    private let traceBreakdownDebounce: Duration = .milliseconds(100)

    private init(
        notificationCenter: NotificationCenter = NotificationObserverManager.defaultCenter,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        setupObservers()
    }

    #if DEBUG
        static func makeTestInstance(
            notificationCenter: NotificationCenter = NotificationCenter(),
            now: @escaping () -> Date = Date.init
        ) -> HrmObservabilityService {
            HrmObservabilityService(notificationCenter: notificationCenter, now: now)
        }

        func _testSetLatestStats(_ stats: KanataHrmStatsSnapshot?) {
            latestStats = stats
            topReasons = stats.map { buildTopReasons(from: $0.reasonCounts) } ?? []
        }

        func _testSetRecentTraceEvents(_ traces: [KanataHrmTraceEvent]) {
            recentTraceEvents = traces
            perKeyBreakdown = buildPerKeyBreakdown(from: traces)
        }

        func _testBuildRecommendations() -> [TimingRecommendation] {
            buildRecommendations(stats: latestStats, traces: recentTraceEvents)
        }

        func _testSetRecommendations(_ values: [TimingRecommendation]) {
            recommendations = values
        }
    #endif

    deinit {
        statsPollTask?.cancel()
        calibrationTask?.cancel()
        breakdownRebuildTask?.cancel()
    }

    func startMonitoring(port: Int) {
        if monitoringPort == port, statsPollTask != nil { return }

        monitoringPort = port
        restartStatsPolling()
    }

    func stopMonitoring() {
        statsPollTask?.cancel()
        statsPollTask = nil
        calibrationTask?.cancel()
        calibrationTask = nil
        breakdownRebuildTask?.cancel()
        breakdownRebuildTask = nil
        statsConsecutiveFailureCount = 0
        monitoringPort = nil
        calibrationRunToken = UUID()
        calibrationState = .idle
        calibrationRemainingSeconds = 0
    }

    func startCalibration(durationSeconds: Int = 60) {
        guard let port = monitoringPort else {
            calibrationState = .failed("Kanata TCP port not configured.")
            return
        }
        guard supportsHrmStats else {
            calibrationState = .failed("HRM telemetry is not supported by the current Kanata build.")
            return
        }

        calibrationTask?.cancel()
        let runToken = UUID()
        calibrationRunToken = runToken
        calibrationState = .running
        calibrationRemainingSeconds = max(1, durationSeconds)
        calibrationStartedAt = now()
        calibrationFinishedAt = nil
        recommendations = []
        recentTraceEvents.removeAll(keepingCapacity: true)
        didLogTraceTruncation = false

        calibrationTask = Task { [weak self, runToken] in
            guard let self else { return }
            let client = KanataTCPClient(port: port, timeout: 3.0)
            defer {
                Task {
                    await client.cancelInflightAndCloseConnection()
                }
            }

            if supportsHrmStats {
                do {
                    try await client.resetHrmStats()
                } catch {
                    guard calibrationRunToken == runToken else { return }
                    calibrationRemainingSeconds = 0
                    calibrationState = .failed("Failed to reset HRM stats: \(error.localizedDescription)")
                    return
                }
            }

            for second in stride(from: calibrationRemainingSeconds, through: 1, by: -1) {
                guard calibrationRunToken == runToken else { return }
                calibrationRemainingSeconds = second
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    guard calibrationRunToken == runToken else { return }
                    calibrationRemainingSeconds = 0
                    calibrationState = .idle
                    return
                } catch {
                    continue
                }
            }
            guard calibrationRunToken == runToken else { return }
            calibrationRemainingSeconds = 0

            await refreshStats(using: client)
            guard calibrationRunToken == runToken else { return }
            recommendations = buildRecommendations(stats: latestStats, traces: recentTraceEvents)
            calibrationFinishedAt = now()
            calibrationState = .completed
        }
    }

    func applyRecommendations(to config: inout HomeRowModsConfig) {
        for recommendation in recommendations where recommendation.hasEffect {
            apply(recommendation: recommendation, to: &config)
        }
    }

    func refreshNow() {
        guard monitoringPort != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await refreshStats(using: nil)
        }
    }

    private func setupObservers() {
        observers.observe(.kanataCapabilitiesUpdated, center: notificationCenter) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?["capabilities"] as? [String] ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                handleCapabilities(raw)
            }
        }

        observers.observe(.kanataHrmTrace, center: notificationCenter) { [weak self] note in
            guard let self else { return }
            guard let payload = Self.makeTraceNotificationPayload(userInfo: note.userInfo) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                ingestTrace(payload)
            }
        }

        // Bridge HoldActivated/TapActivated events (with reason) into the trace pipeline.
        // This provides data even without the dedicated HrmTrace message type.
        observers.observe(.kanataHoldActivated, center: notificationCenter) { [weak self] note in
            guard let self else { return }
            guard let key = note.userInfo?["key"] as? String else { return }
            let reasonStr = note.userInfo?["reason"] as? String
            guard let reason = reasonStr.flatMap({ KanataHrmDecisionReason(rawValue: $0) }) else {
                if let reasonStr { AppLogger.shared.debug("📈 [HRM] Unrecognized hold reason: \(reasonStr)") }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                ingestActivationEvent(key: key, decision: .hold, reason: reason)
            }
        }

        observers.observe(.kanataTapActivated, center: notificationCenter) { [weak self] note in
            guard let self else { return }
            guard let key = note.userInfo?["key"] as? String else { return }
            let reasonStr = note.userInfo?["reason"] as? String
            guard let reason = reasonStr.flatMap({ KanataHrmDecisionReason(rawValue: $0) }) else {
                if let reasonStr { AppLogger.shared.debug("📈 [HRM] Unrecognized tap reason: \(reasonStr)") }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                ingestActivationEvent(key: key, decision: .tap, reason: reason)
            }
        }
    }

    private func restartStatsPolling() {
        statsPollTask?.cancel()
        statsPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshStats(using: nil)
                if Task.isCancelled { return }
                try? await Task.sleep(for: currentStatsPollInterval())
            }
        }
    }

    private func currentStatsPollInterval() -> Duration {
        switch statsConsecutiveFailureCount {
        case ..<1:
            return statsPollInterval
        case 1:
            return .seconds(10)
        case 2:
            return .seconds(30)
        default:
            return maxStatsPollInterval
        }
    }

    private func handleCapabilities(_ rawCapabilities: [String]) {
        let normalized = Set(KanataEventListener.normalizedCapabilities(rawCapabilities))
        advertisedCapabilities = normalized

        if normalized.contains("hrm-stats") || normalized.contains("hrm-trace") {
            if availability == .unknown || availability == .unsupported {
                availability = .supported
            }
        } else {
            availability = .unsupported
            latestStats = nil
            topReasons = []
            perKeyBreakdown = []
            recommendations = []
        }
    }

    private func ingestActivationEvent(key: String, decision: KanataHrmDecision, reason: KanataHrmDecisionReason) {
        let payload = TraceNotificationPayload(
            schemaVersion: 1,
            key: key,
            decision: decision,
            reason: reason,
            decideLatencyMs: nil,
            nextKey: nil,
            nextKeyHand: nil
        )
        ingestTrace(payload)
    }

    private func ingestTrace(_ payload: TraceNotificationPayload) {
        let event = KanataHrmTraceEvent(
            schemaVersion: payload.schemaVersion,
            key: payload.key.lowercased(),
            decision: payload.decision,
            reason: payload.reason,
            decideLatencyMs: payload.decideLatencyMs,
            nextKey: payload.nextKey,
            nextKeyHand: payload.nextKeyHand,
            timestamp: now()
        )
        recentTraceEvents.append(event)
        if recentTraceEvents.count > maxTraceEvents {
            recentTraceEvents.removeFirst(recentTraceEvents.count - maxTraceEvents)
            if !didLogTraceTruncation {
                AppLogger.shared.debug("📈 [HRM] Trace buffer capped at \(maxTraceEvents) events; older entries will be dropped")
                didLogTraceTruncation = true
            }
        }
        schedulePerKeyBreakdownRebuild()

        if availability == .unknown {
            availability = .supported
        }
    }

    private func schedulePerKeyBreakdownRebuild() {
        breakdownRebuildTask?.cancel()
        breakdownRebuildTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.traceBreakdownDebounce)
            guard !Task.isCancelled else { return }
            perKeyBreakdown = buildPerKeyBreakdown(from: recentTraceEvents)
            // Also rebuild topReasons from trace events when stats polling isn't available
            if latestStats == nil {
                topReasons = buildTopReasonsFromTraces(recentTraceEvents)
            }
        }
    }

    nonisolated private static func makeTraceNotificationPayload(userInfo: [AnyHashable: Any]?) -> TraceNotificationPayload? {
        guard let userInfo else { return nil }
        guard let schemaVersion = userInfo["schemaVersion"] as? Int,
              let key = userInfo["key"] as? String,
              let decisionRaw = userInfo["decision"] as? String,
              let decision = KanataHrmDecision(rawValue: decisionRaw),
              let reasonRaw = userInfo["reason"] as? String,
              let reason = KanataHrmDecisionReason(rawValue: reasonRaw)
        else {
            return nil
        }

        let decideLatencyMs = userInfo["decideLatencyMs"] as? Int
        let nextKey = userInfo["nextKey"] as? String
        let nextKeyHand = (userInfo["nextKeyHand"] as? String).flatMap(KanataHrmKeyHand.init(rawValue:))

        return TraceNotificationPayload(
            schemaVersion: schemaVersion,
            key: key,
            decision: decision,
            reason: reason,
            decideLatencyMs: decideLatencyMs,
            nextKey: nextKey,
            nextKeyHand: nextKeyHand
        )
    }

    private func refreshStats(using existingClient: KanataTCPClient?) async {
        guard supportsHrmStats else { return }
        guard let port = monitoringPort else { return }

        let client = existingClient ?? KanataTCPClient(port: port, timeout: 2.0)
        defer {
            if existingClient == nil {
                Task {
                    await client.cancelInflightAndCloseConnection()
                }
            }
        }

        do {
            let stats = try await client.requestHrmStats()
            latestStats = stats
            topReasons = buildTopReasons(from: stats.reasonCounts)
            statsConsecutiveFailureCount = 0
            if availability != .supported {
                availability = .supported
            }
            postStatsUpdated(stats)
        } catch {
            statsConsecutiveFailureCount += 1
            if supportsHrmStats && isLikelyRuntimeDisabled(error) {
                availability = .disabledInRuntimeConfig
            }
            if statsConsecutiveFailureCount >= 3 {
                AppLogger.shared.warn(
                    "📈 [HRM] Failed to refresh stats (\(statsConsecutiveFailureCount) consecutive): \(error.localizedDescription)"
                )
            } else {
                AppLogger.shared.debug("📈 [HRM] Failed to refresh stats: \(error.localizedDescription)")
            }
        }
    }

    private func postStatsUpdated(_ stats: KanataHrmStatsSnapshot) {
        notificationCenter.post(
            name: .kanataHrmStatsUpdated,
            object: nil,
            userInfo: [
                "decisionsTotal": stats.decisionsTotal,
                "tapCount": stats.tapCount,
                "holdCount": stats.holdCount,
                "avgDecideLatencyMs": stats.avgDecideLatencyMs
            ]
        )
    }

    /// Top 3 reasons by frequency, for a compact summary in the HRM insights panel.
    private func buildTopReasons(from counts: KanataHrmReasonCounts) -> [ReasonSummary] {
        Array(KanataHrmDecisionReason.allCases
            .map { ReasonSummary(reason: $0, count: counts.count(for: $0)) }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason.displayName < rhs.reason.displayName
                }
                return lhs.count > rhs.count
            }
            .prefix(3))
    }

    private func buildTopReasonsFromTraces(_ traces: [KanataHrmTraceEvent]) -> [ReasonSummary] {
        var counts: [KanataHrmDecisionReason: Int] = [:]
        for trace in traces {
            counts[trace.reason, default: 0] += 1
        }
        return Array(counts
            .map { ReasonSummary(reason: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason.displayName < rhs.reason.displayName
                }
                return lhs.count > rhs.count
            }
            .prefix(3))
    }

    private func buildPerKeyBreakdown(from traces: [KanataHrmTraceEvent]) -> [KeyBreakdown] {
        let trackedKeys = Set(HomeRowModsConfig.allKeys)
        var grouped: [String: [KanataHrmTraceEvent]] = [:]
        for trace in traces where trackedKeys.contains(trace.key.lowercased()) {
            grouped[trace.key.lowercased(), default: []].append(trace)
        }

        return HomeRowModsConfig.allKeys.compactMap { key in
            guard let events = grouped[key], !events.isEmpty else { return nil }

            let tapCount = events.reduce(into: 0) { partialResult, event in
                if event.decision == .tap {
                    partialResult += 1
                }
            }
            let holdCount = events.count - tapCount
            let latencies = events.compactMap(\.decideLatencyMs)
            let average = latencies.isEmpty ? 0 : Int(Double(latencies.reduce(0, +)) / Double(latencies.count))

            let topReason = Dictionary(grouping: events, by: \.reason)
                .max { lhs, rhs in
                    if lhs.value.count == rhs.value.count {
                        return lhs.key.displayName > rhs.key.displayName
                    }
                    return lhs.value.count < rhs.value.count
                }?
                .key

            return KeyBreakdown(
                key: key,
                decisions: events.count,
                tapCount: tapCount,
                holdCount: holdCount,
                avgLatencyMs: average,
                topReason: topReason
            )
        }
    }

    private func buildRecommendations(
        stats: KanataHrmStatsSnapshot?,
        traces: [KanataHrmTraceEvent]
    ) -> [TimingRecommendation] {
        guard let stats, stats.decisionsTotal > 0 else { return [] }

        var generated: [TimingRecommendation] = []
        let total = Double(stats.decisionsTotal)
        let releaseRate = Double(stats.reasonCounts.releaseBeforeTimeout) / total
        let timeoutRate = Double(stats.reasonCounts.timeout) / total

        if releaseRate >= 0.25, releaseRate > timeoutRate + 0.1 {
            generated.append(
                TimingRecommendation(
                    id: "reduce-hold-delay-release-before-decide",
                    title: "Reduce hold delay slightly",
                    details: "High release-before-decide rates suggest hold activation is arriving too late. Try making hold activation a bit faster.",
                    holdDelayDeltaMs: -10,
                    tapWindowDeltaMs: 0,
                    tapOffsetDeltaMsByKey: [:],
                    holdOffsetDeltaMsByKey: [:]
                )
            )
        } else if timeoutRate >= 0.25 {
            generated.append(
                TimingRecommendation(
                    id: "increase-hold-delay-timeout",
                    title: "Increase hold delay",
                    details: "Timeout-driven holds are high. Increase hold delay to reduce accidental modifier activation during regular typing.",
                    holdDelayDeltaMs: 10,
                    tapWindowDeltaMs: 5,
                    tapOffsetDeltaMsByKey: [:],
                    holdOffsetDeltaMsByKey: [:]
                )
            )
        }

        let accidentalReasons: Set<KanataHrmDecisionReason> = [.releaseBeforeTimeout, .sameHandRoll, .unknownHand]
        let accidentalByKey = traces.reduce(into: [String: Int]()) { partialResult, trace in
            guard accidentalReasons.contains(trace.reason) else { return }
            let normalized = trace.key.lowercased()
            guard HomeRowModsConfig.allKeys.contains(normalized) else { return }
            partialResult[normalized, default: 0] += 1
        }

        let clusteredKeys = accidentalByKey
            .filter { $0.value >= 3 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(3)

        if !clusteredKeys.isEmpty {
            var tapOffsets: [String: Int] = [:]
            let preview = clusteredKeys.map { "\($0.key.uppercased()) (\($0.value))" }.joined(separator: ", ")
            for key in clusteredKeys.map(\.key) {
                tapOffsets[key] = 15
            }

            generated.append(
                TimingRecommendation(
                    id: "per-key-tap-offset-cluster",
                    title: "Add per-key tap offsets",
                    details: "Accidental decisions are clustered on \(preview). Add a small per-key tap offset for those keys.",
                    holdDelayDeltaMs: 0,
                    tapWindowDeltaMs: 0,
                    tapOffsetDeltaMsByKey: tapOffsets,
                    holdOffsetDeltaMsByKey: [:]
                )
            )
        }

        return generated
    }

    private func apply(recommendation: TimingRecommendation, to config: inout HomeRowModsConfig) {
        config.timing.holdDelay = clamp(config.timing.holdDelay + recommendation.holdDelayDeltaMs, min: 60, max: 400)
        config.timing.tapWindow = clamp(config.timing.tapWindow + recommendation.tapWindowDeltaMs, min: 60, max: 400)

        for (key, delta) in recommendation.tapOffsetDeltaMsByKey {
            let next = (config.timing.tapOffsets[key] ?? 0) + delta
            if next == 0 {
                config.timing.tapOffsets.removeValue(forKey: key)
            } else {
                config.timing.tapOffsets[key] = clamp(next, min: -100, max: 200)
            }
        }

        for (key, delta) in recommendation.holdOffsetDeltaMsByKey {
            let next = (config.timing.holdOffsets[key] ?? 0) + delta
            if next == 0 {
                config.timing.holdOffsets.removeValue(forKey: key)
            } else {
                config.timing.holdOffsets[key] = clamp(next, min: -100, max: 200)
            }
        }
    }

    private func isLikelyRuntimeDisabled(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("disabled") || message.contains("not enabled")
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
