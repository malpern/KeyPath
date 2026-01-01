import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Wizard page for stopping an external Kanata process
/// Page 2 of the Kanata user migration flow
/// Only shown when an external Kanata process is running
struct WizardStopKanataPage: View {
    @State private var isStopping = false
    @State private var stopError: String?
    @State private var runningInfo: WizardSystemPaths.RunningKanataInfo?

    // Animation states
    @State private var heroScale: CGFloat = 0.8
    @State private var heroOpacity: Double = 0
    @State private var showContent = false
    @State private var pulseScale: CGFloat = 1.0

    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Hero section with entrance animation
            WizardHeroSection(
                icon: "stop.circle",
                iconColor: .orange,
                title: "Stop existing Kanata",
                subtitle: "KeyPath needs to take over keyboard control"
            )
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            contentView
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 10)
        }
        .onAppear {
            runningInfo = ExternalKanataService.getExternalKanataInfo()
            animateEntrance()
        }
    }

    // MARK: - Entrance Animation

    private func animateEntrance() {
        // Hero entrance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }

        // Content fades in
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            showContent = true
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Explanation
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                if let info = runningInfo {
                    HStack {
                        ZStack {
                            // Pulse ring when stopping
                            if isStopping {
                                Circle()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                    .scaleEffect(pulseScale)
                                    .opacity(2 - pulseScale)
                                    .onAppear {
                                        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                            pulseScale = 2.0
                                        }
                                    }
                            }
                            Image(systemName: isStopping ? "hourglass" : "gearshape.2.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .symbolEffect(.rotate, isActive: isStopping)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isStopping ? "Stopping Kanata..." : "Kanata is currently running")
                                .font(.headline)
                            Text("PID: \(info.pid)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                Text("We'll stop your current Kanata process and disable any LaunchAgent so it doesn't restart.")
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Your remappings will pause for a moment until KeyPath starts.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.top, WizardDesign.Spacing.sectionGap)

            // Error message if any
            if let error = stopError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.body)
                    Spacer()
                }
                .padding(WizardDesign.Spacing.cardPadding)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            }

            Spacer()

            // Action buttons
            HStack(spacing: WizardDesign.Spacing.elementGap) {
                Button(isStopping ? "Stopping..." : "Stop Kanata") {
                    stopKanata()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .disabled(isStopping || runningInfo == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("stop-kanata-button")

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(isStopping)
                .accessibilityIdentifier("stop-kanata-cancel-button")
            }
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.bottom, WizardDesign.Spacing.pageVertical)
        }
    }

    // MARK: - Actions

    private func stopKanata() {
        guard let info = runningInfo else { return }

        isStopping = true
        stopError = nil

        Task {
            let result = await ExternalKanataService.stopExternalKanata(info)

            await MainActor.run {
                isStopping = false

                switch result {
                case .success, .processNotFound:
                    onComplete()

                case let .killFailed(error):
                    stopError = "Failed to stop Kanata: \(error.localizedDescription)"

                case let .launchAgentDisableFailed(error):
                    // Still proceed - process might be stopped
                    stopError = "Warning: LaunchAgent may restart Kanata: \(error.localizedDescription)"
                    // Check if process is actually gone
                    if !ExternalKanataService.hasExternalKanataRunning() {
                        onComplete()
                    }
                }
            }
        }
    }
}
