import Foundation

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
    func checkHealth(processStatus: ProcessHealthStatus, tcpPort: Int) async -> ServiceHealthStatus
    
    /// Check if restart is allowed based on cooldown
    func canRestartService() async -> RestartCooldownState
    
    /// Record that a service start was attempted
    func recordStartAttempt(timestamp: Date) async
    
    /// Record start success
    func recordStartSuccess() async
    
    /// Record connection success
    func recordConnectionSuccess() async
    
    /// Diagnose Kanata failure
    func diagnoseFailure(exitCode: Int32, output: String) -> [KanataDiagnostic]
    
    /// Get system diagnostics
    func getSystemDiagnostics() async -> [KanataDiagnostic]
}

/// Manages diagnostics, health monitoring, and log monitoring
@MainActor
final class DiagnosticsManager: @preconcurrency DiagnosticsManaging {
    private var diagnostics: [KanataDiagnostic] = []
    private let diagnosticsService: DiagnosticsServiceProtocol
    private let healthMonitor: ServiceHealthMonitorProtocol
    private let processLifecycleManager: ProcessLifecycleManager
    
    private var logMonitorTask: Task<Void, Never>?
    
    init(
        diagnosticsService: DiagnosticsServiceProtocol,
        healthMonitor: ServiceHealthMonitorProtocol,
        processLifecycleManager: ProcessLifecycleManager
    ) {
        self.diagnosticsService = diagnosticsService
        self.healthMonitor = healthMonitor
        self.processLifecycleManager = processLifecycleManager
    }
    
    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnostics.append(diagnostic)
        AppLogger.shared.log(
            "\(diagnostic.severity.emoji) [DiagnosticsManager] \(diagnostic.title): \(diagnostic.description)")
        
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
            
            let logPath = "/var/log/kanata.log"
            guard FileManager.default.fileExists(atPath: logPath) else {
                AppLogger.shared.log("⚠️ [DiagnosticsManager] Kanata log file not found at \(logPath)")
                return
            }
            
            AppLogger.shared.log("🔍 [DiagnosticsManager] Starting real-time VirtualHID connection monitoring")
            
            // Monitor log file for connection failures
            var lastPosition: UInt64 = 0
            
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
                            await self.analyzeLogContent(logContent)
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
            await self?.healthMonitor.recordConnectionSuccess() // Reset on stop
        }
    }
    
    func checkHealth(processStatus: ProcessHealthStatus, tcpPort: Int) async -> ServiceHealthStatus {
        await healthMonitor.checkServiceHealth(
            processStatus: processStatus,
            tcpPort: tcpPort
        )
    }
    
    func recordStartSuccess() async {
        await healthMonitor.recordStartSuccess()
    }
    
    func recordConnectionSuccess() async {
        await healthMonitor.recordConnectionSuccess()
    }
    
    func canRestartService() async -> RestartCooldownState {
        await healthMonitor.canRestartService()
    }
    
    func recordStartAttempt(timestamp: Date) async {
        await healthMonitor.recordStartAttempt(timestamp: timestamp)
    }
    
    func diagnoseFailure(exitCode: Int32, output: String) -> [KanataDiagnostic] {
        diagnosticsService.diagnoseKanataFailure(exitCode: exitCode, output: output)
    }
    
    func getSystemDiagnostics() async -> [KanataDiagnostic] {
        await diagnosticsService.getSystemDiagnostics()
    }
    
    // MARK: - Private Helper Methods
    
    /// Analyze log content for VirtualHID connection issues
    private func analyzeLogContent(_ content: String) async {
        // Check for VirtualHID connection failures
        if content.contains("connect_failed asio.system:61") || content.contains("connect_failed asio.system:2") {
            AppLogger.shared.log("🚨 [DiagnosticsManager] Detected VirtualHID connection failure in logs")
            
            let diagnostic = KanataDiagnostic(
                timestamp: Date(),
                severity: .error,
                category: .conflict,
                title: "VirtualHID Connection Failure",
                description: "Kanata cannot connect to VirtualHID device. This may indicate a driver or daemon issue.",
                technicalDetails: "Connection error detected in log output",
                suggestedAction: "Check VirtualHID driver and daemon status",
                canAutoFix: true
            )
            
            addDiagnostic(diagnostic)
            
            // Record connection failure for health monitoring
            let shouldRecover = await healthMonitor.recordConnectionFailure()
            if shouldRecover {
                AppLogger.shared.log("🚨 [DiagnosticsManager] Max connection failures reached - recovery recommended")
            }
        }
    }
}

