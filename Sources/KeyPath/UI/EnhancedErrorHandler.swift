import SwiftUI
import Foundation

/// Enhanced error handling system with persistent display and recovery actions
struct EnhancedErrorHandler: View {
    @Binding var errorInfo: ErrorInfo?
    @State private var isExecutingRecovery = false
    
    var body: some View {
        if let error = errorInfo {
            ErrorDisplayCard(
                errorInfo: error,
                isExecutingRecovery: isExecutingRecovery,
                onDismiss: { errorInfo = nil },
                onExecuteRecovery: { action in
                    await executeRecoveryAction(action)
                }
            )
        }
    }
    
    private func executeRecoveryAction(_ action: RecoveryAction) async {
        isExecutingRecovery = true
        defer { isExecutingRecovery = false }
        
        do {
            let success = try await action.execute()
            if success {
                // Auto-dismiss on successful recovery
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    errorInfo = nil
                }
            }
        } catch {
            // Update error with recovery failure
            await MainActor.run {
                errorInfo?.addRecoveryFailure(error)
            }
        }
    }
}

/// Comprehensive error information with recovery options
struct ErrorInfo: Identifiable {
    let id = UUID()
    let originalError: Error
    let errorType: ErrorType
    let title: String
    let detailedMessage: String
    let recoveryActions: [RecoveryAction]
    var recoveryFailures: [Error] = []
    
    mutating func addRecoveryFailure(_ error: Error) {
        recoveryFailures.append(error)
    }
    
    /// Create ErrorInfo from various error types with appropriate recovery actions
    static func from(_ error: Error) -> ErrorInfo {
        let errorString = error.localizedDescription.lowercased()
        
        // TCP timeout errors (like the user experienced)
        if (errorString.contains("tcp") && errorString.contains("timeout")) || 
           errorString.contains("tcp request timed out") ||
           errorString.contains("tcp communication failed") {
            return ErrorInfo(
                originalError: error,
                errorType: .tcpTimeout,
                title: "Connection Timeout",
                detailedMessage: """
                KeyPath couldn't communicate with the keyboard service to apply your changes.
                
                This usually happens when the service becomes unresponsive. Your mapping was safely rolled back to prevent issues.
                """,
                recoveryActions: [
                    .restartKanataService,
                    .openDiagnostics
                ]
            )
        }
        
        // Permission errors
        if errorString.contains("permission") || errorString.contains("not permitted") {
            return ErrorInfo(
                originalError: error,
                errorType: .permission,
                title: "Permission Required",
                detailedMessage: """
                KeyPath needs additional permissions to modify keyboard mappings.
                
                This often requires granting Input Monitoring or Accessibility permissions in System Settings.
                """,
                recoveryActions: [
                    .openPermissionSettings,
                    .runInstallationWizard
                ]
            )
        }
        
        // Service not running
        if errorString.contains("service") && (errorString.contains("not running") || errorString.contains("stopped")) {
            return ErrorInfo(
                originalError: error,
                errorType: .serviceNotRunning,
                title: "Service Not Running",
                detailedMessage: """
                The keyboard remapping service has stopped unexpectedly.
                
                This can happen after system updates or if there was a configuration error.
                """,
                recoveryActions: [
                    .startKanataService,
                    .runInstallationWizard,
                    .openDiagnostics
                ]
            )
        }
        
        // Config validation errors
        if errorString.contains("config") && (errorString.contains("invalid") || errorString.contains("validation")) {
            return ErrorInfo(
                originalError: error,
                errorType: .configValidation,
                title: "Configuration Error",
                detailedMessage: """
                The keyboard configuration contains invalid settings that prevent it from loading.
                
                This is usually due to conflicting key assignments or unsupported key combinations.
                """,
                recoveryActions: [
                    .resetToSafeConfig,
                    .openDiagnostics
                ]
            )
        }
        
        // Generic error fallback
        return ErrorInfo(
            originalError: error,
            errorType: .generic,
            title: "Unexpected Error",
            detailedMessage: """
            An unexpected error occurred while saving your keyboard mapping.
            
            Error: \(error.localizedDescription)
            """,
            recoveryActions: [
                .runInstallationWizard,
                .openDiagnostics
            ]
        )
    }
}

enum ErrorType {
    case tcpTimeout
    case permission
    case serviceNotRunning
    case configValidation
    case generic
    
    var icon: String {
        switch self {
        case .tcpTimeout: "network.slash"
        case .permission: "lock.shield"
        case .serviceNotRunning: "gearshape.2"
        case .configValidation: "doc.text.magnifyingglass"
        case .generic: "exclamationmark.triangle"
        }
    }
    
    var color: Color {
        switch self {
        case .tcpTimeout: .orange
        case .permission: .red
        case .serviceNotRunning: .yellow
        case .configValidation: .purple
        case .generic: .red
        }
    }
}

/// Actionable recovery steps with automated execution
enum RecoveryAction: Identifiable, CaseIterable {
    case restartKanataService
    case startKanataService
    case openPermissionSettings
    case runInstallationWizard
    case resetToSafeConfig
    case openDiagnostics
    
    var id: String { title }
    
    var title: String {
        switch self {
        case .restartKanataService: "Restart Keyboard Service"
        case .startKanataService: "Start Keyboard Service"
        case .openPermissionSettings: "Open Permission Settings"
        case .runInstallationWizard: "Run Setup Wizard"
        case .resetToSafeConfig: "Reset to Safe Configuration"
        case .openDiagnostics: "Open Diagnostics"
        }
    }
    
    var description: String {
        switch self {
        case .restartKanataService: "Restart the keyboard service to fix communication issues"
        case .startKanataService: "Start the keyboard remapping service"
        case .openPermissionSettings: "Open System Settings to grant required permissions"
        case .runInstallationWizard: "Run the setup wizard to fix configuration issues"
        case .resetToSafeConfig: "Reset to a basic working configuration"
        case .openDiagnostics: "Open diagnostics to see detailed system information"
        }
    }
    
    var icon: String {
        switch self {
        case .restartKanataService: "arrow.clockwise"
        case .startKanataService: "play.circle"
        case .openPermissionSettings: "gear"
        case .runInstallationWizard: "wrench.and.screwdriver"
        case .resetToSafeConfig: "arrow.counterclockwise"
        case .openDiagnostics: "info.circle"
        }
    }
    
    var requiresAdminPassword: Bool {
        switch self {
        case .restartKanataService, .startKanataService: true
        default: false
        }
    }
    
    /// Execute the recovery action
    func execute() async throws -> Bool {
        AppLogger.shared.log("🔧 [Recovery] Executing action: \(title)")
        
        switch self {
        case .restartKanataService:
            return try await restartKanataService()
        case .startKanataService:
            return try await startKanataService()
        case .openPermissionSettings:
            return await openPermissionSettings()
        case .runInstallationWizard:
            return await runInstallationWizard()
        case .resetToSafeConfig:
            return try await resetToSafeConfig()
        case .openDiagnostics:
            return await openDiagnostics()
        }
    }
    
    // MARK: - Recovery Action Implementations
    
    private func restartKanataService() async throws -> Bool {
        let script = """
        tell application "System Events"
            try
                set the result to (do shell script "sudo launchctl kickstart -k system/com.keypath.kanata" with administrator privileges)
                return true
            on error
                return false
            end try
        end tell
        """
        
        return try await executeAppleScript(script)
    }
    
    private func startKanataService() async throws -> Bool {
        let script = """
        tell application "System Events"
            try
                set the result to (do shell script "sudo launchctl kickstart system/com.keypath.kanata" with administrator privileges)
                return true
            on error
                return false
            end try
        end tell
        """
        
        return try await executeAppleScript(script)
    }
    
    private func openPermissionSettings() async -> Bool {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
            return true
        }
        return false
    }
    
    private func runInstallationWizard() async -> Bool {
        // This would need to be connected to the app's wizard system
        await MainActor.run {
            NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
        }
        return true
    }
    
    private func resetToSafeConfig() async throws -> Bool {
        // This would need to be connected to KanataManager
        await MainActor.run {
            NotificationCenter.default.post(name: .resetToSafeConfig, object: nil)
        }
        return true
    }
    
    private func openDiagnostics() async -> Bool {
        await MainActor.run {
            NotificationCenter.default.post(name: .openDiagnostics, object: nil)
        }
        return true
    }
    
    private func executeAppleScript(_ script: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let appleScript = NSAppleScript(source: script)
                var errorDict: NSDictionary?
                let result = appleScript?.executeAndReturnError(&errorDict)
                
                if let error = errorDict {
                    continuation.resume(throwing: NSError(domain: "AppleScript", code: -1, userInfo: error as? [String: Any]))
                } else {
                    let success = result?.booleanValue ?? false
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - UI Components

struct ErrorDisplayCard: View {
    let errorInfo: ErrorInfo
    let isExecutingRecovery: Bool
    let onDismiss: () -> Void
    let onExecuteRecovery: (RecoveryAction) async -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            HStack {
                Image(systemName: errorInfo.errorType.icon)
                    .font(.title2)
                    .foregroundColor(errorInfo.errorType.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(errorInfo.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !isExpanded {
                        Text("Tap to see recovery options")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Button("×") {
                    withAnimation {
                        onDismiss()
                    }
                }
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .onTapGesture {
                withAnimation {
                    isExpanded = true
                }
            }
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Detailed message
                    Text(errorInfo.detailedMessage)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Recovery failures (if any)
                    if !errorInfo.recoveryFailures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Previous recovery attempts failed:")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            ForEach(Array(errorInfo.recoveryFailures.enumerated()), id: \.offset) { _, failure in
                                Text("• \(failure.localizedDescription)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Recovery actions
                    Text("Recommended Actions:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(spacing: 8) {
                        ForEach(errorInfo.recoveryActions) { action in
                            RecoveryActionButton(
                                action: action,
                                isExecuting: isExecutingRecovery,
                                onExecute: { await onExecuteRecovery(action) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(errorInfo.errorType.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct RecoveryActionButton: View {
    let action: RecoveryAction
    let isExecuting: Bool
    let onExecute: () async -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            Task { await onExecute() }
        }) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    if action.requiresAdminPassword {
                        Image(systemName: "key.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPressed ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onPressGesture(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
    }
}

// MARK: - View Modifier for Press Gesture

extension View {
    func onPressGesture(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openInstallationWizard = Notification.Name("openInstallationWizard")
    static let resetToSafeConfig = Notification.Name("resetToSafeConfig")
    static let openDiagnostics = Notification.Name("openDiagnostics")
}