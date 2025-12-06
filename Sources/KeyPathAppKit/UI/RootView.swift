import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// App launch phase: Splash → Create Rule → Main
enum AppLaunchPhase {
    case splash
    case createRule
    case main
}

struct RootView: View {
    @EnvironmentObject var viewModel: KanataViewModel
    @State private var launchPhase: AppLaunchPhase = .splash
    @State private var showingCreateRule = false
    @State private var showingWizard = false

    var body: some View {
        ZStack {
            // Full-window glass background; we can dial this back per-surface
            AppGlassBackground(style: .sheetBold)
                .ignoresSafeArea()

            // Content based on launch phase
            switch launchPhase {
            case .splash:
                SplashView()
                    .transition(.opacity)

            case .createRule:
                // Show empty background with Create Rule dialog as sheet
                VStack {
                    Spacer()
                    Text("Create your first key mapping")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            case .main:
                // Foreground content places solid surfaces where needed for text
                ContentView()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingCreateRule) {
            CustomRuleEditorView(
                rule: nil,
                existingRules: viewModel.customRules,
                onSave: { newRule in
                    Task { await viewModel.saveCustomRule(newRule) }
                },
                onPauseMappings: { await viewModel.underlyingManager.pauseMappings() },
                onResumeMappings: { await viewModel.underlyingManager.resumeMappings() }
            )
            .onDisappear {
                // After create rule dialog closes, go to main view
                withAnimation(.easeInOut(duration: 0.3)) {
                    launchPhase = .main
                }
            }
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView(initialPage: .summary)
                .customizeSheetWindow()
                .environmentObject(viewModel)
                .onDisappear {
                    // After wizard closes, proceed to create rule or main
                    proceedAfterWizard()
                }
        }
        .animation(.easeInOut(duration: 0.3), value: launchPhase)
        .onAppear {
            // Show splash briefly, then check system health
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))

                // Check system health to decide whether to show wizard
                let context = await viewModel.inspectSystemContext()
                let hasProblems = !context.permissions.isSystemReady || !context.services.isHealthy

                if hasProblems {
                    // System has verified problems - show wizard
                    AppLogger.shared.log("🔍 [RootView] System has problems, showing wizard")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        launchPhase = .main // Go to main so wizard shows as sheet over content
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                    showingWizard = true
                } else {
                    // System is healthy - proceed to create rule flow
                    AppLogger.shared.log("🔍 [RootView] System healthy, proceeding to create rule")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        launchPhase = .createRule
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                    showingCreateRule = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowMainView"))) { _ in
            // Skip to main view when menu item is selected
            showingCreateRule = false
            showingWizard = false
            withAnimation(.easeInOut(duration: 0.3)) {
                launchPhase = .main
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWizard"))) { _ in
            showingWizard = true
        }
    }

    private func proceedAfterWizard() {
        // After wizard closes, show create rule dialog
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.3)) {
                launchPhase = .createRule
            }
            try? await Task.sleep(for: .milliseconds(200))
            showingCreateRule = true
        }
    }
}
