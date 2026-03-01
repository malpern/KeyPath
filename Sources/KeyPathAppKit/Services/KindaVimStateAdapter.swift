import Foundation
import KeyPathCore
import Observation

/// Mode signal adapter for KindaVim.
///
/// Primary source is `environment.json` written by KindaVim:
/// `~/Library/Application Support/kindaVim/environment.json`
///
/// Contract:
/// - strict mode enum (`insert`, `normal`, `visual`, `unknown`)
/// - metadata (`source`, `confidence`, `timestamp`, `isStale`)
/// - robust file watching with malformed/missing fallback handling
/// - de-noise duplicate unchanged values while still tracking freshness
@MainActor
@Observable
final class KindaVimStateAdapter {
    enum Mode: String, CaseIterable, Equatable, Sendable {
        case insert
        case normal
        case visual
        case unknown

        var displayName: String {
            switch self {
            case .insert: "Insert"
            case .normal: "Normal"
            case .visual: "Visual"
            case .unknown: "Unknown"
            }
        }
    }

    enum Source: String, Equatable, Sendable {
        case json
        case karabiner
        case fallback
    }

    enum Confidence: String, Equatable, Sendable {
        case high
        case medium
        case low
    }

    struct StateSnapshot: Equatable, Sendable {
        let mode: Mode
        let source: Source
        let confidence: Confidence
        let timestamp: Date
        let isStale: Bool
    }

    struct EnvironmentPayload: Codable, Equatable {
        let mode: String?
    }

    static let shared = KindaVimStateAdapter()

    static var defaultEnvironmentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("kindaVim")
            .appendingPathComponent("environment.json")
    }

    private enum Constants {
        static let staleAfterSeconds: TimeInterval = 5
        static let staleTickSeconds: TimeInterval = 1
        static let retryCount = 2
        static let retryDelay: Duration = .milliseconds(120)
    }

    private struct SnapshotFingerprint: Equatable {
        let mode: Mode
        let source: Source
        let confidence: Confidence
        let isStale: Bool
    }

    public private(set) var state: StateSnapshot
    public private(set) var isMonitoring = false
    public private(set) var isEnvironmentFilePresent = false
    public private(set) var rawModeValue: String?
    public private(set) var lastErrorDescription: String?
    /// Monotonic counter for emitted state updates (used by tests and debug tooling).
    public private(set) var updateSequence: UInt64 = 0

    @ObservationIgnored private var monitoringCount = 0
    @ObservationIgnored private var staleTickerTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: ConfigFileWatcher?
    @ObservationIgnored private var lastFreshSignalAt: Date?
    @ObservationIgnored private let environmentURL: URL
    @ObservationIgnored private let nowProvider: () -> Date
    @ObservationIgnored private let karabinerModeProvider: @Sendable () -> Mode?

    init(
        environmentURL: URL = KindaVimStateAdapter.defaultEnvironmentURL,
        nowProvider: @escaping () -> Date = Date.init,
        karabinerModeProvider: @escaping @Sendable () -> Mode? = { nil }
    ) {
        self.environmentURL = environmentURL
        self.nowProvider = nowProvider
        self.karabinerModeProvider = karabinerModeProvider
        let now = nowProvider()
        state = StateSnapshot(
            mode: .unknown,
            source: .fallback,
            confidence: .low,
            timestamp: now,
            isStale: true
        )
        refresh()
    }

    func startMonitoring() {
        monitoringCount += 1
        guard monitoringCount == 1 else { return }

        let newWatcher = ConfigFileWatcher()
        newWatcher.startWatching(path: environmentURL.path) { [weak self] in
            self?.refresh()
        }
        watcher = newWatcher
        isMonitoring = true
        startStaleTicker()
        refresh()

        AppLogger.shared.log("👀 [KindaVimState] Started monitoring \(environmentURL.path)")
    }

    func stopMonitoring() {
        guard monitoringCount > 0 else { return }
        monitoringCount -= 1
        guard monitoringCount == 0 else { return }

        watcher?.stopWatching()
        watcher = nil
        refreshTask?.cancel()
        refreshTask = nil
        staleTickerTask?.cancel()
        staleTickerTask = nil
        isMonitoring = false

        AppLogger.shared.log("🛑 [KindaVimState] Stopped monitoring")
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshWithRetries(remainingRetries: Constants.retryCount)
        }
    }

    private func refreshWithRetries(remainingRetries: Int) async {
        guard !Task.isCancelled else { return }

        let fileExists = FileManager.default.fileExists(atPath: environmentURL.path)
        isEnvironmentFilePresent = fileExists

        if fileExists {
            do {
                let data = try Data(contentsOf: environmentURL)
                if let rawMode = Self.parseMode(from: data) {
                    applySignalFromJSON(rawMode: rawMode)
                    return
                }

                // Partial writes can transiently produce malformed/partial JSON.
                if remainingRetries > 0 {
                    try? await Task.sleep(for: Constants.retryDelay)
                    await refreshWithRetries(remainingRetries: remainingRetries - 1)
                    return
                }

                lastErrorDescription = "Malformed environment.json"
                applyFallbackState()
                return
            } catch {
                if remainingRetries > 0 {
                    try? await Task.sleep(for: Constants.retryDelay)
                    await refreshWithRetries(remainingRetries: remainingRetries - 1)
                    return
                }

                lastErrorDescription = error.localizedDescription
                applyFallbackState()
                return
            }
        }

        lastErrorDescription = nil
        applyFallbackState()
    }

    private func applySignalFromJSON(rawMode: String) {
        let normalizedMode = Self.normalizedMode(from: rawMode)
        let confidence: Confidence = normalizedMode == .unknown ? .medium : .high
        let now = nowProvider()
        lastFreshSignalAt = now
        rawModeValue = rawMode
        lastErrorDescription = nil

        // De-noise duplicate unchanged values while still refreshing freshness.
        let currentFingerprint = SnapshotFingerprint(
            mode: state.mode,
            source: state.source,
            confidence: state.confidence,
            isStale: state.isStale
        )
        let incomingFingerprint = SnapshotFingerprint(
            mode: normalizedMode,
            source: .json,
            confidence: confidence,
            isStale: false
        )

        guard currentFingerprint != incomingFingerprint else { return }

        state = StateSnapshot(
            mode: normalizedMode,
            source: .json,
            confidence: confidence,
            timestamp: now,
            isStale: false
        )
        updateSequence &+= 1
        AppLogger.shared.log("🧭 [KindaVimState] Mode -> \(normalizedMode.displayName) (json)")
    }

    private func applyFallbackState() {
        if let karabinerMode = karabinerModeProvider() {
            applyState(
                mode: karabinerMode,
                source: .karabiner,
                confidence: .medium,
                timestamp: nowProvider(),
                isStale: false
            )
            return
        }

        rawModeValue = nil
        lastFreshSignalAt = nil
        applyState(
            mode: .unknown,
            source: .fallback,
            confidence: .low,
            timestamp: nowProvider(),
            isStale: true
        )
    }

    private func applyState(
        mode: Mode,
        source: Source,
        confidence: Confidence,
        timestamp: Date,
        isStale: Bool
    ) {
        let currentFingerprint = SnapshotFingerprint(
            mode: state.mode,
            source: state.source,
            confidence: state.confidence,
            isStale: state.isStale
        )
        let incomingFingerprint = SnapshotFingerprint(
            mode: mode,
            source: source,
            confidence: confidence,
            isStale: isStale
        )
        guard currentFingerprint != incomingFingerprint else { return }

        state = StateSnapshot(
            mode: mode,
            source: source,
            confidence: confidence,
            timestamp: timestamp,
            isStale: isStale
        )
        updateSequence &+= 1
    }

    private func startStaleTicker() {
        staleTickerTask?.cancel()
        staleTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.staleTickSeconds))
                await MainActor.run {
                    self?.evaluateStaleness()
                }
            }
        }
    }

    private func evaluateStaleness() {
        guard state.source != .fallback else { return }

        let isStaleNow: Bool
        if let lastFreshSignalAt {
            isStaleNow = nowProvider().timeIntervalSince(lastFreshSignalAt) >= Constants.staleAfterSeconds
        } else {
            isStaleNow = true
        }

        guard isStaleNow != state.isStale else { return }

        applyState(
            mode: state.mode,
            source: state.source,
            confidence: state.confidence,
            timestamp: state.timestamp,
            isStale: isStaleNow
        )
    }

    static func parseMode(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(EnvironmentPayload.self, from: data) else {
            return nil
        }
        return payload.mode
    }

    static func normalizedMode(from rawMode: String?) -> Mode {
        guard let rawMode else { return .unknown }

        let normalized = rawMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "insert":
            return .insert
        case "normal":
            return .normal
        case "visual", "visual_mode", "visual_line", "visual_block":
            return .visual
        default:
            return .unknown
        }
    }

    // MARK: - Test Hooks

    #if DEBUG
        func refreshForTesting() async {
            await refreshWithRetries(remainingRetries: Constants.retryCount)
        }

        func evaluateStalenessForTesting() {
            evaluateStaleness()
        }
    #endif
}
