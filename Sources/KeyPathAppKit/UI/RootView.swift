import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject var viewModel: KanataViewModel
    @State private var showingWizard = false
    @State private var hasCheckedWizardNeed = false
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""
    @State private var showingWhatsNew = false

    var body: some View {
        ZStack {
            // Layer 1: Glass background
            AppGlassBackground(style: .sheetBold)
                .ignoresSafeArea()

            // Layer 2: Home content
            CustomRuleEditorView(
                rule: nil,
                existingRules: viewModel.customRules,
                isStandalone: true,
                onSave: { newRule in
                    Task { await viewModel.saveCustomRule(newRule) }
                },
                onShowWizard: { showingWizard = true }
            )
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView(initialPage: .summary)
                .customizeSheetWindow()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView()
                .onDisappear {
                    WhatsNewTracker.markAsSeen()
                }
        }
        .task {
            // Wait for splash to finish (coordinated via notification)
            // Then check if wizard is needed
            guard !hasCheckedWizardNeed else { return }
            hasCheckedWizardNeed = true

            // Wait for splash dismissal (5 seconds splash + 0.5s fade + small buffer)
            // The splash window controller handles the actual timing
            try? await Task.sleep(for: .seconds(6.0))

            // Check if wizard needed - only check KeyPath permissions, not Kanata
            let context = await viewModel.inspectSystemContext()
            if !context.permissions.keyPath.hasAllPermissions || !context.services.isHealthy {
                try? await Task.sleep(for: .milliseconds(300))
                showingWizard = true
            } else if WhatsNewTracker.shouldShowWhatsNew() {
                // System is ready - check if we should show What's New (after update)
                try? await Task.sleep(for: .milliseconds(300))
                showingWhatsNew = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWizard"))) { _ in
            showingWizard = true
        }
        .onPreferenceChange(WindowHeightPreferenceKey.self) { newHeight in
            guard newHeight > 0 else { return }
            NotificationCenter.default.post(
                name: .mainWindowHeightChanged,
                object: nil,
                userInfo: ["height": newHeight]
            )
        }
        .focusEffectDisabled()
        .onChange(of: viewModel.lastError) { _, newError in
            if let error = newError {
                validationErrorMessage = error
                showingValidationError = true
                viewModel.lastError = nil
            }
        }
        .alert("Configuration Error", isPresented: $showingValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
    }
}

// MARK: - Splash Notification

extension Notification.Name {
    /// Posted when the splash window has finished dismissing
    static let splashDidDismiss = Notification.Name("KeyPath.splashDidDismiss")
}
