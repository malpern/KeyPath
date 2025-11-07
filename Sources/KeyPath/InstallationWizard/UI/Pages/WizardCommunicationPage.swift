import SwiftUI
import KeyPathWizardCore
import KeyPathCore

struct WizardCommunicationPage: View {
    @State private var commStatus: CommunicationStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var showingFixFeedback = false
    @State private var fixResult: FixResult?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @EnvironmentObject var kanataViewModel: KanataViewModel
    @Environment(\.preferencesService) private var preferences: PreferencesService

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
        kanataViewModel.underlyingManager
    }

    // Auto-fix integration
    let onAutoFix: ((AutoFixAction) async -> Bool)?

    init(onAutoFix: ((AutoFixAction) async -> Bool)? = nil) {
        self.onAutoFix = onAutoFix
    }

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when communication is working
            if commStatus.isSuccess {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green globe with green check overlay
                        ZStack {
                            Image(systemName: "globe")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(BounceIfAvailable())

                            // Green check overlay in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Move further right and slightly up
                                }
                                Spacer()
                            }
                            .frame(width: 140, height: 115)
                        }

                        // Large headline (23pt)
                        Text("Communication Ready")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Supporting copy (17pt)
                        Text("TCP server is running for instant config reloading & external integrations")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Header for setup/error states with action link
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Custom header with colored globe icon
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Colored globe with overlay icon
                        ZStack {
                            Image(systemName: "globe")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(commStatus.globeColor)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(BounceIfAvailable())

                            // Overlay icon in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: commStatus.overlayIcon)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(commStatus.globeColor)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -3) // Move to the right for smaller icon
                                }
                                Spacer()
                            }
                            .frame(width: 60, height: 60)
                        }
                        .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)

                        // Title
                        Text("TCP Communication")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        // Status message
                        Text(commStatus.message)
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    // Action area
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Fix button or status indicator
                        if commStatus.canAutoFix {
                            WizardButton(
                                commStatus.fixButtonText,
                                style: .primary,
                                isLoading: isFixing
                            ) {
                                await performAutoFix()
                            }
                        } else if commStatus == .checking {
                            VStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Checking communication server...")
                                    .font(WizardDesign.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if case .authTesting = commStatus {
                            VStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Setting up secure connection...")
                                    .font(WizardDesign.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Secondary information or actions
                        if showingFixFeedback, let result = fixResult {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? WizardDesign.Colors.success : WizardDesign.Colors.error)
                                Text(result.message)
                                    .font(WizardDesign.Typography.body)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill((result.success ? WizardDesign.Colors.success : WizardDesign.Colors.error).opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }
            }

            Spacer()

            // Bottom buttons - HIG compliant button order
            WizardButtonBar(
                cancel: WizardButtonBar.CancelButton(title: "Back", action: navigateToPreviousPage),
                primary: WizardButtonBar.PrimaryButton(title: "Done") {
                    AppLogger.shared.log("ℹ️ [Wizard] User completing wizard from Communication page")
                    navigationCoordinator.navigateToPage(.summary)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onAppear {
            Task {
                await checkCommunicationStatus()
            }
        }
    }

    // MARK: - Helper Methods
    
    private func navigateToPreviousPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex > 0
        else { return }
        let previousPage = allPages[currentIndex - 1]
        navigationCoordinator.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Communication] Navigated to previous page: \(previousPage.displayName)")
    }

    // MARK: - Communication Status Check (Using Shared SystemStatusChecker)

    private func checkCommunicationStatus() async {
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                commStatus = .checking
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
                        AppLogger.shared.log("🌐 [WizardCommDetail] hello ok port=\(port) duration_ms=\(Int(dt*1000)) caps=\(hello.capabilities.joined(separator: ","))")

                        // Ensure Status capability exists to claim "Communication Ready"
                        if !hello.hasCapabilities(["status"]) {
                            AppLogger.shared.log("🌐 [WizardCommDetail] missing 'status' capability -> not ready")
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    commStatus = .needsSetup("TCP reachable but Status capability not available (older Kanata). Install/update via Wizard.")
                                }
                            }
                            return
                        }
                    } catch {
                        responding = false
                        AppLogger.shared.log("🌐 [WizardCommDetail] hello failed port=\(port) error=\(error.localizedDescription)")
                    }
                    guard responding else {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                commStatus = .needsSetup("TCP server is not responding. Service may use old TCP configuration. Click Fix to regenerate with TCP.")
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
                                commStatus = .ready("Ready for instant configuration changes and external integrations")
                            }
                        }
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
                    try await Task.sleep(nanoseconds: 15_000_000_000)
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
                    commStatus = .needsSetup("Connection timed out. Service may be using old TCP configuration. Click Fix to regenerate with TCP.")
                }
            }
        } catch {
            AppLogger.shared.log("❌ [WizardComm] TCP check failed: \(error)")
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    commStatus = .needsSetup("Failed to connect to TCP server. Click Fix to regenerate service configuration.")
                }
            }
        }
    }

    private struct TimeoutError: Error {}

    // MARK: - Authentication Helpers (for Auto-Fix functionality)

    private func authenticateWithRetries(client: KanataTCPClient, token: String, attempts: Int = 5, initialDelay: TimeInterval = 0.2) async -> Bool {
        var delay = initialDelay
        for attempt in 1 ... attempts {
            AppLogger.shared.log("🔐 [WizardComm] Authentication attempt \(attempt)/\(attempts)")
            if await client.authenticate(token: token) {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 1.6, 1.0)
        }
        AppLogger.shared.log("❌ [WizardComm] Authentication failed after \(attempts) attempts")
        return false
    }

    private func testConfigReload(client: KanataTCPClient) async -> Bool {
        // Test a simple config reload to ensure full functionality
        let result = await client.reloadConfig()
        switch result {
        case .success:
            return true
        case .authenticationRequired:
            return false
        case .failure:
            return false
        case .networkError:
            return false
        }
    }

    // MARK: - Auto Fix

    private func performAutoFix() async {
        guard let onAutoFix else { return }

        isFixing = true
        showingFixFeedback = false

        let (action, successMessage, failureMessage) = getAutoFixAction()
        var success = await onAutoFix(action)

        // For service regeneration, restart the service
        // NOTE: TCP mode doesn't require authentication (Kanata v1.9.0 ignores auth messages)
        if success, case .needsSetup = commStatus {
            AppLogger.shared.log("🔄 [WizardComm] Service regenerated, restarting Kanata...")
            success = await onAutoFix(.restartCommServer)

            if success {
                // Wait for TCP server to start
                AppLogger.shared.log("⏳ [WizardComm] Waiting for TCP server to be ready...")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            } else {
                AppLogger.shared.log("❌ [WizardComm] Failed to restart service after regeneration")
            }
        }

        isFixing = false
        fixResult = FixResult(
            success: success,
            message: success ? successMessage : failureMessage,
            timestamp: Date()
        )
        showingFixFeedback = true

        if success {
            // Recheck status after successful fix
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await checkCommunicationStatus()
        }
    }

    private func getAutoFixAction() -> (AutoFixAction, String, String) {
        switch commStatus {
        case .needsSetup:
            (.regenerateCommServiceConfiguration, "Service regenerated with TCP configuration", "Failed to regenerate service")
        case .authRequired:
            (.setupTCPAuthentication, "Secure connection established successfully", "Failed to setup authentication")
        default:
            (.regenerateCommServiceConfiguration, "Issue resolved", "Failed to fix issue")
        }
    }

    private func setupAuthentication() async -> Bool {
        // Generate a new secure auth token
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)
        guard result == errSecSuccess else {
            AppLogger.shared.log("❌ [WizardComm] Failed to generate secure random token")
            return false
        }

        let newToken = Data(randomBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Store token in keychain
        do {
            try await MainActor.run {
                try KeychainService.shared.storeTCPToken(newToken)
            }
        } catch {
            AppLogger.shared.log("❌ [WizardComm] Failed to store TCP token in keychain: \(error)")
            return false
        }

        // Regenerate service configuration with new token
        if let autoFix = onAutoFix {
            let regenOK = await autoFix(.regenerateCommServiceConfiguration)
            guard regenOK else {
                AppLogger.shared.log("❌ [WizardComm] Failed to regenerate communication service configuration")
                return false
            }

            // Restart communication server to adopt new token
            let restartOK = await autoFix(.restartCommServer)
            guard restartOK else {
                AppLogger.shared.log("❌ [WizardComm] Failed to restart communication server")
                return false
            }
        }

        // Wait for the TCP server to be ready before authenticating
        AppLogger.shared.log("🔄 [WizardComm] Waiting for TCP server to be ready...")
        let client = KanataTCPClient(port: preferences.tcpServerPort, timeout: 8.0)
        let ready = await client.checkServerStatus()
        if !ready {
            AppLogger.shared.log("❌ [WizardComm] TCP server did not become ready in time after restart")
            return false
        }
        AppLogger.shared.log("✅ [WizardComm] TCP server is ready, proceeding with authentication")

        // Retry authenticate with small backoff to ride out any last startup work
        let authed = await authenticateWithRetries(client: client, token: newToken)
        if authed {
            // Test config reload to ensure full functionality
            return await testConfigReload(client: client)
        } else {
            return false
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

struct FixResult {
    let success: Bool
    let message: String
    let timestamp: Date
}

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
        case let .ready(msg), let .needsSetup(msg), let .authRequired(msg), let .authTesting(msg), let .error(msg):
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
