import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import KeyPathCore

/// 🔮 THE ORACLE - Single source of truth for all permission detection in KeyPath
///
/// KeyPath runs Kanata in an unprivileged session worker launched from
/// KeyPath.app, so the app bundle is the only permission identity. A snapshot
/// therefore holds one model: KeyPath's Accessibility grant (shown to the user
/// as `AccessibilityPermissionPresentation.current.name`) and the running
/// runtime's own report of whether it can read and post keys.
public actor PermissionOracle {
    public static let shared = PermissionOracle()

    private var runtimeKeyAccessProvider: (@Sendable () async -> RuntimeKeyAccess?)?

    /// Bind the session runtime's capability report as the source of
    /// `Snapshot.runtimeKeyAccess`.
    public func configureRuntimeKeyAccessProvider(_ provider: @escaping @Sendable () async -> RuntimeKeyAccess?) {
        runtimeKeyAccessProvider = provider
        invalidateCache()
    }

    /// Passive capabilities of the calling process, as the session worker
    /// samples them for its report. Posting authorization alone can yield a
    /// modifying tap containing only flagsChanged, so it cannot establish
    /// keyboard input readiness by itself.
    public func currentProcessSessionCapabilities() -> ProcessCapabilities {
        Self.sessionCapabilities(
            accessibility: Self.checkKeyPathAccessibilityStatus(),
            eventListening: Self.rawEventListeningStatus(),
            eventPosting: Self.rawEventPostingStatus(), timestamp: Date()
        )
    }

    /// One passive sample supplies both effective policy and diagnostic raw facts.
    /// No permission request API, runtime startup, or database inspection occurs here.
    public func currentProcessSessionCapabilitySnapshot() -> SessionCapabilitySnapshot {
        Self.sampleSessionCapabilities(
            accessibility: Self.rawAccessibilityStatus,
            eventListening: Self.rawEventListeningStatus,
            eventPosting: Self.rawEventPostingStatus,
            verifyExternalAccess: Self.verifyExternalAccessibilityAccess
        )
    }

    public struct SessionCapabilitySnapshot: Sendable {
        public let effective: ProcessCapabilities
        public let rawPermissions: SessionRuntimeReport.RawPermissions
    }

    nonisolated static func sampleSessionCapabilities(
        accessibility: () -> Status, eventListening: () -> Status,
        eventPosting: () -> Status,
        verifyExternalAccess: () -> Bool = { false }
    ) -> SessionCapabilitySnapshot {
        let accessibility = accessibility()
        let eventListening = eventListening()
        let eventPosting = eventPosting()
        func raw(_ status: Status) -> SessionRuntimeReport.RawPermissions.Status {
            switch status {
            case .granted: .granted
            case .denied: .denied
            case .unknown: .unknown
            case .error: .error
            }
        }
        return SessionCapabilitySnapshot(
            effective: sessionCapabilities(
                accessibility: accessibility == .denied
                    ? resolveAccessibilityStatus(trusted: false, verifyExternalAccess: verifyExternalAccess)
                    : accessibility,
                eventListening: eventListening, eventPosting: eventPosting, timestamp: Date()
            ),
            rawPermissions: .init(
                accessibility: raw(accessibility), eventListening: raw(eventListening),
                eventPosting: raw(eventPosting)
            )
        )
    }

    /// Key access is the listen grant when present, else the posting grant: a
    /// modifying tap works with posting access alone on macOS 27.
    nonisolated static func sessionCapabilities(
        accessibility: Status, eventListening: Status, eventPosting: Status, timestamp: Date
    ) -> ProcessCapabilities {
        ProcessCapabilities(
            accessibility: accessibility,
            keyAccess: eventListening.isReady ? eventPosting : eventListening,
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

    /// What one process can do, sampled with passive Apple APIs. The session
    /// worker samples this about itself and writes it into its report.
    public struct ProcessCapabilities: Sendable {
        public let accessibility: Status
        /// Whether the process can read and post keys through a modifying tap.
        public let keyAccess: Status
        public let source: String
        public let confidence: Confidence
        public let timestamp: Date

        public init(
            accessibility: Status, keyAccess: Status, source: String, confidence: Confidence,
            timestamp: Date
        ) {
            self.accessibility = accessibility
            self.keyAccess = keyAccess
            self.source = source
            self.confidence = confidence
            self.timestamp = timestamp
        }

        public var isReady: Bool {
            accessibility.isReady && keyAccess.isReady
        }
    }

    /// The running session runtime's own report of whether it can remap keys.
    /// `status` is `.unknown` with low confidence until a runtime has reported.
    public struct RuntimeKeyAccess: Sendable {
        public let status: Status
        public let source: String
        public let confidence: Confidence
        public let timestamp: Date

        public init(status: Status, source: String, confidence: Confidence, timestamp: Date) {
            self.status = status
            self.source = source
            self.confidence = confidence
            self.timestamp = timestamp
        }

        /// Combines a runtime report's Accessibility and key-access facts into
        /// one status: a runtime without Accessibility cannot remap either.
        public init(
            runtimeAccessibility: Bool, keyAccess: Bool, source: String, timestamp: Date
        ) {
            self.init(
                status: runtimeAccessibility && keyAccess ? .granted : .denied,
                source: source, confidence: .high, timestamp: timestamp
            )
        }

        public static func notReported(timestamp: Date = Date()) -> RuntimeKeyAccess {
            RuntimeKeyAccess(
                status: .unknown, source: "session-runtime.not-reported", confidence: .low,
                timestamp: timestamp
            )
        }
    }

    public struct Snapshot: Sendable {
        /// KeyPath.app's own Accessibility grant (Device Control and Data Access on macOS 27).
        public let accessibility: Status
        /// The session runtime's report of whether it can read and post keys.
        public let runtimeKeyAccess: RuntimeKeyAccess
        public let timestamp: Date

        public init(accessibility: Status, runtimeKeyAccess: RuntimeKeyAccess, timestamp: Date) {
            self.accessibility = accessibility
            self.runtimeKeyAccess = runtimeKeyAccess
            self.timestamp = timestamp
        }

        /// Remapping works when KeyPath has Accessibility and the runtime confirms key access.
        public var isSystemReady: Bool {
            accessibility.isReady && runtimeKeyAccess.status.isReady
        }

        /// The first blocking permission issue, as user-facing guidance.
        public var blockingIssue: String? {
            if accessibility.isBlocking {
                return Self.sessionBlockingGuidance(accessibilityBlocking: true, presentation: .current)
            }
            if runtimeKeyAccess.status.isBlocking {
                return Self.sessionBlockingGuidance(accessibilityBlocking: false, presentation: .current)
            }
            return nil
        }

        /// What to tell the user when remapping lacks access.
        /// Device Control and Data Access covers reading keys, so once it is on
        /// the runtime only needs a fresh launch.
        public static func sessionBlockingGuidance(
            accessibilityBlocking: Bool, presentation: AccessibilityPermissionPresentation
        ) -> String {
            if accessibilityBlocking {
                return "Enable KeyPath in \(presentation.name) in System Settings, then quit and reopen KeyPath."
            }
            return "Quit and reopen KeyPath so it can use \(presentation.name)."
        }

        /// Diagnostic information for troubleshooting
        public var diagnosticSummary: String {
            """
            🔮 Permission Oracle Snapshot (\(String(format: "%.3f", Date().timeIntervalSince(timestamp)))s ago)

            • KeyPath \(AccessibilityPermissionPresentation.current.name): \(accessibility)
            • Runtime key access [\(runtimeKeyAccess.source), \(runtimeKeyAccess.confidence)]: \(runtimeKeyAccess.status)

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

    /// Advanced by every invalidation. A computation that began before an
    /// invalidation describes the old state: it is neither shared with later
    /// callers nor written to the cache.
    private var cacheGeneration: UInt64 = 0

    #if DEBUG
        /// Replaces the OS permission reads so tests can exercise caching and
        /// coalescing, including a computation suspended across an invalidation.
        private var testSnapshotGenerator: (@Sendable () async -> Snapshot)?

        public func setTestSnapshotGenerator(_ generator: (@Sendable () async -> Snapshot)?) {
            testSnapshotGenerator = generator
            invalidateCache()
        }
    #endif

    /// Cache TTL for sub-2-second goal
    private let cacheTTL: TimeInterval = 1.5

    public init() {
        AppLogger.shared.log("🔮 [Oracle] Permission Oracle initialized - ending the chaos!")
    }

    // MARK: - 🎯 THE ONLY PUBLIC API

    /// Force cache invalidation - useful after UDP configuration changes
    public func invalidateCache() {
        AppLogger.shared.log("🔮 [Oracle] Cache invalidated - next check will be fresh")
        cacheGeneration &+= 1
        lastSnapshot = nil
        lastSnapshotTime = nil
        inFlightSnapshot = nil
    }

    /// Whether this process may create a listen-only event tap. Non-prompting.
    /// Observers prefer such a tap and otherwise fall back to a pass-through one,
    /// because requesting a listen-only tap without access makes macOS prompt for
    /// a separate permission KeyPath does not otherwise need.
    public nonisolated func keyPathCanCreateListenOnlyTap() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Input Monitoring for this process, non-prompting. Only opt-in keyboard
    /// attribution needs it (ADR-048); nothing else asks for it.
    public nonisolated func keyPathInputMonitoringStatus() -> Status {
        Self.rawEventListeningStatus()
    }

    /// Shows the Input Monitoring prompt once. Call it only when the person turns
    /// on keyboard attribution, never at setup (ADR-047, ADR-048).
    public nonisolated func requestKeyPathInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
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
        if TestEnvironment.isRunningTests, !hasTestSnapshotGenerator {
            // Honor cache semantics in tests to keep behavior deterministic
            if let cachedTime = lastSnapshotTime,
               let cached = lastSnapshot,
               Date().timeIntervalSince(cachedTime) < cacheTTL
            {
                AppLogger.shared.log("🔮 [Oracle] (Test) Returning cached snapshot")
                return cached
            }

            let now = Date()
            let snap = Snapshot(
                accessibility: .unknown,
                runtimeKeyAccess: RuntimeKeyAccess(
                    status: .unknown, source: "test.placeholder", confidence: .low, timestamp: now
                ),
                timestamp: now
            )
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
        let generation = cacheGeneration
        let task = Task { await self.generateSnapshot(generation: generation) }
        inFlightSnapshot = task
        let result = await task.value
        if generation == cacheGeneration { inFlightSnapshot = nil }
        return result
    }

    private var hasTestSnapshotGenerator: Bool {
        #if DEBUG
            testSnapshotGenerator != nil
        #else
            false
        #endif
    }

    /// Generate a fresh permission snapshot. Called by `currentSnapshot()` when
    /// the cache is stale and no in-flight computation exists.
    private func generateSnapshot(generation: UInt64) async -> Snapshot {
        #if DEBUG
            if let testSnapshotGenerator {
                let snapshot = await testSnapshotGenerator()
                cache(snapshot, generation: generation)
                return snapshot
            }
        #endif
        AppLogger.shared.log("🔮 [Oracle] Generating fresh permission snapshot")
        let start = Date()

        let accessibility = checkKeyPathAccessibility()
        let runtimeKeyAccess = await runtimeKeyAccessProvider?() ?? .notReported()
        let snapshot = Snapshot(
            accessibility: accessibility, runtimeKeyAccess: runtimeKeyAccess, timestamp: Date()
        )

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] Permission snapshot complete in \(String(format: "%.3f", duration))s"
        )
        AppLogger.shared.log("🔮 [Oracle] System ready: \(snapshot.isSystemReady)")
        if let issue = snapshot.blockingIssue {
            AppLogger.shared.log("🔮 [Oracle] Blocking issue: \(issue)")
        }

        // Log transitions for Accessibility and runtime key access
        if let previous = lastSnapshot {
            logPermissionTransitions(from: previous, to: snapshot)
        }

        cache(snapshot, generation: generation)
        return snapshot
    }

    private func cache(_ snapshot: Snapshot, generation: UInt64) {
        guard generation == cacheGeneration else {
            AppLogger.shared.log("🔮 [Oracle] Discarding snapshot computed before cache invalidation")
            return
        }
        lastSnapshot = snapshot
        lastSnapshotTime = snapshot.timestamp
    }

    /// Force refresh (bypass cache) - use after permission changes
    public func forceRefresh() async -> Snapshot {
        AppLogger.shared.log("🔮 [Oracle] Forcing permission refresh (cache invalidated)")
        invalidateCache()
        return await currentSnapshot()
    }

    // MARK: - KeyPath Permission Detection

    /// KeyPath.app's own Accessibility grant, via the non-prompting
    /// `AXIsProcessTrusted()` (ADR-006). An inconclusive result stays unknown;
    /// permission detection never reads protected databases.
    private func checkKeyPathAccessibility() -> Status {
        let start = Date()
        let accessibility = Self.checkKeyPathAccessibilityStatus()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] KeyPath permission check completed in \(String(format: "%.3f", duration))s - AX: \(accessibility), raw AX trust: \(Self.rawAccessibilityStatus())"
        )
        return accessibility
    }

    private nonisolated static func rawAccessibilityStatus() -> Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    private nonisolated static func checkKeyPathAccessibilityStatus() -> Status {
        resolveAccessibilityStatus(
            trusted: AXIsProcessTrusted(), verifyExternalAccess: verifyExternalAccessibilityAccess
        )
    }

    /// A successful read from Finder proves cross-process AX access when macOS
    /// retains a stale negative trust answer. Finder is independent of focus;
    /// probing our own UI could succeed without permission. No user content is read.
    private nonisolated static func verifyExternalAccessibilityAccess() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first, finder.processIdentifier != getpid() else { return false }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXRoleAttribute as CFString, &role
        ) == .success, let role, CFGetTypeID(role) == CFStringGetTypeID()
        else { return false }
        return (role as? String) == (kAXApplicationRole as String)
    }

    nonisolated static func resolveAccessibilityStatus(
        trusted: Bool, verifyExternalAccess: () -> Bool
    ) -> Status {
        if trusted { return .granted }
        return verifyExternalAccess() ? .granted : .denied
    }

    /// Raw listen-event authorization for this process. Non-prompting; only the
    /// session worker's capability sample uses it, as one input to key access.
    private nonisolated static func rawEventListeningStatus() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    /// Raw posting authorization for this process. Non-prompting.
    private nonisolated static func rawEventPostingStatus() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypePostEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
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

        logChange(subject: "KeyPath Accessibility", old: old.accessibility, new: new.accessibility)
        logChange(
            subject: "Runtime key access", old: old.runtimeKeyAccess.status, new: new.runtimeKeyAccess.status
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
