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
        public let keyPath: PermissionSet
        public let kanata: PermissionSet
        public let timestamp: Date

        public init(keyPath: PermissionSet, kanata: PermissionSet, timestamp: Date) {
            self.keyPath = keyPath
            self.kanata = kanata
            self.timestamp = timestamp
        }

        /// System is ready when KeyPath has all required permissions
        /// NOTE: Kanata needs Input Monitoring permission to capture events for remapping.
        public var isSystemReady: Bool {
            keyPath.hasAllPermissions && kanata.inputMonitoring.isReady
        }

        /// Get the first blocking permission issue (user-facing error message)
        public var blockingIssue: String? {
            // Check KeyPath permissions (needed for UI functionality)
            if keyPath.accessibility.isBlocking {
                return
                    "KeyPath needs Accessibility permission - enable in System Settings > Privacy & Security > Accessibility"
            }

            if keyPath.inputMonitoring.isBlocking {
                return
                    "KeyPath needs Input Monitoring permission - enable in System Settings > Privacy & Security > Input Monitoring"
            }

            // Kanata must be able to capture events (Input Monitoring) for remapping to work.
            // We treat non-granted states as blocking because a running daemon without IM will not
            // see keyboard events reliably.
            if !kanata.inputMonitoring.isReady {
                return
                    "Kanata needs Input Monitoring permission - enable in System Settings > Privacy & Security > Input Monitoring"
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
        case low // Unknown/unavailable states (TCC fallback removed)

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

    // MARK: - Kanata Runtime Verification State

    private var hasObservedKanataRealKeyEvents = false

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

    /// Get current permission snapshot - THE authoritative permission state
    ///
    /// This is the ONLY method other components should call.
    /// No more direct PermissionService calls, no more guessing from logs.
    public func currentSnapshot() async -> Snapshot {
        // Fast-path for unit tests: avoid heavy OS calls and network timeouts
        if TestEnvironment.isRunningTests {
            // Honor cache semantics in tests to keep behavior deterministic
            if let cachedTime = lastSnapshotTime,
               let cached = lastSnapshot,
               Date().timeIntervalSince(cachedTime) < cacheTTL {
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
           Date().timeIntervalSince(cachedTime) < cacheTTL {
            AppLogger.shared.log(
                "🔮 [Oracle] Returning cached snapshot (age: \(String(format: "%.3f", Date().timeIntervalSince(cachedTime)))s)"
            )
            return cached
        }

        AppLogger.shared.log("🔮 [Oracle] Generating fresh permission snapshot")
        let start = Date()

        // Get KeyPath permissions (local, always authoritative)
        let keyPathSet = await checkKeyPathPermissions()

        // Get Kanata permissions (UDP primary, functional verification)
        let kanataSet = await checkKanataPermissions()

        let snapshot = Snapshot(
            keyPath: keyPathSet,
            kanata: kanataSet,
            timestamp: Date()
        )

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] Permission snapshot complete in \(String(format: "%.3f", duration))s")
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

    /// TCC-only Input Monitoring status for the active Kanata binary path.
    ///
    /// This is intentionally weaker than `currentSnapshot().kanata.inputMonitoring`:
    /// - `currentSnapshot()` applies functional verification (daemon logs + real key events) to
    ///   prevent “green but broken” states.
    /// - This method is used by the wizard’s “Fix” flow to detect whether the user granted
    ///   permission in System Settings, even if we have not yet observed key traffic.
    ///
    /// Use this only for UI flow control, not to declare the system “ready”.
    public func kanataInputMonitoringTCCStatus() async -> Status {
        let kanataPath = resolveKanataExecutablePath()
        let (_, tccIM) = await checkTCCForKanata(executablePath: kanataPath)
        return tccIM ?? .unknown
    }

    // MARK: - KeyPath Permission Detection (Always Authoritative)

    private func checkKeyPathPermissions() async -> PermissionSet {
        let start = Date()

        // For GUI apps, TCC stores permissions by bundle identifier (client_type=0)
        // NOT by executable path (client_type=1 is for CLI binaries like kanata)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
        let tccAX = await tccStatusByBundleID(bundleID, service: .accessibility)
        let tccIM = await tccStatusByBundleID(bundleID, service: .inputMonitoring)

        // Accessibility: if there is no TCC row, treat as denied (not listed => not granted)
        // AXIsProcessTrusted() can return stale/incorrect results, so we only use TCC as source of truth
        let accessibility: Status = {
            if let tccAX { return tccAX }
            // No TCC row = not listed in System Settings = denied
            AppLogger.shared.log("🔮 [Oracle] No TCC row for KeyPath Accessibility - treating as denied")
            return .denied
        }()

        // Input Monitoring: if there is no TCC row, treat as denied (not listed => not granted)
        let inputMonitoring: Status = {
            if let tccIM { return tccIM }
            // No TCC row = not listed in System Settings = denied
            AppLogger.shared.log("🔮 [Oracle] No TCC row for KeyPath Input Monitoring - treating as denied")
            return .denied
        }()

        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
            "🔮 [Oracle] KeyPath permission check completed in \(String(format: "%.3f", duration))s - AX: \(accessibility), IM: \(inputMonitoring)"
        )

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: "keypath.tcc",
            confidence: .high,
            timestamp: Date()
        )
    }

    // MARK: - Kanata Permission Detection (ADR-016: TCC Database Reading)

    //
    // WHY TCC DATABASE READING IS NECESSARY:
    // The wizard needs to guide users through Accessibility and Input Monitoring
    // permissions sequentially (one at a time). Without pre-flight detection:
    // - Starting Kanata triggers BOTH system permission dialogs simultaneously
    // - Users get confused by two overlapping prompts
    // - If they dismiss one, they don't know which permission is missing
    //
    // WHY ALTERNATIVES DON'T WORK:
    // - IOHIDCheckAccess() only works for the CALLING process (KeyPath), not Kanata
    // - PR #1759 to Kanata proved daemon-level checking fails (false negatives for root)
    // - Kanata maintainer has no macOS devices; upstream changes unlikely
    //
    // THIS IS ACCEPTABLE BECAUSE:
    // - Read-only operation (Apple's concern is TCC WRITES/bypasses)
    // - Graceful degradation: Falls back to .unknown if TCC read fails
    // - GUI context: Runs in user session, not daemon
    // - UX requirement: Sequential prompts are essential for comprehension

    // NOTE: ADR-016 documents an approved exception to AGENTS.md’s
    // “never read TCC directly” rule. We must read the TCC DB *read‑only*
    // to know Kanata’s AX/IM state without launching the root-managed
    // daemon (which cannot report its own TCC reliably). This keeps the
    // wizard’s sequential permission flow predictable. Do not remove
    // without revisiting ADR-016.
    private func checkKanataPermissions() async -> PermissionSet {
        let kanataPath = resolveKanataExecutablePath()

        // See ADR-016 for why TCC database reading is the correct approach here
        AppLogger.shared.log("🔮 [Oracle] Checking TCC database for Kanata (AX + IM) - see ADR-016")
        let (tccAX, tccIM) = await checkTCCForKanata(executablePath: kanataPath)

        let accessibility: Status = tccAX ?? .unknown
        var inputMonitoring: Status = tccIM ?? .unknown

        var sourceParts: [String] = []
        var confidence: Confidence = .high

        switch accessibility {
        case .granted, .denied:
            sourceParts.append("tcc-ax")
        default:
            break
        }
        switch inputMonitoring {
        case .granted, .denied:
            sourceParts.append("tcc-im")
        default:
            break
        }

        // Prevent false positives:
        // - Even if TCC indicates "granted", Kanata can still fail to open the keyboard at runtime.
        // - However, the wizard must be able to grant permissions *before* starting the Kanata
        //   service, so we only apply daemon-based verification when we have recent daemon logs.
        //
        // Result:
        // - If the daemon has logged recently: require real key events before reporting green.
        // - If the daemon is not running (or logs are stale/unavailable): trust the TCC grant so
        //   the user can proceed to start the service.
        if inputMonitoring.isReady {
            if let daemonIM = observeKanataDaemonInputMonitoringStatus() {
                switch daemonIM {
                case .denied:
                    AppLogger.shared.log(
                        "🔮 [Oracle] Kanata daemon logs indicate Input Monitoring failure; overriding TCC-granted to denied"
                    )
                    inputMonitoring = .denied
                    sourceParts.append("iohid-denied")
                case .granted:
                    sourceParts.append("daemon-ok")

                    // Require proof of real key events before reporting "granted".
                    if observeKanataHasRealKeyEvents() {
                        sourceParts.append("events")
                        inputMonitoring = .granted
                    } else {
                        inputMonitoring = .denied
                        sourceParts.append("no-events")
                    }
                case .unknown, .error:
                    sourceParts.append("daemon-unverifiable")
                    confidence = .low
                }
            } else {
                sourceParts.append("daemon-unverifiable")
                confidence = .low
            }
        }

        if sourceParts.isEmpty {
            sourceParts = ["unknown"]
            confidence = .low
        }

        let source = "kanata.\(sourceParts.joined(separator: "+"))"
        AppLogger.shared.log(
            "🔮 [Oracle] Kanata permissions (TCC): AX=\(accessibility), IM=\(inputMonitoring) via \(source)"
        )

        return PermissionSet(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            source: source,
            confidence: confidence,
            timestamp: Date()
        )
    }

    private func observeKanataDaemonInputMonitoringStatus() -> Status? {
        let stderrPath = KeyPathConstants.Logs.kanataStderr
        guard FileManager.default.fileExists(atPath: stderrPath) else { return nil }

        // Only trust this heuristic if the daemon has logged recently.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: stderrPath),
           let mod = attrs[FileAttributeKey.modificationDate] as? Date
        {
            if Date().timeIntervalSince(mod) > 60 {
                return nil
            }
        }

        // Read a small tail of stderr to keep this fast.
        // The file is root-owned but world-readable on normal installs.
        guard let tail = readFileTail(path: stderrPath, maxBytes: 8_192) else { return nil }

        // Be conservative: only treat this as an Input Monitoring failure when stderr clearly
        // indicates an IOHID permission denial. Other "not permitted"/"permission denied" lines
        // can be unrelated (e.g. file system), and should not flip IM red.
        if tail.localizedCaseInsensitiveContains("privilege violation") {
            return .denied
        }
        if tail.localizedCaseInsensitiveContains("IOHIDDeviceOpen error"),
           tail.localizedCaseInsensitiveContains("not permitted")
        {
            return .denied
        }

        return .granted
    }

    private func observeKanataHasRealKeyEvents() -> Bool {
        if hasObservedKanataRealKeyEvents { return true }

        let stdoutPath = KeyPathConstants.Logs.kanataStdout
        guard FileManager.default.fileExists(atPath: stdoutPath) else { return false }

        // Only trust this heuristic if the daemon has logged recently; otherwise a stale log tail
        // can cause "green but broken" after reinstalls or log rotation gaps.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: stdoutPath),
           let mod = attrs[FileAttributeKey.modificationDate] as? Date
        {
            if Date().timeIntervalSince(mod) > 60 {
                return false
            }
        }

        // Read a small tail for performance; this should include recent input.
        guard let tail = readFileTail(path: stdoutPath, maxBytes: 32_768) else { return false }

        // Kanata logs a periodic keepalive that looks like:
        //   process recv ev KeyEvent { code: KEY_RESERVED (0), value: WakeUp }
        // We only count it as "real input" if we see a KeyEvent that is not WakeUp.
        let lines = tail.split(separator: "\n")
        // Only consider the most recent lines; older input can linger in the tail and cause
        // false positives if the daemon is currently only emitting WakeUp keepalives.
        let recentLines = lines.suffix(250)
        for lineSub in recentLines {
            let line = String(lineSub)
            guard line.contains("process recv ev KeyEvent") else { continue }
            if line.contains("value: WakeUp") { continue }
            hasObservedKanataRealKeyEvents = true
            return true
        }

        return false
    }

    private func readFileTail(path: String, maxBytes: Int) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }

        do {
            let size = try fh.seekToEnd()
            let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
            try fh.seek(toOffset: start)
            let data = try fh.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Functional verification disabled in TCP-only mode
    /// TCP connectivity check would require protocol implementation
    private func checkKanataFunctionalStatus() async -> Status {
        AppLogger.shared.log("🔮 [Oracle] Functional status check disabled (TCP-only mode)")
        return .unknown
    }

    /// Additional timeout wrapper to prevent hanging
    private func withTimeout<T: Sendable>(
        seconds: Double, operation: @Sendable @escaping () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw KeyPathError.permission(
                    .privilegedOperationFailed(operation: "permission check", reason: "Operation timed out"))
            }

            guard let result = try await group.next() else {
                throw KeyPathError.permission(
                    .privilegedOperationFailed(operation: "permission check", reason: "Operation timed out"))
            }

            group.cancelAll()
            return result
        }
    }

    // MARK: - Utilities

    // Add this helper to prefer the active daemon path, falling back to bundled path
    private func resolveKanataExecutablePath() -> String {
        // Use the same “active” path as the daemon/service configuration.
        // If we probe a different binary (e.g. bundled vs system-installed),
        // users can “grant IM” successfully to the wrong path and Kanata still won’t work.
        return WizardSystemPaths.kanataActiveBinary
    }

    // Log granular permission transitions for observability
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
                "🔁 [Oracle] System readiness changed: \(old.isSystemReady) → \(new.isSystemReady)")
        }
    }

    // MARK: - TCC Database Fallback (Necessary to break chicken-and-egg problem)

    // TCC service names across macOS versions
    private enum TCCServiceName: String {
        case accessibility = "kTCCServiceAccessibility"
        case inputMonitoring = "kTCCServiceListenEvent"
    }

    // Attempt to determine TCC status for Kanata by executable path (best-effort).
    // Returns (.granted/.denied) if determinable, or nil if inconclusive/unreadable.
    // NOTE: This direct TCC access was previously removed as "bad practice" but is
    // necessary here to resolve the chicken-and-egg problem between permission verification
    // and service startup. This is a legitimate fallback when functional verification fails.
    private func checkTCCForKanata(executablePath: String) async -> (ax: Status?, im: Status?) {
        // Normalize path for TCC queries - convert development builds to installed paths
        let normalizedPath = normalizePathForTCC(executablePath)
        let ax = await tccStatus(forExecutable: normalizedPath, service: .accessibility)
        let im = await tccStatus(forExecutable: normalizedPath, service: .inputMonitoring)
        return (ax, im)
    }

    /// Normalize paths for TCC queries - convert development builds to installed paths
    /// Development builds use paths like /Volumes/.../build/KeyPath.app/...
    /// But TCC database has the installed path /Applications/KeyPath.app/...
    private func normalizePathForTCC(_ path: String) -> String {
        // If this is a development build path, convert to installed path
        if path.contains("/build/KeyPath.app/") || path.contains("/.build") {
            // Extract the relative path after KeyPath.app/
            if let range = path.range(of: "/KeyPath.app/") {
                let relativePath = String(path[range.upperBound...])
                let canonicalPath = "/Applications/KeyPath.app/\(relativePath)"
                AppLogger.shared.log("🔮 [Oracle] Normalized TCC path: \(path) → \(canonicalPath)")
                return canonicalPath
            }
        }
        return path
    }

    // Query TCC DB for a bundle identifier (client_type=0, used for GUI apps)
    // GUI apps like KeyPath are stored by bundle ID, not executable path
    private func tccStatusByBundleID(_ bundleID: String, service: TCCServiceName) async -> Status? {
        AppLogger.shared.log("🔍 [TCC] Checking \(service.rawValue) for bundle ID: \(bundleID)")
        let dbPaths = tccDatabaseCandidates()
        AppLogger.shared.log("🔍 [TCC] Will check databases: \(dbPaths)")
        for db in dbPaths {
            let exists = FileManager.default.fileExists(atPath: db)
            AppLogger.shared.log("🔍 [TCC] Database \(db) exists: \(exists)")
            guard exists else { continue }

            if let val = await queryTCCDatabaseByBundleID(
                dbPath: db, service: service.rawValue, bundleID: bundleID
            ) {
                AppLogger.shared.log("🔍 [TCC] Got value \(val) from \(db)")
                if val >= 2 || val == 1 {
                    AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(bundleID): GRANTED (auth_value=\(val))")
                    return .granted
                } else if val == 0 {
                    AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(bundleID): DENIED (auth_value=0)")
                    return .denied
                }
            } else {
                AppLogger.shared.log("🔍 [TCC] No entry in \(db), continuing to next database...")
            }
        }
        AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(bundleID): NO ROW FOUND in any database (returning nil)")
        return nil
    }

    // Query TCC DB for a specific executable path and service (client_type=1, used for CLI binaries)
    // Note: Requires Full Disk Access to read user's TCC.db; gracefully degrades to nil otherwise.
    // This is similar to how other system utilities (e.g., tccutil, privacy management tools) work.
    private func tccStatus(forExecutable execPath: String, service: TCCServiceName) async -> Status? {
        AppLogger.shared.log("🔍 [TCC] Checking \(service.rawValue) for: \(execPath)")
        let dbPaths = tccDatabaseCandidates()
        for db in dbPaths where FileManager.default.fileExists(atPath: db) {
            if let val = await queryTCCDatabase(
                dbPath: db, service: service.rawValue, executablePath: execPath
            ) {
                // Interpret result:
                // - Newer macOS: auth_value (2=Allow, 0=Deny or Prompt depending on auth_reason)
                // - Older macOS: allowed (1=Allow, 0=Not allowed)
                if val >= 2 || val == 1 {
                    AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(execPath): GRANTED (auth_value=\(val))")
                    return .granted
                } else if val == 0 {
                    // Only report denied if we positively read a 0 from TCC
                    AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(execPath): DENIED (auth_value=0)")
                    return .denied
                }
            }
        }
        // Inconclusive (no readable DB, no rows found, or unexpected schema) => nil
        AppLogger.shared.log("🔍 [TCC] \(service.rawValue) for \(execPath): NO ROW FOUND (returning nil)")
        return nil
    }

    // TCC DB locations to try (user first, then system)
    // Most permission grants are stored in the user's TCC database
    private func tccDatabaseCandidates() -> [String] {
        let user = "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db"
        let system = "/Library/Application Support/com.apple.TCC/TCC.db"
        return [user, system]
    }

    // Query TCC database by bundle identifier (client_type=0, used for GUI apps)
    // GUI apps are stored by bundle ID in TCC, not by executable path
    private func queryTCCDatabaseByBundleID(dbPath: String, service: String, bundleID: String) async
        -> Int? {
        let escService = escapeSQLiteLiteral(service)
        let escBundleID = escapeSQLiteLiteral(bundleID)

        AppLogger.shared.log("🔍 [Oracle] Querying TCC database: \(dbPath)")
        AppLogger.shared.log("🔍 [Oracle] Looking for: service=\(service), bundleID=\(bundleID)")

        // GUI apps use client_type=0 (bundle identifier) not client_type=1 (path)
        let queries = [
            "SELECT auth_value FROM access WHERE service='\(escService)' AND client='\(escBundleID)' AND client_type=0 ORDER BY auth_value DESC LIMIT 1;",
            "SELECT allowed FROM access WHERE service='\(escService)' AND client='\(escBundleID)' AND client_type=0 ORDER BY allowed DESC LIMIT 1;"
        ]

        for (index, sql) in queries.enumerated() {
            AppLogger.shared.log("🔍 [Oracle] Trying bundle ID query #\(index + 1)")
            if let out = await runSQLiteQuery(dbPath: dbPath, sql: sql, timeout: 0.4) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned: '\(trimmed)'")

                if trimmed.isEmpty {
                    if index == 0 {
                        AppLogger.shared.log("🔍 [Oracle] Query #1 returned empty result - stopping (no entry found)")
                        return nil
                    }
                }

                if let val = Int(trimmed) {
                    AppLogger.shared.log(
                        "🔍 [Oracle] TCC '\(service)' for \(bundleID) via \(dbPath): \(val)")
                    return val
                }
            } else {
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned nil (timeout or empty)")
            }
        }
        AppLogger.shared.log("🔍 [Oracle] TCC query failed for bundle ID \(bundleID) - no results found")
        return nil
    }

    // Run a minimal sqlite query with a short timeout.
    // Returns an integer meaning of auth_value/allowed, or nil if not determinable.
    // Uses sqlite3 CLI tool which is available on all macOS systems.
    // Approved read-only TCC lookup (see ADR-016). This must remain
    // best-effort, side-effect free, and resilient to failure (no FDA).
    private func queryTCCDatabase(dbPath: String, service: String, executablePath: String) async
        -> Int? {
        // The 'access' table schema varies. We try auth_value first, then allowed.
        // We check for client_type=1 (path) because Kanata is a CLI binary.
        let escService = escapeSQLiteLiteral(service)
        let escExec = escapeSQLiteLiteral(executablePath)

        AppLogger.shared.log("🔍 [Oracle] Querying TCC database: \(dbPath)")
        AppLogger.shared.log("🔍 [Oracle] Looking for: service=\(service), path=\(executablePath)")

        let queries = [
            "SELECT auth_value FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY auth_value DESC LIMIT 1;",
            "SELECT allowed FROM access WHERE service='\(escService)' AND client='\(escExec)' AND client_type=1 ORDER BY allowed DESC LIMIT 1;"
        ]

        for (index, sql) in queries.enumerated() {
            AppLogger.shared.log("🔍 [Oracle] Trying query #\(index + 1)")
            if let out = await runSQLiteQuery(dbPath: dbPath, sql: sql, timeout: 0.4) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned: '\(trimmed)'")

                // Check for empty result (valid query, but no rows found)
                if trimmed.isEmpty {
                    // If we got an empty result for the primary query (auth_value),
                    // it means the table/column exists but there's no entry for this app.
                    // We should STOP here and not try legacy queries that might fail on new macOS versions.
                    if index == 0 {
                        AppLogger.shared.log("🔍 [Oracle] Query #1 returned empty result - stopping (no entry found)")
                        return nil
                    }
                }

                if let val = Int(trimmed) {
                    AppLogger.shared.log(
                        "🔍 [Oracle] TCC '\(service)' for \(executablePath) via \(dbPath): \(val)")
                    return val
                }
            } else {
                AppLogger.shared.log("🔍 [Oracle] Query #\(index + 1) returned nil (timeout or empty)")
            }
        }
        AppLogger.shared.log("🔍 [Oracle] TCC query failed for \(executablePath) - no results found")
        return nil
    }

    // Escape single quotes in SQL string literals to prevent injection
    private func escapeSQLiteLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    // Execute sqlite3 query with timeout protection
    // This is a minimal, defensive implementation that avoids external dependencies
    private func runSQLiteQuery(dbPath: String, sql: String, timeout: Double) async -> String? {
        do {
            let result = try await SubprocessRunner.shared.run(
                "/usr/bin/sqlite3",
                args: [dbPath, sql],
                timeout: timeout
            )
            return result.stdout
        } catch {
            AppLogger.shared.log("❌ [Oracle] sqlite3 query failed: \(error)")
            return nil
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
