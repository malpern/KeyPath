import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// App launch phase: Splash → Home (Custom Rule Editor)
enum AppLaunchPhase {
    case splash
    case home
}

struct RootView: View {
    @EnvironmentObject var viewModel: KanataViewModel
    @State private var launchPhase: AppLaunchPhase = .splash
    @State private var showingWizard = false

    var body: some View {
        ZStack {
            // Full-window glass background
            AppGlassBackground(style: .sheetBold)
                .ignoresSafeArea()

            // Content based on launch phase
            switch launchPhase {
            case .splash:
                SplashView()
                    .transition(.opacity)

            case .home:
                // Custom Rule Editor as the home screen
                CustomRuleEditorView(
                    rule: nil,
                    existingRules: viewModel.customRules,
                    isStandalone: true,
                    onSave: { newRule in
                        Task { await viewModel.saveCustomRule(newRule) }
                    },
                    onPauseMappings: { await viewModel.underlyingManager.pauseMappings() },
                    onResumeMappings: { await viewModel.underlyingManager.resumeMappings() }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView(initialPage: .summary)
                .customizeSheetWindow()
                .environmentObject(viewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: launchPhase)
        .onAppear {
            // Show splash briefly, then check system health
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))

                // Check system health to decide whether to show wizard
                let context = await viewModel.inspectSystemContext()
                let hasProblems = !context.permissions.isSystemReady || !context.services.isHealthy

                // Always go to home after splash
                withAnimation(.easeInOut(duration: 0.3)) {
                    launchPhase = .home
                }

                if hasProblems {
                    // System has verified problems - show wizard over home
                    AppLogger.shared.log("🔍 [RootView] System has problems, showing wizard")
                    try? await Task.sleep(for: .milliseconds(200))
                    showingWizard = true
                } else {
                    AppLogger.shared.log("🔍 [RootView] System healthy, showing home")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWizard"))) { _ in
            showingWizard = true
        }
    }
}
