import Foundation
import KeyPathCore

// MARK: - Error Severity

/// Severity level for Kanata errors
enum KanataErrorSeverity: String, Sendable {
    case critical // System is failing - requires immediate attention
    case warning // Non-critical but should be investigated
    case info // Informational, normal operation

    var color: String {
        switch self {
        case .critical: "red"
        case .warning: "orange"
        case .info: "gray"
        }
    }

    var icon: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .info: "info.circle"
        }
    }
}

// MARK: - Error Entry

/// Represents a single error detected from Kanata stderr
struct KanataError: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let severity: KanataErrorSeverity
    let message: String
    let rawLine: String
    let pattern: String? // Which pattern matched this error

    init(
        timestamp: Date = Date(),
        severity: KanataErrorSeverity,
        message: String,
        rawLine: String,
        pattern: String? = nil
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.severity = severity
        self.message = message
        self.rawLine = rawLine
        self.pattern = pattern
    }

    /// User-friendly formatted timestamp
    var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Health Status

/// Overall health status based on recent errors
enum KanataHealthStatus: Sendable {
    case healthy
    case degraded(reason: String)
    case critical(reason: String)

    var severity: KanataErrorSeverity {
        switch self {
        case .healthy: .info
        case .degraded: .warning
        case .critical: .critical
        }
    }

    var icon: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .healthy: "green"
        case .degraded: "orange"
        case .critical: "red"
        }
    }
}

// MARK: - Error Pattern

/// Pattern for detecting critical errors in Kanata stderr
struct ErrorPattern {
    let regex: NSRegularExpression
    let severity: KanataErrorSeverity
    let userMessage: String
    let patternName: String
    let toastThreshold: Int // Show toast after this many occurrences

    init(pattern: String, severity: KanataErrorSeverity, userMessage: String, patternName: String, toastThreshold: Int = 1) {
        regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        self.severity = severity
        self.userMessage = userMessage
        self.patternName = patternName
        self.toastThreshold = toastThreshold
    }

    func matches(_ line: String) -> Bool {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }
}

// MARK: - Monitor Service

/// Monitors Kanata stderr for critical errors and health issues
@MainActor
final class KanataErrorMonitor: ObservableObject {
    static let shared = KanataErrorMonitor()

    // MARK: - Published State

    @Published private(set) var recentErrors: [KanataError] = []
    @Published private(set) var healthStatus: KanataHealthStatus = .healthy
    @Published private(set) var unreadErrorCount: Int = 0

    // MARK: - Configuration

    private let maxErrors = 100 // Ring buffer size
    private let stderrPath = "/var/log/com.keypath.kanata.stderr.log"
    private let monitoringInterval: TimeInterval = 2.0 // Check every 2 seconds
    private let patternCountWindow: TimeInterval = 60.0 // Count patterns over 1 minute window

    // MARK: - Critical Error Patterns

    private lazy var errorPatterns: [ErrorPattern] = [
        // Configuration parse errors - CRITICAL
        // These prevent Kanata from starting and cause crash loops
        ErrorPattern(
            pattern: "failed to parse file|Error in configuration|requires \\d+ to match defsrc",
            severity: .critical,
            userMessage: "Configuration file has errors - Kanata cannot start",
            patternName: "config_parse_error",
            toastThreshold: 1
        ),

        // File descriptor exhaustion - CRITICAL
        ErrorPattern(
            pattern: "Too many open files|file descriptor|Os \\{ code: 24",
            severity: .critical,
            userMessage: "File descriptor limit reached - system resources exhausted",
            patternName: "file_descriptor_exhaustion",
            toastThreshold: 1
        ),

        // Process crashes/panics - CRITICAL
        ErrorPattern(
            pattern: "panic|fatal|SIGABRT|SIGSEGV|thread.*panicked",
            severity: .critical,
            userMessage: "Kanata process crashed or panicked",
            patternName: "process_crash",
            toastThreshold: 1
        ),

        // VirtualHID driver issues - CRITICAL
        ErrorPattern(
            pattern: "VirtualHID.*failed|driver.*not found|kext.*error",
            severity: .critical,
            userMessage: "VirtualHID driver failure detected",
            patternName: "virtualhid_failure",
            toastThreshold: 1
        ),

        // Connection failures (if repeated) - WARNING
        ErrorPattern(
            pattern: "failed to clone stream|dropping connection.*clone failure",
            severity: .warning,
            userMessage: "Repeated connection failures detected",
            patternName: "connection_failure",
            toastThreshold: 10 // Only toast after 10 occurrences
        ),

        // Broken pipe (if repeated rapidly) - WARNING
        ErrorPattern(
            pattern: "Broken pipe.*os error 32",
            severity: .warning,
            userMessage: "Repeated broken pipe errors",
            patternName: "broken_pipe",
            toastThreshold: 5 // Toast after 5 occurrences
        ),

        // Permission denied - WARNING
        ErrorPattern(
            pattern: "permission denied|EPERM|operation not permitted",
            severity: .warning,
            userMessage: "Permission denied errors detected",
            patternName: "permission_denied",
            toastThreshold: 3
        )
    ]

    // MARK: - State Tracking

    private var lastFilePosition: UInt64 = 0
    private var monitoringTask: Task<Void, Never>?
    private var patternCounts: [String: [(Date, Int)]] = [:] // patternName -> [(timestamp, count)]
    private var lastToastTime: [String: Date] = [:] // patternName -> last toast time
    private let toastCooldown: TimeInterval = 300.0 // 5 minutes between toasts for same pattern

    private init() {
        AppLogger.shared.info("[ErrorMonitor] Initialized")
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard monitoringTask == nil else {
            AppLogger.shared.debug("[ErrorMonitor] Already monitoring")
            return
        }

        AppLogger.shared.info("[ErrorMonitor] Starting stderr monitoring")

        // Get current file size to start reading from end
        if let attrs = try? FileManager.default.attributesOfItem(atPath: stderrPath),
           let fileSize = attrs[.size] as? UInt64
        {
            lastFilePosition = fileSize
            AppLogger.shared.debug("[ErrorMonitor] Starting from file position: \(fileSize)")
        }

        monitoringTask = Task {
            while !Task.isCancelled {
                await checkForNewErrors()
                try? await Task.sleep(for: .seconds(monitoringInterval))
            }
        }
    }

    func stopMonitoring() {
        AppLogger.shared.info("[ErrorMonitor] Stopping stderr monitoring")
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Error Detection

    private func checkForNewErrors() async {
        guard let fileHandle = FileHandle(forReadingAtPath: stderrPath) else {
            AppLogger.shared.debug("[ErrorMonitor] Cannot open stderr log")
            return
        }

        defer { try? fileHandle.close() }

        // Seek to last position
        if #available(macOS 10.15.4, *) {
            try? fileHandle.seek(toOffset: lastFilePosition)
        } else {
            fileHandle.seek(toFileOffset: lastFilePosition)
        }

        // Read new data
        let newData = fileHandle.readDataToEndOfFile()
        guard !newData.isEmpty else { return }

        // Update position
        lastFilePosition += UInt64(newData.count)

        // Parse lines
        guard let content = String(data: newData, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            processErrorLine(line)
        }

        // Update health status based on recent errors
        updateHealthStatus()
    }

    private func processErrorLine(_ line: String) {
        // Skip non-error lines (only process ERROR level)
        guard line.contains("[ERROR]") else { return }

        // Check against all patterns
        for pattern in errorPatterns {
            if pattern.matches(line) {
                // Create error entry
                let error = KanataError(
                    severity: pattern.severity,
                    message: pattern.userMessage,
                    rawLine: line,
                    pattern: pattern.patternName
                )

                // Add to recent errors (ring buffer)
                recentErrors.insert(error, at: 0)
                if recentErrors.count > maxErrors {
                    recentErrors.removeLast()
                }

                // Increment unread count
                unreadErrorCount += 1

                // Track pattern count
                trackPatternOccurrence(pattern.patternName)

                // Check if we should show toast
                if shouldShowToast(for: pattern) {
                    showErrorToast(error)
                    lastToastTime[pattern.patternName] = Date()
                }

                AppLogger.shared.warn("[ErrorMonitor] Detected: \(pattern.patternName) - \(pattern.userMessage)")

                // Don't check other patterns for this line
                break
            }
        }
    }

    // MARK: - Pattern Tracking

    private func trackPatternOccurrence(_ patternName: String) {
        let now = Date()

        // Initialize if needed
        if patternCounts[patternName] == nil {
            patternCounts[patternName] = []
        }

        // Remove old occurrences outside the window
        patternCounts[patternName] = patternCounts[patternName]?.filter {
            now.timeIntervalSince($0.0) < patternCountWindow
        } ?? []

        // Add new occurrence
        let currentCount = (patternCounts[patternName]?.last?.1 ?? 0) + 1
        patternCounts[patternName]?.append((now, currentCount))
    }

    private func getPatternCount(_ patternName: String) -> Int {
        guard let counts = patternCounts[patternName] else { return 0 }
        let now = Date()
        return counts.filter { now.timeIntervalSince($0.0) < patternCountWindow }.count
    }

    private func shouldShowToast(for pattern: ErrorPattern) -> Bool {
        // Check count threshold
        let count = getPatternCount(pattern.patternName)
        guard count >= pattern.toastThreshold else { return false }

        // Check cooldown
        if let lastToast = lastToastTime[pattern.patternName] {
            let timeSinceLastToast = Date().timeIntervalSince(lastToast)
            guard timeSinceLastToast > toastCooldown else { return false }
        }

        return true
    }

    // MARK: - Health Status

    private func updateHealthStatus() {
        let now = Date()
        let recentWindow: TimeInterval = 60.0 // Last 1 minute

        let recentCritical = recentErrors.filter {
            $0.severity == .critical && now.timeIntervalSince($0.timestamp) < recentWindow
        }

        let recentWarnings = recentErrors.filter {
            $0.severity == .warning && now.timeIntervalSince($0.timestamp) < recentWindow
        }

        if !recentCritical.isEmpty {
            healthStatus = .critical(reason: recentCritical.first!.message)
        } else if recentWarnings.count >= 5 {
            healthStatus = .degraded(reason: "Multiple warnings detected")
        } else {
            healthStatus = .healthy
        }
    }

    // MARK: - Toast Notifications

    private func showErrorToast(_ error: KanataError) {
        let severityIcon = error.severity == .critical ? "⚠️" : "⚡"
        let message = "\(severityIcon) Kanata Error: \(error.message). Click health indicator to view diagnostics."

        Task { @MainActor in
            UserFeedbackService.show(message: message)
            // Also post notification to make health indicator more visible
            NotificationCenter.default.post(name: .kanataErrorDetected, object: error)

            // Post specific notification for config errors so UI can show modal
            if error.pattern == "config_parse_error" {
                NotificationCenter.default.post(
                    name: .kanataConfigErrorDetected,
                    object: error,
                    userInfo: ["rawLine": error.rawLine]
                )
            }
        }
    }

    // MARK: - Public Actions

    func markAllAsRead() {
        unreadErrorCount = 0
        AppLogger.shared.debug("[ErrorMonitor] Marked all errors as read")
    }

    func clearErrors() {
        recentErrors.removeAll()
        unreadErrorCount = 0
        healthStatus = .healthy
        AppLogger.shared.info("[ErrorMonitor] Cleared all errors")
    }

    func getRecentErrors(severity: KanataErrorSeverity? = nil, limit: Int = 50) -> [KanataError] {
        var errors = recentErrors
        if let severity {
            errors = errors.filter { $0.severity == severity }
        }
        return Array(errors.prefix(limit))
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showDiagnostics = Notification.Name("com.keypath.showDiagnostics")
    static let showErrorsTab = Notification.Name("com.keypath.showErrorsTab")
    static let kanataErrorDetected = Notification.Name("com.keypath.kanataErrorDetected")
    static let kanataConfigErrorDetected = Notification.Name("com.keypath.kanataConfigErrorDetected")
}
