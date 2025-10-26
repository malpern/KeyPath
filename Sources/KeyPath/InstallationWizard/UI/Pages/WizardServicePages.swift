import SwiftUI

// Consolidated service pages: Communication + Kanata Service
// Moved from:
// - WizardCommunicationPage.swift
// - WizardKanataServicePage.swift

struct WizardCommunicationPage: View {
    @State private var commStatus: CommunicationStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    let onAutoFix: ((AutoFixAction) async -> Bool)?

    init(onAutoFix: ((AutoFixAction) async -> Bool)? = nil) {
        self.onAutoFix = onAutoFix
    }

    var body: some View {
        VStack(spacing: 0) {
            if commStatus.isSuccess {
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        ZStack {
                            Image(systemName: "globe")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(BounceIfAvailable())
                            VStack { HStack { Spacer(); Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) }; Spacer() }
                                .frame(width: 140, height: 115)
                        }
                        Text("Communication Ready")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Text("TCP server is running for instant config reloading")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)
                    Spacer()
                }
            } else {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        ZStack {
                            Image(systemName: "globe")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(commStatus.globeColor)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(BounceIfAvailable())
                            VStack { HStack { Spacer(); Image(systemName: commStatus.overlayIcon)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(commStatus.globeColor)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -3) }; Spacer() }
                                .frame(width: 60, height: 60)
                        }
                        .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)
                        Text("TCP Communication")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Text(commStatus.message)
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)
                }
            }
        }
        .background(WizardDesign.Colors.wizardBackground)
    }

    // Minimal communication status for build compatibility
    enum CommunicationStatus {
        case checking
        case ok
        case error(String)
        var isSuccess: Bool { if case .ok = self { return true } else { return false } }
        var message: String { switch self { case .checking: return "Checking communication..."; case .ok: return "Communication healthy"; case let .error(msg): return msg } }
        var globeColor: Color { isSuccess ? .green : .orange }
        var overlayIcon: String { isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    }
}

// Minimal shim to preserve previous modifier usage
struct BounceIfAvailable: ViewModifier {
    func body(content: Content) -> some View { content }
}

struct WizardKanataServicePage: View {
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let systemState: WizardSystemState
    let issues: [WizardIssue]

    private var kanataManager: KanataManager { kanataViewModel.underlyingManager }

    @State private var serviceStatus: ServiceStatus = .unknown
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    enum ServiceStatus: Equatable { case unknown, running, stopped }

    var body: some View {
        VStack(spacing: 0) {
            if serviceStatus == .running {
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        ZStack {
                            Image(systemName: "gearshape.2")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())
                            VStack { HStack { Spacer(); Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) }; Spacer() }
                                .frame(width: 115, height: 115)
                        }
                        Text("Kanata Service")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Text("Service is running and processing keyboard events")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)
                    Spacer()
                }
            } else {
                ScrollView { Text("Service controls and status appear here.")
                    .padding(WizardDesign.Spacing.pageVertical) }
            }
        }
        .background(WizardDesign.Colors.wizardBackground)
    }
}
