import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct WizardKanataServicePage: View {
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () -> Void

    // Access underlying RuntimeCoordinator for business logic
    private var kanataManager: RuntimeCoordinator {
        kanataViewModel.underlyingManager
    }

    @State private var isPerformingAction = false
    @State private var serviceStatus: ServiceStatus = .unknown
    @State private var refreshTimer: Timer?
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @State private var refreshTask: Task<Void, Never>?

    // Integration with RuntimeCoordinator for better error context
    @EnvironmentObject var stateMachine: WizardStateMachine

    enum ServiceStatus: Equatable {
        case unknown
        case running
        case stopped
        case failed(error: String)
        case starting
        case stopping

        var color: Color {
            switch self {
            case .running: .green
            case .stopped: .orange
            case .failed: .red
            case .starting, .stopping: .blue
            case .unknown: .gray
            }
        }

        var icon: String {
            switch self {
            case .running: "checkmark.circle.fill"
            case .stopped: "stop.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            case .starting, .stopping: "arrow.clockwise.circle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .running: "Service is running"
            case .stopped: "Service is not running"
            case .failed: "Service error"
            case .starting: "Service is starting..."
            case .stopping: "Service is stopping..."
            case .unknown: "Checking service status..."
            }
        }
    }

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            WizardHeroSection(
                icon: "gearshape.2",
                iconColor: serviceStatus.color,
                overlayIcon: serviceStatus.icon,
                overlayColor: serviceStatus.color,
                overlaySize: .large,
                title: "Kanata Service",
                subtitle: statusMessage,
                iconTapAction: { refreshStatus() }
            )
            .padding(.top, WizardDesign.Spacing.sectionGap)

            // Inline action status
            if actionStatus.isActive, let message = actionStatus.message {
                InlineStatusView(status: actionStatus, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if let cta = primaryCTAConfiguration {
                Button(cta.label, action: cta.action)
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isPerformingAction))
                    .keyboardShortcut(.defaultAction)
                    .disabled(cta.disabled)
                    .frame(minHeight: 44)
                    .padding(.top, WizardDesign.Spacing.itemGap)
            }

            if shouldShowNextStepButton {
                Button(nextStepButtonTitle) {
                    navigateToNextStep()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .padding(.top, WizardDesign.Spacing.sectionGap)
            }
        }
        .padding(.bottom, 32)
        .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onAppear {
            startAutoRefresh()
            refreshStatus()
        }
        .onDisappear {
            stopAutoRefresh()
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Helper Methods

    private enum DesiredServiceState {
        case running
        case stopped
    }

    private func evaluateServiceCompletion(target: DesiredServiceState, actionName: String) {
        switch target {
        case .running:
            switch serviceStatus {
            case .running:
                actionStatus = .success(message: "\(actionName) succeeded")
                scheduleStatusClear()
            case .failed:
                actionStatus = .error(message: "\(actionName) failed. Try again.")
            default:
                actionStatus = .error(message: "\(actionName) did not complete. Try again.")
            }
        case .stopped:
            switch serviceStatus {
            case .stopped:
                actionStatus = .success(message: "\(actionName) succeeded")
                scheduleStatusClear()
            case .failed:
                actionStatus = .error(message: "\(actionName) failed. Try again.")
            default:
                actionStatus = .error(message: "\(actionName) did not complete. Try again.")
            }
        }
    }

    /// Auto-clear success status after 3 seconds
    private func scheduleStatusClear() {
        Task { @MainActor in
            _ = await WizardSleep.seconds(3)
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }

    // MARK: - Computed Properties

    private var statusForHeader: WizardPageHeader.HeaderStatus {
        switch serviceStatus {
        case .running: .success
        case .stopped, .unknown: .info
        case .failed: .error
        case .starting, .stopping: .warning
        }
    }

    private var statusTitle: String {
        switch serviceStatus {
        case .running: "Service Running"
        case .stopped: "Service Not Running"
        case .failed: "Service Error"
        case .starting: "Starting Service"
        case .stopping: "Stopping Service"
        case .unknown: "Checking Status"
        }
    }

    private var statusMessage: String {
        switch serviceStatus {
        case .running:
            "Kanata is running and ready to process keyboard events."
        case .stopped:
            "Kanata service is not running. Click Fix to start it."
        case .failed:
            "Kanata failed to start. Click Fix to retry."
        case .starting:
            "Starting Kanata service…"
        case .stopping:
            "Stopping Kanata service…"
        case .unknown:
            "Checking Kanata service status… If this takes too long, click Fix."
        }
    }

    private var shouldShowNextStepButton: Bool {
        serviceStatus == .running
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    // MARK: - Actions

    private func startService() {
        isPerformingAction = true
        serviceStatus = .starting
        actionStatus = .inProgress(message: "Starting Kanata service…")

        Task { @MainActor in
            _ = await kanataManager.startKanata(reason: "Wizard service start button")
            isPerformingAction = false
            await refreshStatusAsync()
            evaluateServiceCompletion(target: .running, actionName: "Kanata start")
        }
    }

    private func restartService() {
        isPerformingAction = true
        serviceStatus = .stopping
        actionStatus = .inProgress(message: "Restarting Kanata service…")

        Task { @MainActor in
            _ = await kanataManager.restartServiceWithFallback(reason: "Wizard service restart button")
            isPerformingAction = false
            await refreshStatusAsync()
            evaluateServiceCompletion(target: .running, actionName: "Kanata restart")
        }
    }

    private func stopService() {
        isPerformingAction = true
        serviceStatus = .stopping
        actionStatus = .inProgress(message: "Stopping Kanata service…")

        Task { @MainActor in
            _ = await kanataManager.stopKanata(reason: "Wizard service stop button")
            isPerformingAction = false
            await refreshStatusAsync()
            evaluateServiceCompletion(target: .stopped, actionName: "Kanata stop")
        }
    }

    private func refreshStatus() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshStatusAsync()
        }
    }

    private func refreshStatusAsync() async {
        let serviceState = await kanataManager.currentServiceState()

        let processStatus = ServiceStatusEvaluator.evaluate(
            kanataIsRunning: serviceState.isRunning,
            systemState: systemState,
            issues: issues
        )

        guard !Task.isCancelled else { return }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                applyStatusUpdate(serviceState: serviceState, processStatus: processStatus)
            }
        }
    }

    @MainActor
    private func applyStatusUpdate(
        serviceState: KanataService.ServiceState,
        processStatus: ServiceProcessStatus
    ) {
        var derivedStatus: ServiceStatus

        switch serviceState {
        case .running:
            derivedStatus = .running
        case .stopped:
            derivedStatus = .stopped
        case let .failed(reason):
            // Try to get more detailed config error from stderr log
            let stderrPath = "/var/log/com.keypath.kanata.stderr.log"
            if let configError = Self.extractConfigError(from: stderrPath) {
                derivedStatus = .failed(error: configError)
            } else {
                derivedStatus = .failed(error: reason)
            }
        case .maintenance:
            derivedStatus = .starting
        case .requiresApproval:
            let message = "Approval required in System Settings ▸ Privacy & Security"
            derivedStatus = .failed(error: message)
        case .unknown:
            derivedStatus = .unknown
        }

        switch processStatus {
        case .running:
            break
        case let .failed(message):
            let errorMessage = message ?? "Permission or service issue detected"
            derivedStatus = .failed(error: errorMessage)
        case .stopped:
            // If we previously thought it was running, align with evaluator
            if derivedStatus == .running {
                derivedStatus = .stopped
            }
        }

        if case .stopped = derivedStatus {
            serviceStatus = .stopped
            AppLogger.shared.log("🔍 [ServiceStatus] Service stopped - checking for crash indicators")
            Task {
                await checkForCrashAsync()
            }
            return
        }

        if case .running = derivedStatus {
            AppLogger.shared.log("✅ [ServiceStatus] Service confirmed functional via shared evaluator")
        } else if case let .failed(error) = derivedStatus {
            AppLogger.shared.log("⚠️ [ServiceStatus] Service failed: \(error)")
        }

        serviceStatus = derivedStatus
    }

    private func checkForCrashAsync() async {
        // First check stderr log for config parsing errors (more detailed)
        let stderrPath = "/var/log/com.keypath.kanata.stderr.log"
        let logPath = WizardSystemPaths.kanataLogFile
        let errorMessage = await (Task.detached {
            Self.extractCrashError(stderrPath: stderrPath, logPath: logPath)
        }).value

        await MainActor.run {
            guard case .stopped = serviceStatus else { return }
            if let errorMessage {
                serviceStatus = .failed(error: errorMessage)
            } else {
                serviceStatus = .stopped
            }
        }
    }

    private nonisolated static func extractCrashError(stderrPath: String, logPath: String) -> String? {
        if let configError = extractConfigError(from: stderrPath) {
            return configError
        }

        if let logData = readRecentLogData(from: logPath, maxBytes: 64 * 1024) {
            let logString = String(decoding: logData, as: UTF8.self)
            let lines = logString.components(separatedBy: .newlines)
            let recentLines = lines.suffix(40) // Check last 40 lines

            for line in recentLines.reversed() {
                if line.contains("ERROR") || line.contains("FATAL") || line.contains("panic") {
                    return extractErrorMessage(from: line)
                }
            }
        }

        return nil
    }

    private nonisolated static func readRecentLogData(from path: String, maxBytes: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer {
            try? handle.close()
        }

        do {
            let endOffset = try handle.seekToEnd()
            let startOffset = max(0, Int64(endOffset) - Int64(maxBytes))
            try handle.seek(toOffset: UInt64(startOffset))
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    /// Extract config parsing error from kanata stderr log
    /// Returns a user-friendly error message if a recent config error is found
    private nonisolated static func extractConfigError(from stderrPath: String) -> String? {
        // Ignore stale stderr logs so old config errors don't surface after reinstalls.
        let maxLogAge: TimeInterval = 10 * 60
        if let attributes = try? FileManager.default.attributesOfItem(atPath: stderrPath),
           let modifiedAt = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modifiedAt) > maxLogAge {
            return nil
        }

        guard let logData = try? String(contentsOfFile: stderrPath, encoding: .utf8) else {
            return nil
        }

        let lines = logData.components(separatedBy: .newlines)
        let recentLines = Array(lines.suffix(100)) // Check last 100 lines for config errors

        // Look for config error patterns
        var foundConfigError = false
        var errorFile: String?
        var errorLine: String?
        var helpMessage: String?

        for line in recentLines.reversed() {
            // Check for "Error in configuration" marker
            if line.contains("Error in configuration") {
                foundConfigError = true
            }

            // Extract file and line info: ╭─[keypath-apps.kbd:14:1]
            if foundConfigError, errorFile == nil,
               let match = line.range(of: #"\[([^\]]+\.kbd):(\d+)"#, options: .regularExpression) {
                let matchStr = String(line[match])
                // Extract filename and line number
                let parts = matchStr.dropFirst().dropLast().split(separator: ":")
                if parts.count >= 2 {
                    errorFile = String(parts[0])
                    errorLine = String(parts[1])
                }
            }

            // Extract the help message which contains the actual error
            if foundConfigError, helpMessage == nil, line.contains("help:") {
                if let helpRange = line.range(of: "help:") {
                    helpMessage = String(line[helpRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }

            // Extract "failed to parse file" as fallback
            if line.contains("failed to parse file") {
                foundConfigError = true
            }

            // If we have all the info we need, build the message
            if foundConfigError, helpMessage != nil {
                break
            }
        }

        // Build user-friendly message
        if foundConfigError {
            var message = "Config error"
            if let file = errorFile {
                message += " in \(file)"
                if let lineNum = errorLine {
                    message += " line \(lineNum)"
                }
            }
            if let help = helpMessage {
                message += ": \(help)"
            }
            return message
        }

        return nil
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: issues),
               nextPage != stateMachine.currentPage {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private var primaryCTAConfiguration:
        (label: String, action: () -> Void, disabled: Bool)?
    {
        switch serviceStatus {
        case .running:
            nil
        case .starting, .stopping:
            nil
        case .unknown:
            (
                label: "Fix",
                action: startService,
                disabled: isPerformingAction
            )
        case .stopped:
            (
                label: "Fix",
                action: startService,
                disabled: isPerformingAction
            )
        case .failed:
            (
                label: "Fix",
                action: restartService,
                disabled: isPerformingAction
            )
        }
    }

    private nonisolated static func extractErrorMessage(from logLine: String) -> String {
        // Extract meaningful error message from log line
        if logLine.contains("Permission denied") {
            "Permission denied - check Input Monitoring settings"
        } else if logLine.contains("Config error") {
            "Configuration error - check your keypath.kbd file"
        } else if logLine.contains("Device not found") {
            "Keyboard device not found"
        } else {
            "Check log file for details"
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        // DISABLED: This timer calls refreshStatus() which may trigger invasive permission checks
        // that cause KeyPath to auto-add to Input Monitoring system preferences

        AppLogger.shared.log(
            "🔄 [WizardKanataServicePage] Auto-refresh timer DISABLED to prevent invasive permission checks"
        )
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Preview

struct WizardKanataServicePage_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)

        WizardKanataServicePage(
            systemState: .ready,
            issues: [],
            onRefresh: {}
        )
        .environmentObject(viewModel)
        .environmentObject(WizardStateMachine())
    }
}
