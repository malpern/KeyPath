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
                                "Enable UDP Server",
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

        // Try to connect to UDP server
        let client = KanataUDPClient(port: preferences.udpServerPort)
        let isAvailable = await client.checkServerStatus()

        if isAvailable {
            commStatus = .ready("UDP server is running and responsive")
        } else {
            commStatus = .needsSetup("UDP server is not responding on port \(preferences.udpServerPort)")
        }
    }

    // MARK: - Auto Fix

    private func performAutoFix() async {
        guard let onAutoFix = onAutoFix else { return }

        isFixing = true
        showingFixFeedback = false

        let action: AutoFixAction = .enableUDPServer
        let success = await onAutoFix(action)

        isFixing = false
        fixResult = FixResult(
            success: success,
            message: success ? "UDP server enabled successfully" : "Failed to enable UDP server",
            timestamp: Date()
        )
        showingFixFeedback = true

        if success {
            // Recheck status after successful fix
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await checkCommunicationStatus()
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
        case .needsSetup:
            return true
        default:
            return false
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking communication server status..."
        case let .ready(msg), let .needsSetup(msg), let .error(msg):
            return msg
        }
    }

    var globeColor: Color {
        switch self {
        case .ready:
            return WizardDesign.Colors.success
        case .needsSetup:
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
        case .error:
            return "xmark.circle.fill"
        case .checking:
            return "clock.fill"
        }
    }
}
