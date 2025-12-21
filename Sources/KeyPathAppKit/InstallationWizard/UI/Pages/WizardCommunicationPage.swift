import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct WizardCommunicationPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    @State private var commStatus: CommunicationStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @EnvironmentObject var kanataViewModel: KanataViewModel
    @Environment(\.preferencesService) private var preferences: PreferencesService

    // Access underlying RuntimeCoordinator for business logic
    private var kanataManager: RuntimeCoordinator {
        kanataViewModel.underlyingManager
    }

    // Auto-fix integration
    let onAutoFix: ((AutoFixAction, Bool) async -> Bool)?

    init(
        systemState: WizardSystemState, issues: [WizardIssue],
        onAutoFix: ((AutoFixAction, Bool) async -> Bool)? = nil
    ) {
        self.systemState = systemState
        self.issues = issues
        self.onAutoFix = onAutoFix
    }

    var body: some View {
        VStack(spacing: 0) {
            // Unified hero/header (matches other wizard pages)
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                // Icon with overlay
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    ZStack {
                        Image(systemName: "globe")
                            .font(.system(size: 115, weight: .light))
                            .foregroundColor(commStatus.globeColor)
                            .symbolRenderingMode(.hierarchical)
                            .modifier(BounceIfAvailable())

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: commStatus.overlayIcon)
                                    .font(.system(size: commStatus.isSuccess ? 32 : 24, weight: .medium))
                                    .foregroundColor(commStatus.globeColor)
                                    .background(WizardDesign.Colors.wizardBackground)
                                    .clipShape(Circle())
                                    .offset(x: commStatus.isSuccess ? 12 : 8, y: commStatus.isSuccess ? -4 : -3)
                            }
                            Spacer()
                        }
                        .frame(width: 140, height: 115)
                    }
                    .frame(width: 140, height: 130)

                    Text("TCP Communication")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text(commStatus.message)
                        .font(WizardDesign.Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, WizardDesign.Spacing.pageVertical)

                // Inline action status (immediately after hero for visual consistency)
                if actionStatus.isActive, let message = actionStatus.message {
                    InlineStatusView(status: actionStatus, message: message)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Action buttons
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    if commStatus.isSuccess {
                        Button(nextStepButtonTitle) {
                            navigateToNextStep()
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, WizardDesign.Spacing.sectionGap)

                        Button("Re-check Status") {
                            Task { await checkCommunicationStatus() }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                    } else if commStatus.canAutoFix {
                        Button(commStatus.fixButtonText) {
                            Task { await performAutoFix() }
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixing))
                        .keyboardShortcut(.defaultAction)
                        .disabled(isFixing)
                        .frame(minHeight: 44)
                        .padding(.top, WizardDesign.Spacing.itemGap)

                        Button("Re-check Status") {
                            Task { await checkCommunicationStatus() }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isFixing)
                    } else if commStatus == .checking || isAuthTesting {
                        Button("Checking...") {}
                            .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: true))
                            .disabled(true)
                            .frame(minHeight: 44)
                            .padding(.top, WizardDesign.Spacing.itemGap)
                    } else {
                        Button("Re-check Status") {
                            Task { await checkCommunicationStatus() }
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }
                }
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            }

            Spacer()

            // Bottom buttons - HIG compliant button order
        }
        .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onAppear {
            Task {
                await checkCommunicationStatus()
            }
        }
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var isAuthTesting: Bool {
        if case .authTesting = commStatus {
            return true
        }
        return false
    }

    // MARK: - Communication Status Check (Using Shared SystemStatusChecker)

    private func checkCommunicationStatus() async {
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                commStatus = .checking
                actionStatus = .inProgress(message: "Checking communication server...")
            }
        }
        lastCheckTime = Date()

        // Prefer a lightweight, non-blocking check that runs off the main actor.
        // The previous approach used SystemStatusChecker (MainActor) which spawned
        // synchronous launchctl calls and could momentarily block the UI.
        await checkUDPStatusDirect()
    }

    private func checkUDPStatusDirect() async {
        // SECURITY NOTE (ADR-013): Kanata v1.9.0 TCP does NOT support authentication
        // We previously used UDP with token-based auth, but TCP explicitly ignores auth messages.
        // This is acceptable for localhost-only IPC with limited attack surface (config reloads only).
        // Future work: Consider contributing authentication support to upstream Kanata.

        // Check TCP server status (kanata uses TCP) with timeout
        let port = preferences.tcpServerPort
        let client = KanataTCPClient(port: port, timeout: 8.0)
        AppLogger.shared.log("🧪 [WizardComm] Checking TCP server on port \(port)")

        do {
            // Add timeout wrapper around the entire check (15s total)
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Main check task
                group.addTask {
                    // IMPORTANT: Kanata v1.9.0 TCP server does NOT support authentication
                    // It ignores all Authenticate messages. We only need to verify the server responds.

                    // 1) Is the server answering? Prefer Hello handshake to align with summary check
                    let responding: Bool
                    do {
                        let t0 = CFAbsoluteTimeGetCurrent()
                        let hello = try await client.hello()
                        responding = true
                        let dt = CFAbsoluteTimeGetCurrent() - t0
                        AppLogger.shared.log(
                            "🌐 [WizardCommDetail] hello ok port=\(port) duration_ms=\(Int(dt * 1000)) caps=\(hello.capabilities.joined(separator: ","))"
                        )

                        // Ensure Status capability exists to claim "Communication Ready"
                        if !hello.hasCapabilities(["status"]) {
                            AppLogger.shared.log("🌐 [WizardCommDetail] missing 'status' capability -> not ready")
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    commStatus = .needsSetup(
                                        "TCP reachable but Status capability not available (older Kanata). Install/update via Wizard."
                                    )
                                }
                            }
                            return
                        }
                    } catch {
                        responding = false
                        AppLogger.shared.log(
                            "🌐 [WizardCommDetail] hello failed port=\(port) error=\(error.localizedDescription)")
                    }
                    guard responding else {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                commStatus = .needsSetup(
                                    "TCP server is not responding. Service may use old TCP configuration. Click Fix to regenerate with TCP."
                                )
                            }
                        }
                        return
                    }

                    // 2) Test if we can send commands (e.g., reload config)
                    // No authentication needed - TCP mode is open for local connections
                    let reload = await client.reloadConfig()
                    if reload.isSuccess {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                commStatus = .ready(
                                    "Ready for instant configuration changes and external integrations")
                                actionStatus = .success(message: "Communication ready")
                                scheduleStatusClear()
                            }
                        }
                    } else if reload.isCancellation {
                        AppLogger.shared.log("⚠️ [WizardComm] TCP reload cancelled; retrying status check")
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                commStatus = .checking
                            }
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await checkCommunicationStatus()
                        }
                        return
                    } else {
                        let msg = reload.errorMessage ?? "TCP server responded but reload failed"
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                commStatus = .needsSetup(msg)
                            }
                        }
                    }
                }

                // Timeout task (15 seconds total)
                group.addTask {
                    // Poll for up to 15s at 250ms to detect service recovery
                    let clock = ContinuousClock()
                    for _ in 0 ..< 60 {
                        try await clock.sleep(for: .milliseconds(250))
                        if await isCommunicationResponding() {
                            // Communication is responding - return normally (no timeout)
                            return
                        }
                    }
                    // Only throw if we exhausted all 60 polls without a response
                    throw TimeoutError()
                }

                // Wait for first to complete
                try await group.next()
                group.cancelAll()
            }
        } catch is TimeoutError {
            AppLogger.shared.log("⚠️ [WizardComm] TCP check timed out after 15s")
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    commStatus = .needsSetup(
                        "Connection timed out. Service may be using old TCP configuration. Click Fix to regenerate with TCP."
                    )
                }
            }
        } catch {
            AppLogger.shared.log("❌ [WizardComm] TCP check failed: \(error)")
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    commStatus = .needsSetup(
                        "Failed to connect to TCP server. Click Fix to regenerate service configuration.")
                }
            }
        }

        // FIX #1: Explicitly close connection to prevent file descriptor leak
        await client.cancelInflightAndCloseConnection()
    }

    private struct TimeoutError: Error {}

    private func testConfigReload(client: KanataTCPClient) async -> Bool {
        // Test a simple config reload to ensure full functionality
        let result = await client.reloadConfig()
        switch result {
        case .success:
            return true
        case .failure, .networkError:
            return false
        }
    }

    /// Lightweight TCP readiness check used by polling loops.
    private func isCommunicationResponding() async -> Bool {
        let client = KanataTCPClient(port: preferences.tcpServerPort, timeout: 2.0)
        let ok = await client.checkServerStatus()
        await client.cancelInflightAndCloseConnection()
        return ok
    }

    // MARK: - Auto Fix

    private func performAutoFix() async {
        guard let onAutoFix else { return }

        isFixing = true

        await MainActor.run {
            actionStatus = .inProgress(message: "Fixing communication server...")
        }

        let (action, successMessage, failureMessage) = getAutoFixAction()
        var success = await onAutoFix(action, true) // suppressToast=true for inline feedback

        // For service regeneration, restart the service
        // NOTE: TCP mode doesn't require authentication (Kanata v1.9.0 ignores auth messages)
        if success, case .needsSetup = commStatus {
            AppLogger.shared.log("🔄 [WizardComm] Service regenerated, restarting Kanata...")
            success = await onAutoFix(.restartCommServer, true)

            if success {
                // Wait for TCP server to start
                AppLogger.shared.log("⏳ [WizardComm] Waiting for TCP server to be ready...")
                // Poll up to 3s at 200ms for the service to come up
                let clock = ContinuousClock()
                for _ in 0 ..< 15 {
                    try? await clock.sleep(for: .milliseconds(200))
                    if await isCommunicationResponding() {
                        break
                    }
                }
            } else {
                AppLogger.shared.log("❌ [WizardComm] Failed to restart service after regeneration")
            }
        }

        isFixing = false

        await MainActor.run {
            if success {
                actionStatus = .success(message: successMessage)
                scheduleStatusClear()
            } else {
                actionStatus = .error(message: failureMessage)
            }
        }

        if success {
            // Recheck status after successful fix
            let clock = ContinuousClock()
            for _ in 0 ..< 10 {
                try? await clock.sleep(for: .milliseconds(100))
                if await isCommunicationResponding() {
                    break
                }
            }
            await checkCommunicationStatus()
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

    private func getAutoFixAction() -> (AutoFixAction, String, String) {
        switch commStatus {
        case .needsSetup:
            (
                .regenerateCommServiceConfiguration, "Service regenerated with TCP configuration",
                "Failed to regenerate service"
            )
        case .authRequired:
            (
                .setupTCPAuthentication, "Secure connection established successfully",
                "Failed to setup authentication"
            )
        default:
            (.regenerateCommServiceConfiguration, "Issue resolved", "Failed to fix issue")
        }
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: issues),
               nextPage != navigationCoordinator.currentPage {
                navigationCoordinator.navigateToPage(nextPage)
            } else {
                navigationCoordinator.navigateToPage(.summary)
            }
        }
    }
}

// MARK: - Compatibility helpers

private struct BounceIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.modifier(AvailabilitySymbolBounce())
        } else {
            content
        }
    }
}

// MARK: - Communication Status Types

enum CommunicationStatus: Equatable {
    case checking
    case ready(String)
    case needsSetup(String)
    case authRequired(String)
    case authTesting(String)
    case error(String)

    var isSuccess: Bool {
        switch self {
        case .ready:
            true
        default:
            false
        }
    }

    var canAutoFix: Bool {
        switch self {
        case .needsSetup, .authRequired:
            true
        default:
            false
        }
    }

    var isAuthenticationRelated: Bool {
        switch self {
        case .authRequired:
            true
        default:
            false
        }
    }

    var message: String {
        switch self {
        case .checking:
            "Checking communication server status..."
        case let .ready(msg), let .needsSetup(msg), let .authRequired(msg), let .authTesting(msg),
             let .error(msg):
            msg
        }
    }

    var globeColor: Color {
        switch self {
        case .ready:
            WizardDesign.Colors.success
        case .needsSetup, .authRequired:
            WizardDesign.Colors.warning
        case .authTesting:
            WizardDesign.Colors.warning
        case .error:
            WizardDesign.Colors.error
        case .checking:
            WizardDesign.Colors.warning
        }
    }

    var overlayIcon: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .needsSetup:
            "exclamationmark.triangle.fill"
        case .authRequired:
            "key.fill"
        case .authTesting:
            "clock.fill"
        case .error:
            "xmark.circle.fill"
        case .checking:
            "clock.fill"
        }
    }

    var fixButtonText: String {
        switch self {
        case .needsSetup:
            "Regenerate Service Configuration"
        case .authRequired:
            "Setup Authentication"
        default:
            "Fix Issue"
        }
    }
}
