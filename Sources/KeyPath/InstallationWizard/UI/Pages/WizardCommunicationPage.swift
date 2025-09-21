import SwiftUI

struct WizardCommunicationPage: View {
    @State private var commStatus: CommunicationStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var showingFixFeedback = false
    @State private var fixResult: FixResult?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @EnvironmentObject var kanataManager: KanataManager
    @Environment(\.preferencesService) private var preferences: PreferencesService

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
                        Text("UDP server is running for instant config reloading & external integrations with ~10x lower latency")
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
                        Text("UDP Communication")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onAppear {
            Task {
                await checkCommunicationStatus()
            }
        }
    }

    // MARK: - Communication Status Check (Using Shared SystemStatusChecker)

    private func checkCommunicationStatus() async {
        commStatus = .checking
        lastCheckTime = Date()

        // Prefer a lightweight, non-blocking check that runs off the main actor.
        // The previous approach used SystemStatusChecker (MainActor) which spawned
        // synchronous launchctl calls and could momentarily block the UI.
        await checkUDPStatusDirect()
    }

    private func checkUDPStatusDirect() async {
        // Snapshot prefs safely off-main
        let snapshot = PreferencesService.communicationSnapshot()
        if !snapshot.shouldUseUDP {
            await MainActor.run { commStatus = .needsSetup("UDP server is not enabled") }
            return
        }

        let port = snapshot.udpPort
        let client = KanataUDPClient(port: port)
        AppLogger.shared.log("🧪 [WizardComm] Direct UDP check on port \(port)")

        // 1) Is the server answering?
        let responding = await client.checkServerStatus()
        guard responding else {
            await MainActor.run { commStatus = .needsSetup("UDP server is not responding on port \(port)") }
            return
        }

        // 2) Do we have a token? If not, auth is required.
        guard !snapshot.udpAuthToken.isEmpty else {
            await MainActor.run { commStatus = .authRequired("Secure connection required for configuration changes") }
            return
        }

        // 3) Try to authenticate and perform a quick reload probe
        let authed = await client.authenticate(token: snapshot.udpAuthToken)
        guard authed else {
            await MainActor.run { commStatus = .authRequired("Authentication failed. Generate a new token and retry.") }
            return
        }

        let reload = await client.reloadConfig()
        if reload.isSuccess {
            await MainActor.run { commStatus = .ready("Ready for instant configuration changes and external integrations") }
        } else if case .authenticationRequired = reload {
            await MainActor.run { commStatus = .authRequired("Session expired; re-authentication required") }
        } else {
            let msg = reload.errorMessage ?? "UDP server responded but reload failed"
            await MainActor.run { commStatus = .authRequired(msg) }
        }
    }

    // MARK: - Authentication Helpers (for Auto-Fix functionality)

    private func authenticateWithRetries(client: KanataUDPClient, token: String, attempts: Int = 5, initialDelay: TimeInterval = 0.2) async -> Bool {
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

    private func testConfigReload(client: KanataUDPClient) async -> Bool {
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

        // For authentication setup, we need additional steps
        if success, commStatus.isAuthenticationRelated {
            success = await setupAuthentication()
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
            (.enableUDPServer, "UDP server enabled successfully", "Failed to enable UDP server")
        case .authRequired:
            (.setupUDPAuthentication, "Secure connection established successfully", "Failed to setup authentication")
        default:
            (.enableUDPServer, "Issue resolved", "Failed to fix issue")
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

        // Update token directly to shared file
        await MainActor.run {
            preferences.udpAuthToken = newToken
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

        // Wait for the UDP server to be ready before authenticating
        AppLogger.shared.log("🔄 [WizardComm] Waiting for UDP server to be ready...")
        let client = KanataUDPClient(port: preferences.udpServerPort)
        let ready = await client.checkServerStatus()
        if !ready {
            AppLogger.shared.log("❌ [WizardComm] UDP server did not become ready in time after restart")
            return false
        }
        AppLogger.shared.log("✅ [WizardComm] UDP server is ready, proceeding with authentication")

        // Retry authenticate with small backoff to ride out any last startup work
        let authed = await WizardCommunicationPage.authenticateWithRetries(client: client, token: newToken, attempts: 5, initialDelay: 0.2)
        if authed {
            // Test config reload to ensure full functionality
            return await WizardCommunicationPage.testConfigReload(client: client)
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

// MARK: - Local helpers

extension WizardCommunicationPage {
    static func authenticateWithRetries(client: KanataUDPClient, token: String, attempts: Int, initialDelay: Double) async -> Bool {
        var delay = initialDelay
        for _ in 0 ..< max(attempts, 1) {
            if await client.authenticate(token: token, clientName: "KeyPath") {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay *= 1.5
        }
        return false
    }

    static func testConfigReload(client: KanataUDPClient) async -> Bool {
        let result = await client.reloadConfig()
        return result.isSuccess
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
            "Enable UDP Server"
        case .authRequired:
            "Setup Authentication"
        default:
            "Fix Issue"
        }
    }
}
