import SwiftUI

struct WizardCommunicationPage: View {
    @State private var commStatus: CommunicationStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var showingFixFeedback = false
    @State private var fixResult: FixResult?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
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
                                .symbolEffect(.bounce, options: .nonRepeating)

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
                                .symbolEffect(.bounce, options: .nonRepeating)

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

    // MARK: - Communication Status Check

    private func checkCommunicationStatus() async {
        commStatus = .checking
        lastCheckTime = Date()

        // Check UDP status only
        await checkUDPStatus()
    }

    private func checkUDPStatus() async {
        if !preferences.udpServerEnabled {
            commStatus = .needsSetup("UDP server is not enabled")
            return
        }

        // Try to ping UDP server without authentication
        let client = KanataUDPClient(port: preferences.udpServerPort)
        AppLogger.shared.log("🧪 [WizardComm] Checking UDP server status on port \(preferences.udpServerPort)")
        let isAvailable = await client.checkServerStatus()
        AppLogger.shared.log("🧪 [WizardComm] UDP server status check result: \(isAvailable)")

        if !isAvailable {
            AppLogger.shared.log("❌ [WizardComm] UDP server marked as not available")
            commStatus = .needsSetup("UDP server is not responding on port \(preferences.udpServerPort)")
            return
        }

        // Server is available, now test authentication
        await testAuthentication(client: client)
    }

    private func testAuthentication(client: KanataUDPClient) async {
        commStatus = .authTesting("Testing secure connection...")

        // Check if we already have a valid auth token
        let authToken = preferences.udpAuthToken
        if !authToken.isEmpty {
            // Try existing token
            let authenticated = await client.authenticate(token: authToken)
            if authenticated {
                // Test config reload capability
                if await testConfigReload(client: client) {
                    commStatus = .ready("Ready for instant configuration changes and external integrations")
                    return
                } else {
                    commStatus = .authRequired("Authentication works but config reload failed - may need fresh token")
                    return
                }
            }
        }

        // Need new authentication
        commStatus = .authRequired("Secure connection required for configuration changes")
    }

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
        guard let onAutoFix = onAutoFix else { return }

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
            return (.enableUDPServer, "UDP server enabled successfully", "Failed to enable UDP server")
        case .authRequired:
            return (.setupUDPAuthentication, "Secure connection established successfully", "Failed to setup authentication")
        default:
            return (.enableUDPServer, "Issue resolved", "Failed to fix issue")
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
        let authed = await authenticateWithRetries(client: client, token: newToken, attempts: 5, initialDelay: 0.2)
        if authed {
            // Test config reload to ensure full functionality
            return await testConfigReload(client: client)
        } else {
            return false
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
            return true
        default:
            return false
        }
    }

    var canAutoFix: Bool {
        switch self {
        case .needsSetup, .authRequired:
            return true
        default:
            return false
        }
    }

    var isAuthenticationRelated: Bool {
        switch self {
        case .authRequired:
            return true
        default:
            return false
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking communication server status..."
        case let .ready(msg), let .needsSetup(msg), let .authRequired(msg), let .authTesting(msg), let .error(msg):
            return msg
        }
    }

    var globeColor: Color {
        switch self {
        case .ready:
            return WizardDesign.Colors.success
        case .needsSetup, .authRequired:
            return WizardDesign.Colors.warning
        case .authTesting:
            return WizardDesign.Colors.warning
        case .error:
            return WizardDesign.Colors.error
        case .checking:
            return WizardDesign.Colors.warning
        }
    }

    var overlayIcon: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .needsSetup:
            return "exclamationmark.triangle.fill"
        case .authRequired:
            return "key.fill"
        case .authTesting:
            return "clock.fill"
        case .error:
            return "xmark.circle.fill"
        case .checking:
            return "clock.fill"
        }
    }

    var fixButtonText: String {
        switch self {
        case .needsSetup:
            return "Enable UDP Server"
        case .authRequired:
            return "Setup Authentication"
        default:
            return "Fix Issue"
        }
    }
}
