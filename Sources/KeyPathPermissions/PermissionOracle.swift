import ApplicationServices
import Foundation
import IOKit.hid
import KeyPathCore

// (Removed deprecated OracleError - now using KeyPathError directly)

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// This actor eliminates the chaos of multiple conflicting permission detection methods.
/// It provides deterministic, hierarchical permission checking with clear source precedence.
public actor PermissionOracle {
    public static let shared = PermissionOracle()

    private var sessionCapabilityProvider: (@Sendable () async -> PermissionSet?)?

    public func configureSessionCapabilityProvider(_ provider: @escaping @Sendable () async -> PermissionSet?) {
        sessionCapabilityProvider = provider
        lastSnapshot = nil
    }

    /// Raw non-prompting AX and Input Monitoring facts for this process.
    public func currentProcessCapabilities() -> PermissionSet {
        PermissionSet(
            accessibility: Self.checkKeyPathAccessibilityStatus(),
            inputMonitoring: Self.checkKeyPathInputMonitoringStatus(),
            source: "current-process.apple-api", confidence: .high, timestamp: Date()
        )
    }

    /// Passive authorization checks for keyboard capture and synthesized output.
    /// Posting authorization alone can yield a modifying tap containing only
    /// flagsChanged, so it cannot establish keyboard input readiness.
    public func currentProcessSessionCapabilities() -> PermissionSet {
        Self.sessionPermissionSet(
            accessibility: Self.checkKeyPathAccessibilityStatus(),
            eventListening: Self.checkKeyPathInputMonitoringStatus(),
            eventPosting: currentProcessEventPostingStatus(), timestamp: Date()
        )
    }

    /// Raw posting authorization, kept separate from combined session readiness.
    public func currentProcessEventPostingStatus() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypePostEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    nonisolated static func sessionPermissionSet(
        accessibility: Status, eventListening: Status, eventPosting: Status, timestamp: Date
    ) -> PermissionSet {
        PermissionSet(
            accessibility: accessibility,
            inputMonitoring: eventListening.isReady ? eventPosting : eventListening,
            source: "current-process.apple-api.listen-and-post-event",
            confidence: .high, timestamp: timestamp
        )
    }

    // MARK: - Core Types

    public enum Status: Equatable, Sendable {
        case granted
        case denied
        case error(String)
        case unknown

        public var isReady: Bool {
            if case .granted = self { return true }
            return false
        }

        public var isBlocking: Bool {
            if case .denied = self { return true }
            if case .error = self { return true }
            return false
        }

        /// Permission is missing/not granted (includes .unknown, .denied, .error)
        /// Use this for wizard checks - treats .unknown as missing since the permission
        /// hasn't been explicitly granted yet.
        public var isMissing: Bool {
            if case .granted = self { return false }
            return true // .unknown, .denied, .error all count as missing
        }
    }

    public struct PermissionSet: Sendable {
        public let accessibility: Status
        public let inputMonitoring: Status
        public let source: String
        public let confidence: Confidence
        public let timestamp: Date

        public init(
            accessibility: Status, inputMonitoring: Status, source: String, confidence: Confidence,
            timestamp: Date
        ) {
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
            self.source = source
            self.confidence = confidence
            self.timestamp = timestamp
        }

        public var hasAllPermissions: Bool {
            accessibility.isReady && inputMonitoring.isReady
        }
    }

    public struct Snapshot: Sendable {
        public let backend: KanataRuntimeBackend
        public let keyPath: PermissionSet
        public let kanata: PermissionSet
        public let timestamp: Date

        public init(keyPath: PermissionSet, kanata: PermissionSet, timestamp: Date, backend: KanataRuntimeBackend = .selected) {
            self.backend = backend
            self.keyPath = keyPath
            self.kanata = kanata
            self.timestamp = timestamp
        }

        /// System is ready when both apps have all required permissions
        public var isSystemReady: Bool {
            // Kanata's AX + IM are the hard requirement for remapping to work.
            // KeyPath's own IM (now queried authoritatively via IOHIDCheckAccess —
            // see checkKeyPathPermissions) powers the live keyboard overlay, not
            // core remapping, so it is surfaced via blockingIssue but intentionally
            // kept out of this hard readiness gate to avoid flipping a
            // working-remap system to "not ready".
            keyPath.accessibility.isReady && kanata.hasAllPermissions
        }

        /// Get the first blocking permission issue (user-facing error message)
        public var blockingIssue: String? {
            // KeyPath's own Accessibility is required (event posting / overlay).
            if keyPath.accessibility.isBlocking {
                return
                    "KeyPath needs Accessibility permission - enable in System Settings > Privacy & Security > Accessibility"
            }

            // NOTE: KeyPath's OWN Input Monitoring is intentionally NOT a blocking
            // issue. It powers only seize-mode features (the live overlay / key
            // recording), never core remapping — which is kanata's job (see
            // CompositionRoot's HID-monitor comment and isSystemReady). This must
            // stay consistent with isSystemReady, which also excludes it: before
            // IOHIDCheckAccess made this signal authoritative (#931) it was
            // perpetually .unknown and never blocked; treating it as blocking now
            // would newly pop the wizard for a working-remap system. The wizard's
            // Input Monitoring page still surfaces it per-row for users who want
            // the overlay.

            // Kanata's permissions ARE required for remapping.
            if kanata.accessibility.isBlocking || kanata.inputMonitoring.isBlocking {
                if backend == .session {
                    return "Enable Accessibility and Input Monitoring for KeyPath in System Settings, then quit and reopen KeyPath."
                }
                return
                    "Kanata needs permissions - use the Installation Wizard to grant Accessibility and Input Monitoring"
            }

            return nil
        }

        /// Diagnostic information for troubleshooting
        public var diagnosticSummary: String {
            """
            🔮 Permission Oracle Snapshot (\(String(format: "%.3f", Date().timeIntervalSince(timestamp)))s ago)

            KeyPath [\(keyPath.source), \(keyPath.confidence)]:
              • Accessibility: \(keyPath.accessibility)
              • Input Monitoring: \(keyPath.inputMonitoring)

            Kanata [\(kanata.source), \(kanata.confidence)]:
              • Accessibility: \(kanata.accessibility)
              • Input Monitoring: \(kanata.inputMonitoring)

            System Ready: \(isSystemReady)
            """
        }
    }

    public enum Confidence: Equatable, CustomStringConvertible, Sendable {
        case high // UDP API, Official Apple APIs
        case low // Unknown or unavailable permission evidence

        public var description: String {
            switch self {
            case .high: "high"
            case .low: "low"
            }
        }
    }

    // MARK: - State Management

    private var lastSnapshot: Snapshot?
    private var lastSnapshotTime: Date?

    /// In-flight snapshot task for request coalescing.
    /// Prevents concurrent callers from duplicating permission checks.
    private var inFlightSnapshot: Task<Snapshot, Never>?

    /// Cache TTL for sub-2-second goal
    private let cacheTTL: TimeInterval = 1.5

    public init() {
        AppLogger.shared.log("🔮 [Oracle] Permission Oracle initialized - ending the chaos!")
    }

    // MARK: - 🎯 THE ONLY PUBLIC API

    /// Force cache invalidation - useful after UDP configuration changes
    public func invalidateCache() {
        AppLogger.shared.log("🔮 [Oracle] Cache invalidated - next check will be fresh")
        lastSnapshot = nil
        lastSnapshotTime = nil
    }

    /// Synchronous, non-prompting Accessibility status for call sites that cannot
    /// await a full permission snapshot.
    public nonisolated func keyPathAccessibilityStatus() -> Status {
        Self.checkKeyPathAccessibilityStatus()
    }

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    ///
    /// Concurrent callers are coalesced: if a snapshot is already being computed,
    /// subsequent callers wait for the same result.
    public func currentSnapshot() async -> Snapshot {
        // Fast-path for unit tests: avoid heavy OS calls and network timeouts
        if TestEnvironment.isRunningTests {
            // Honor cache semantics in tests to keep behavior deterministic
            if let cachedTime = lastSnapshotTime,
               let cached = lastSnapshot,
               Date().timeIntervalSince(cachedTime) < cacheTTL
            {
                AppLogger.shared.log("🔮 [Oracle] (Test) Returning cached snapshot")
                return cached
            }

            let now = Date()
            let placeholder = PermissionSet(
                accessibility: .unknown,
                inputMonitoring: .unknown,
                source: "test.placeholder",
                confidence: .low,
                timestamp: now
            )
            let snap = Snapshot(keyPath: placeholder, kanata: placeholder, timestamp: now)
            lastSnapshot = snap
            lastSnapshotTime = now
            AppLogger.shared.log("🔮 [Oracle] Test mode snapshot generated (non-blocking)")
            return snap
        }

        // Return cached result if fresh
        if let cachedTime = lastSnapshotTime,
           let cached = lastSnapshot,
           Date().timeIntervalSince(cachedTime) < cacheTTL
        {
            AppLogger.shared.log(
                "🔮 [Oracle] Returning cached snapshot (age: \(String(format: "%.3f", Date().timeIntervalSince(cachedTime)))s)"
            )
            return cached
        }

        // Coalesce: reuse in-flight computation instead of starting a parallel one
        if let inflight = inFlightSnapshot {
            AppLogger.shared.log("🔮 [Oracle] Coalescing with in-flight snapshot request")
            return await inflight.value
        }

        // Start new computation
        let task = Task { await self.generateSnapshot() }
        inFlightSnapshot = task
        let result = await task.value
        inFlightSnapshot = nil
        return result
    }

    /// Generate a fresh permission snapshot. Called by `currentSnapshot()` when
    /// the cache is stale and no in-flight computation exists.
    private func generateSnapshot() async -> Snapshot {
        AppLogger.shared.log("🔮 [Oracle] Generating fresh permission snapshot")
        let start = Date()

        // Get KeyPath permissions (local, always authoritative)
        let keyPathSet = await checkKeyPathPermissions()

        // Use effective session-process facts, or retain legacy-process uncertainty.
        let backend = KanataRuntimeBackend.selected
        let kanataSet: PermissionSet = if backend == .session {
            await sessionCapabilityProvider?() ?? PermissionSet(
                accessibility: .unknown, inputMonitoring: .unknown,
                source: "session-process-not-verified", confidence: .low, timestamp: Date()
            )
        } else {
            await checkKanataPermissions()
        }

        let snapshot = Snapshot(
            keyPath: keyPathSet,
            kanata: kanataSet,
            timestamp: Date(), backend: backend
        )

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] Permission snapshot complete in \(String(format: "%.3f", duration))s"
        )
        AppLogger.shared.log("🔮 [Oracle] System ready: \(snapshot.isSystemReady)")
        if let issue = snapshot.blockingIssue {
            AppLogger.shared.log("🔮 [Oracle] Blocking issue: \(issue)")
        }

        // Log transitions for AX/IM across KeyPath and Kanata
        if let previous = lastSnapshot {
            logPermissionTransitions(from: previous, to: snapshot)
        }

        // Cache the result
        lastSnapshot = snapshot
        lastSnapshotTime = snapshot.timestamp

        return snapshot
    }

    /// Force refresh (bypass cache) - use after permission changes
    public func forceRefresh() async -> Snapshot {
        AppLogger.shared.log("🔮 [Oracle] Forcing permission refresh (cache invalidated)")
        lastSnapshot = nil
        lastSnapshotTime = nil
        return await currentSnapshot()
    }

    // MARK: - KeyPath Permission Detection (Always Authoritative)

    /// Check KeyPath's own permissions using non-prompting Apple APIs, per ADR-006.
    ///
    /// Both APIs used here are passive (they never show a system prompt — only
    /// `IOHIDRequestAccess()`, used exclusively by the wizard's
    /// `PermissionRequestService`, prompts):
    /// - `AXIsProcessTrusted()` for Accessibility
    /// - `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` for Input Monitoring
    ///
    /// Apple APIs are authoritative for this process. An inconclusive result
    /// stays unknown; permission detection never reads protected databases.
    private func checkKeyPathPermissions() async -> PermissionSet {
        let start = Date()

        // Accessibility check via official Apple API (no prompt)
        let accessibility = Self.checkKeyPathAccessibilityStatus()

        let resolved = Self.resolveKeyPathInputMonitoring(apiStatus: Self.checkKeyPathInputMonitoringStatus())
        let inputMonitoring = resolved.status
        let source = resolved.source
        let confidence = resolved.confidence

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] KeyPath permission check completed in \(String(format: "%.3f", duration))s - AX: \(accessibility), IM: \(inputMonitoring) (source: \(source))"
        )

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: source,
            confidence: confidence,
            timestamp: Date()
        )
    }

    private nonisolated static func checkKeyPathAccessibilityStatus() -> Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Input Monitoring status for KeyPath's own process via IOHIDCheckAccess.
    ///
    /// This is a non-prompting query (it returns the current access level; only
    /// `IOHIDRequestAccess()` shows the system dialog) and it is scoped to the
    /// calling process, so it is authoritative only for KeyPath.app — never for
    /// another process such as the legacy kanata-launcher.
    private nonisolated static func checkKeyPathInputMonitoringStatus() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    /// A passive Apple-API fact never implies a grant for another process.
    nonisolated static func resolveKeyPathInputMonitoring(
        apiStatus: Status
    ) -> (status: Status, source: String, confidence: Confidence) {
        switch apiStatus {
        case .granted, .denied:
            return (apiStatus, "keypath.ax-api+im-api", .high)
        case .unknown, .error:
            return (.unknown, "keypath.ax-api-only", .low)
        }
    }

    /// The legacy daemon cannot be checked through this process's Apple APIs.
    /// Retain uncertainty rather than infer a grant from files or runtime state.
    nonisolated static func legacyKanataPermissions(timestamp: Date) -> PermissionSet {
        PermissionSet(
            accessibility: .unknown, inputMonitoring: .unknown,
            source: "kanata.unknown", confidence: .low, timestamp: timestamp
        )
    }

    private func checkKanataPermissions() async -> PermissionSet {
        Self.legacyKanataPermissions(timestamp: Date())
    }

    /// Log granular permission transitions for observability
    private func logPermissionTransitions(from old: Snapshot, to new: Snapshot) {
        func logChange(subject: String, old: Status, new: Status) {
            guard old != new else { return }
            AppLogger.shared.log("🔄 [Oracle] Permission change: \(subject): \(old) → \(new)")
            switch new {
            case .granted:
                AppLogger.shared.log("🟢 [Oracle] \(subject) granted")
            case .denied:
                AppLogger.shared.log("🔴 [Oracle] \(subject) denied")
            case let .error(msg):
                AppLogger.shared.log("⚠️ [Oracle] \(subject) error: \(msg)")
            case .unknown:
                AppLogger.shared.log("ℹ️ [Oracle] \(subject) unknown")
            }
        }

        // KeyPath
        logChange(
            subject: "KeyPath Accessibility", old: old.keyPath.accessibility,
            new: new.keyPath.accessibility
        )
        logChange(
            subject: "KeyPath Input Monitoring", old: old.keyPath.inputMonitoring,
            new: new.keyPath.inputMonitoring
        )

        // Kanata
        logChange(
            subject: "Kanata Accessibility", old: old.kanata.accessibility, new: new.kanata.accessibility
        )
        logChange(
            subject: "Kanata Input Monitoring", old: old.kanata.inputMonitoring,
            new: new.kanata.inputMonitoring
        )

        if old.isSystemReady != new.isSystemReady {
            AppLogger.shared.log(
                "🔁 [Oracle] System readiness changed: \(old.isSystemReady) → \(new.isSystemReady)"
            )
        }
    }
}

// MARK: - Status Display Helpers

public extension PermissionOracle.Status {
    var description: String {
        switch self {
        case .granted: "granted"
        case .denied: "denied"
        case let .error(msg): "error(\(msg))"
        case .unknown: "unknown"
        }
    }
}
