import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

/// Protocol for managing diagnostics, health monitoring, and log monitoring
@preconcurrency
protocol DiagnosticsManaging: Sendable {
    /// Add a diagnostic
    func addDiagnostic(_ diagnostic: KanataDiagnostic)

    /// Get all current diagnostics
    func getDiagnostics() -> [KanataDiagnostic]

    /// Clear all diagnostics
    func clearDiagnostics()

    /// Start log monitoring
    func startLogMonitoring()

    /// Stop log monitoring
    func stopLogMonitoring()

    /// Check service health
    func checkHealth(tcpPort: Int) async -> ServiceHealthStatus

    /// Diagnose Kanata failure
    func diagnoseFailure(exitCode: Int32, output: String) -> [KanataDiagnostic]

    /// Get system diagnostics
    func getSystemDiagnostics(engineClient: EngineClient?) async -> [KanataDiagnostic]
}

/// Manages diagnostics, health monitoring, and log monitoring
@MainActor
final class DiagnosticsManager: @preconcurrency DiagnosticsManaging {
    private var diagnostics: [KanataDiagnostic] = []
    private let diagnosticsService: DiagnosticsServiceProtocol
    private let kanataService: KanataService

    private var logMonitorTask: Task<Void, Never>?

    init(
        diagnosticsService: DiagnosticsServiceProtocol,
        kanataService: KanataService
    ) {
        self.diagnosticsService = diagnosticsService
        self.kanataService = kanataService
    }

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnostics.append(diagnostic)
        AppLogger.shared.log(
            "\(diagnostic.severity.emoji) [DiagnosticsManager] \(diagnostic.title): \(diagnostic.description)"
        )

        // Keep only last 50 diagnostics to prevent memory bloat
        if diagnostics.count > 50 {
            diagnostics.removeFirst(diagnostics.count - 50)
        }
    }

    func getDiagnostics() -> [KanataDiagnostic] {
        diagnostics
    }

    func clearDiagnostics() {
        diagnostics.removeAll()
    }

    func startLogMonitoring() {
        // Cancel any existing monitoring
        logMonitorTask?.cancel()

        logMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let logPath = WizardSystemPaths.kanataLogFile
            guard FileManager.default.fileExists(atPath: logPath) else {
                AppLogger.shared.log("⚠️ [DiagnosticsManager] Kanata log file not found at \(logPath)")
                return
            }

            AppLogger.shared.log(
                "🔍 [DiagnosticsManager] Starting real-time VirtualHID connection monitoring"
            )

            // Scan existing log content first to clear any stale diagnostics
            var lastPosition: UInt64 = 0
            do {
                let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logPath))
                defer { fileHandle.closeFile() }

                let fileSize = fileHandle.seekToEndOfFile()
                lastPosition = fileSize

                if fileSize > 0 {
                    fileHandle.seek(toFileOffset: 0)
                    let existingData = fileHandle.readDataToEndOfFile()
                    if let logContent = String(data: existingData, encoding: .utf8) {
                        // Check if we see driver_connected 1 in recent logs (last 1000 lines)
                        let lines = logContent.components(separatedBy: .newlines)
                        let recentLines = lines.suffix(1000)
                        let recentContent = recentLines.joined(separator: "\n")

                        if recentContent.contains("driver_connected 1") {
                            AppLogger.shared.log(
                                "✅ [DiagnosticsManager] Found driver_connected 1 in recent logs - clearing stale VirtualHID failure diagnostics"
                            )
                            diagnostics.removeAll { diagnostic in
                                diagnostic.title == "VirtualHID Connection Failure"
                            }
                        }
                    }
                }
            } catch {
                AppLogger.shared.log("⚠️ [DiagnosticsManager] Could not scan existing log content: \(error)")
            }

            // Monitor log file for connection failures

            while !Task.isCancelled {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logPath))
                    defer { fileHandle.closeFile() }

                    let fileSize = fileHandle.seekToEndOfFile()
                    if fileSize > lastPosition {
                        fileHandle.seek(toFileOffset: lastPosition)
                        let newData = fileHandle.readDataToEndOfFile()
                        lastPosition = fileSize

                        if let logContent = String(data: newData, encoding: .utf8) {
                            await analyzeLogContent(logContent)
                        }
                    }

                    // Check every 2 seconds
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    AppLogger.shared.log("⚠️ [DiagnosticsManager] Error reading log file: \(error)")
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // Wait 5 seconds before retry
                }
            }

            AppLogger.shared.log("🔍 [DiagnosticsManager] Stopped log monitoring")
        }
    }

    func stopLogMonitoring() {
        logMonitorTask?.cancel()
        logMonitorTask = nil
        Task { @MainActor [weak self] in
            await self?.kanataService.recordConnectionSuccess() // Reset on stop
        }
    }

    func checkHealth(tcpPort: Int) async -> ServiceHealthStatus {
        await kanataService.checkHealth(tcpPort: tcpPort)
    }

    func diagnoseFailure(exitCode: Int32, output: String) -> [KanataDiagnostic] {
        diagnosticsService.diagnoseKanataFailure(exitCode: exitCode, output: output)
    }

    func getSystemDiagnostics(engineClient: EngineClient?) async -> [KanataDiagnostic] {
        await diagnosticsService.getSystemDiagnostics(engineClient: engineClient)
    }

    // MARK: - Private Helper Methods

    /// Analyze log content for VirtualHID connection issues
    private func analyzeLogContent(_ content: String) async {
        // Check for successful connection first - clear any existing failure diagnostics
        if content.contains("driver_connected 1") {
            AppLogger.shared.log(
                "✅ [DiagnosticsManager] Detected VirtualHID connection success - clearing failure diagnostics"
            )

            // Remove VirtualHID Connection Failure diagnostics
            diagnostics.removeAll { diagnostic in
                diagnostic.title == "VirtualHID Connection Failure"
            }

            // Record connection success
            await kanataService.recordConnectionSuccess()
            return
        }

        // Check for VirtualHID connection failures
        if content.contains("connect_failed asio.system:61")
            || content.contains("connect_failed asio.system:2") {
            AppLogger.shared.log("🚨 [DiagnosticsManager] Detected VirtualHID connection failure in logs")

            // Only add if we don't already have this diagnostic
            let hasExistingFailure = diagnostics.contains { diagnostic in
                diagnostic.title == "VirtualHID Connection Failure"
            }

            if !hasExistingFailure {
                let diagnostic = KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .conflict,
                    title: "VirtualHID Connection Failure",
                    description:
                    "Kanata cannot connect to VirtualHID device. This may indicate a driver or daemon issue.",
                    technicalDetails: "Connection error detected in log output",
                    suggestedAction: "Check VirtualHID driver and daemon status",
                    canAutoFix: true
                )

                addDiagnostic(diagnostic)
            }

            // Record connection failure for health monitoring
            let shouldRecover = await kanataService.recordConnectionFailure()
            if shouldRecover {
                AppLogger.shared.log(
                    "🚨 [DiagnosticsManager] Max connection failures reached - recovery recommended"
                )
            }
        }
    }
}
