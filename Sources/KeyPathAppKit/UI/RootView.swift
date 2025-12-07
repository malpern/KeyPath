import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject var viewModel: KanataViewModel
    @State private var showingSplash = true
    @State private var splashOpacity: Double = 1.0
    @State private var showingWizard = false

    // Fixed splash size (matches image aspect ratio 1000x800 @2x)
    private let splashSize = CGSize(width: 500, height: 400)

    var body: some View {
        ZStack {
            // Layer 1: Glass background (always present, revealed as splash fades)
            AppGlassBackground(style: .sheetBold)
                .ignoresSafeArea()

            // Layer 2: Home content (always present, revealed as splash fades)
            CustomRuleEditorView(
                rule: nil,
                existingRules: viewModel.customRules,
                isStandalone: true,
                onSave: { newRule in
                    Task { await viewModel.saveCustomRule(newRule) }
                },
                onShowWizard: { showingWizard = true }
            )
            .opacity(1.0 - splashOpacity)

            // Layer 3: Splash on top (fades out to reveal glass + content)
            if showingSplash {
                SplashView()
                    .opacity(splashOpacity)
            }
        }
        .onAppear {
            // Force window to splash size on appear
            if showingSplash {
                setWindowSize(splashSize)
            }
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView(initialPage: .summary)
                .customizeSheetWindow()
                .environmentObject(viewModel)
        }
        .task {
            // Show splash for 5 seconds
            try? await Task.sleep(for: .seconds(5.0))

            // Crossfade: splash fades out, glass + content fade in
            withAnimation(.easeInOut(duration: 0.5)) {
                splashOpacity = 0.0
            }

            // Remove splash view after animation completes
            try? await Task.sleep(for: .milliseconds(600))
            showingSplash = false

            // Check if wizard needed
            let context = await viewModel.inspectSystemContext()
            if !context.permissions.isSystemReady || !context.services.isHealthy {
                try? await Task.sleep(for: .milliseconds(300))
                showingWizard = true
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
    }

    private func setWindowSize(_ size: CGSize) {
        guard let window = NSApplication.shared.mainWindow else { return }
        var frame = window.frame
        let oldHeight = frame.height
        frame.size = size
        // Keep top-left anchored
        frame.origin.y += oldHeight - size.height
        window.setFrame(frame, display: true, animate: false)
    }
}
