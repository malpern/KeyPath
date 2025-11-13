import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct WizardKanataServicePage: View {
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () -> Void
    let toastManager: WizardToastManager

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
        kanataViewModel.underlyingManager
    }

    @State private var isPerformingAction = false
    @State private var lastError: String?
    @State private var serviceStatus: ServiceStatus = .unknown
    @State private var refreshTimer: Timer?

    // Integration with KanataManager for better error context
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    enum ServiceStatus: Equatable {
        case unknown
        case running
        case stopped
        case crashed(error: String)
        case starting
        case stopping

        var color: Color {
            switch self {
            case .running: .green
            case .stopped: .orange
            case .crashed: .red
            case .starting, .stopping: .blue
            case .unknown: .gray
            }
        }

        var icon: String {
            switch self {
            case .running: "checkmark.circle.fill"
            case .stopped: "stop.circle.fill"
            case .crashed: "exclamationmark.triangle.fill"
            case .starting, .stopping: "arrow.clockwise.circle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .running: "Service is running"
            case .stopped: "Service is stopped"
            case let .crashed(error): "Service crashed: \(error)"
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
                overlaySize: .small,
                title: "Kanata Service",
                subtitle: statusMessage,
                iconTapAction: { refreshStatus() }
            )
            .padding(.top, WizardDesign.Spacing.sectionGap)

            if let cta = primaryCTAConfiguration {
                Button(cta.label, action: cta.action)
                    .buttonStyle(.borderedProminent)
                    .tint(cta.tint)
                    .disabled(cta.disabled)
                    .padding(.top, WizardDesign.Spacing.itemGap)
            }

            if isPerformingAction {
                ProgressView()
                    .padding(.top, WizardDesign.Spacing.itemGap)
            }

            if let lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(lastError)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(10)
            }

            if shouldShowNextStepButton {
                Button(nextStepButtonTitle) {
                    navigateToNextStep()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .padding(.top, WizardDesign.Spacing.sectionGap)
            }

            Spacer()
        }
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
                toastManager.showSuccess("\(actionName) succeeded")
            case let .crashed(error):
                toastManager.showError("\(actionName) failed: \(error)")
            default:
                toastManager.showError("\(actionName) did not complete. Current state: \(serviceStatus.description)")
            }
        case .stopped:
            switch serviceStatus {
            case .stopped:
                toastManager.showSuccess("\(actionName) succeeded")
            case let .crashed(error):
                toastManager.showError("\(actionName) encountered an error: \(error)")
            default:
                toastManager.showError("\(actionName) did not complete. Current state: \(serviceStatus.description)")
            }
        }
    }

    // MARK: - Computed Properties

    private var statusForHeader: WizardPageHeader.HeaderStatus {
        switch serviceStatus {
        case .running: .success
        case .stopped, .unknown: .info
        case .crashed: .error
        case .starting, .stopping: .warning
        }
    }

    private var statusTitle: String {
        switch serviceStatus {
        case .running: "Service Running"
        case .stopped: "Service Stopped"
        case .crashed: "Service Crashed"
        case .starting: "Starting Service"
        case .stopping: "Stopping Service"
        case .unknown: "Unknown Status"
        }
    }

    private var statusMessage: String {
        switch serviceStatus {
        case .running:
            return "Kanata is running and ready to process keyboard events."
        case .stopped:
            return "Kanata service is stopped. Start it to enable keyboard remapping."
        case let .crashed(error):
            return "Kanata service crashed: \(error)"
        case .starting:
            return "Starting Kanata service…"
        case .stopping:
            return "Stopping Kanata service…"
        case .unknown:
            return "Checking Kanata service status…"
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
        lastError = nil

        Task {
            await kanataManager.startKanataWithSafetyTimeout()

            await MainActor.run {
                isPerformingAction = false
            }
            await refreshStatusAsync()
            await MainActor.run {
                evaluateServiceCompletion(target: .running, actionName: "Kanata start")
            }
        }
    }

    private func restartService() {
        isPerformingAction = true
        serviceStatus = .stopping
        lastError = nil

        Task {
            await kanataManager.stopKanata()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                serviceStatus = .starting
            }

            await kanataManager.startKanataWithSafetyTimeout()

            await MainActor.run {
                isPerformingAction = false
            }
            await refreshStatusAsync()
            await MainActor.run {
                evaluateServiceCompletion(target: .running, actionName: "Kanata restart")
            }
        }
    }

    private func stopService() {
        isPerformingAction = true
        serviceStatus = .stopping

        Task {
            await kanataManager.stopKanata()

            // Give it a moment to stop
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                isPerformingAction = false
            }
            await refreshStatusAsync()
            await MainActor.run {
                evaluateServiceCompletion(target: .stopped, actionName: "Kanata stop")
            }
        }
    }

    private func refreshStatus() {
        Task {
            await refreshStatusAsync()
        }
    }

    private func refreshStatusAsync() async {
        // Use the same ServiceStatusEvaluator as summary page (SINGLE SOURCE OF TRUTH)
        let processStatus = ServiceStatusEvaluator.evaluate(
            kanataIsRunning: kanataManager.isRunning,
            systemState: systemState,
            issues: issues
        )

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                switch processStatus {
                case .running:
                    serviceStatus = .running
                    lastError = nil
                    AppLogger.shared.log("✅ [ServiceStatus] Service confirmed functional via shared evaluator")

                case let .failed(message):
                    serviceStatus = .crashed(error: message ?? "Permission or service issue detected")
                    lastError = message
                    AppLogger.shared.log("⚠️ [ServiceStatus] Service failed via shared evaluator: \(message ?? "unknown")")

                case .stopped:
                    // Preserve existing crash log heuristic when stopped
                    checkForCrash()
                    AppLogger.shared.log("🔍 [ServiceStatus] Service stopped - checking for crash indicators")
                }
            }
        }
    }

    private func checkForCrash() {
        // Check log file for recent crash indicators
        let logPath = WizardSystemPaths.kanataLogFile

        if let logData = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = logData.components(separatedBy: .newlines)
            let recentLines = lines.suffix(20) // Check last 20 lines

            for line in recentLines.reversed() {
                if line.contains("ERROR") || line.contains("FATAL") || line.contains("panic") {
                    serviceStatus = .crashed(error: extractErrorMessage(from: line))
                    lastError = line
                    return
                }
            }
        }

        // No crash detected, just stopped
        serviceStatus = .stopped
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        if let nextPage = navigationCoordinator.getNextPage(for: systemState, issues: issues),
           nextPage != navigationCoordinator.currentPage {
            navigationCoordinator.navigateToPage(nextPage)
        } else {
            navigationCoordinator.navigateToPage(.summary)
        }
    }

    private var primaryCTAConfiguration: (label: String, action: () -> Void, tint: Color?, disabled: Bool)? {
        switch serviceStatus {
        case .running:
            return nil
        case .starting, .stopping:
            return nil
        case .unknown:
            return nil
        case .stopped:
            return (
                label: "Start Service",
                action: startService,
                tint: nil,
                disabled: isPerformingAction
            )
        case .crashed:
            return (
                label: "Restart Service",
                action: restartService,
                tint: .orange,
                disabled: isPerformingAction
            )
        }
    }

    private func extractErrorMessage(from logLine: String) -> String {
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
        let manager = KanataManager()
        let viewModel = KanataViewModel(manager: manager)
        let toastManager = WizardToastManager()

        WizardKanataServicePage(
            systemState: .ready,
            issues: [],
            onRefresh: {},
            toastManager: toastManager
        )
        .environmentObject(viewModel)
        .environmentObject(WizardNavigationCoordinator())
    }
}
