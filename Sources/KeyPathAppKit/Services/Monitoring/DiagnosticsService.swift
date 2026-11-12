import Foundation
import KeyPathCore
import KeyPathInstallationWizard

// MARK: - Diagnostic Types

/// Detailed diagnostic information for Kanata issues
struct KanataDiagnostic: Sendable {
    let timestamp: Date
    let severity: DiagnosticSeverity
    let category: DiagnosticCategory
    let title: String
    let description: String
    let technicalDetails: String
    let suggestedAction: String
    let canAutoFix: Bool
}

enum DiagnosticSeverity: String, CaseIterable, Sendable {
    case info
    case warning
    case error
    case critical

    var emoji: String {
        switch self {
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🚨"
        }
    }
}

enum DiagnosticCategory: String, CaseIterable, Sendable {
    case configuration = "Configuration"
    case permissions = "Permissions"
    case process = "Process"
    case system = "System"
    case conflict = "Conflict"
}

// MARK: - Protocol

/// Service responsible for generating and analyzing system diagnostics
protocol DiagnosticsServiceProtocol: Sendable {
    /// Get comprehensive system diagnostics
    func getSystemDiagnostics() async -> [KanataDiagnostic]

    /// Check for Kanata process conflicts
    func checkProcessConflicts() async -> [KanataDiagnostic]
}

// MARK: - Implementation

// SAFETY: @unchecked Sendable — all stored state (processDetector) is itself
// Sendable (@MainActor final class). Methods are stateless diagnostic queries.
final class DiagnosticsService: DiagnosticsServiceProtocol, @unchecked Sendable {
    /// Dependencies
    private let processDetector: KanataProcessDetector
    private let systemStateProvider: SystemStateProvider

    init(
        processDetector: KanataProcessDetector,
        systemStateProvider: SystemStateProvider = .shared
    ) {
        self.processDetector = processDetector
        self.systemStateProvider = systemStateProvider
    }

    // MARK: - System Diagnostics

    func getSystemDiagnostics() async -> [KanataDiagnostic] {
        // Fast path for tests - skip all process/system checks
        if TestEnvironment.isRunningTests {
            return []
        }

        var diagnostics: [KanataDiagnostic] = []

        // Check Kanata installation
        if !isKanataInstalled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .critical,
                    category: .system,
                    title: String(localized: "Kanata Not Installed"),
                    description: String(localized: "Kanata binary not found at \(WizardSystemPaths.kanataActiveBinary)"),
                    technicalDetails: "Expected path: \(WizardSystemPaths.kanataActiveBinary)",
                    suggestedAction: String(localized: "Use KeyPath's Installation Wizard to install Kanata automatically"),
                    canAutoFix: false
                )
            )
        }

        // NOTE: Permission checks are handled by the Installation Wizard
        // We don't duplicate permission diagnostics here to avoid confusion

        let karabinerElementsRunning = await isKarabinerElementsRunning()

        // Check for karabiner_grabber conflict (single diagnostic for the condition)
        if karabinerElementsRunning {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .conflict,
                    title: String(localized: "Karabiner Grabber Conflict"),
                    description: String(localized: "karabiner_grabber is running and will prevent Kanata from starting"),
                    technicalDetails: "karabiner_grabber process detected — causes 'exclusive access and device already open' errors",
                    suggestedAction: String(localized: "Quit Karabiner-Elements or disable its key remapping"),
                    canAutoFix: true
                )
            )
        }

        // Check for Kanata process conflicts
        let processConflicts = await checkProcessConflicts()
        diagnostics.append(contentsOf: processConflicts)

        // TCP handshake summary (protocol/capabilities)
        if let hello = await fetchTcpHello() {
            let caps = hello.capabilities.joined(separator: ", ")
            let proto = hello.protocolVersion
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .info,
                    category: .system,
                    title: "TCP Handshake",
                    description: "version=\(hello.version) protocol=\(proto) caps=[\(caps)]",
                    technicalDetails: "HelloOk(version, protocol, capabilities)",
                    suggestedAction: "",
                    canAutoFix: false
                )
            )

            // Protocol numbers are not stable across Kanata forks; prefer capability checks.
            // Keep this informational to avoid false "old version" errors.
        }

        return diagnostics
    }

    // MARK: - Process Conflict Checking

    func checkProcessConflicts() async -> [KanataDiagnostic] {
        var diagnostics: [KanataDiagnostic] = []
        let conflicts = await processDetector.detectConflicts()

        // Show external conflicts (errors that need attention)
        if !conflicts.externalProcesses.isEmpty {
            let conflictDetails = conflicts.externalProcesses.map { process in
                "PID \(process.pid): \(process.command)"
            }.joined(separator: "\n")

            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .conflict,
                    title: String(localized: "External Kanata Conflicts (\(conflicts.externalProcesses.count))"),
                    description: String(localized: "External Kanata processes that conflict with KeyPath"),
                    technicalDetails: conflictDetails,
                    suggestedAction: String(localized: "Terminate conflicting processes or let KeyPath auto-fix them"),
                    canAutoFix: true
                )
            )
        }

        return diagnostics
    }

    // MARK: - Helper Methods

    private func isKanataInstalled() -> Bool {
        Foundation.FileManager().fileExists(atPath: WizardSystemPaths.kanataActiveBinary)
    }

    func isKarabinerElementsRunning() async -> Bool {
        let pids = await systemStateProvider.processIDs(matching: "karabiner_grabber")
        return !pids.isEmpty
    }

    private func fetchTcpHello() async -> KanataTCPClient.TcpHelloOk? {
        let client = KanataTCPClient()

        do {
            let hello = try await client.hello()

            // FIX #1: Explicitly close connection to prevent file descriptor leak
            await client.cancelInflightAndCloseConnection()

            return hello
        } catch {
            // FIX #1: Clean up connection even on error path
            await client.cancelInflightAndCloseConnection()
            return nil
        }
    }
}
