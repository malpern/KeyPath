import SwiftUI

/// Post-setup celebration + short panel tour (issue #954).
///
/// Shown exactly once, the moment the wizard first closes healthy after a fresh
/// install (see `OnboardingFirstSuccessGate`). Ends the setup arc that #932 started
/// in a working mapping instead of a closed wizard: a guaranteed one-click win
/// (Caps Lock → Escape) followed by a short tour of the surfaces users reach for
/// next — the live overlay, the Rules tab, and the custom-rule inline editor.
struct FirstSuccessDialog: View {
    @Environment(KanataViewModel.self) private var kanataManager

    /// Called when the user dismisses the dialog, at any step.
    let onFinished: () -> Void

    @State private var currentStep: Step = .celebration
    @State private var isEnabling = false
    @State private var starterErrorMessage: String?

    enum Step {
        case celebration
        case success
        case tourOverlay
        case tourRules
        case tourCustomRule
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case .celebration:
                    celebrationStep
                case .success:
                    successStep
                case .tourOverlay:
                    tourStep(
                        icon: "keyboard",
                        title: "Your Live Keyboard",
                        description: "This floating overlay shows your mappings in real time. Glance down anytime to see what a key does.",
                        identifier: "first-success-tour-overlay",
                        next: .tourRules
                    )
                case .tourRules:
                    tourStep(
                        icon: "list.bullet.rectangle",
                        title: "The Rules Tab",
                        description: "Every collection you turn on shows up here. Toggle any of them on or off whenever you like.",
                        identifier: "first-success-tour-rules",
                        next: .tourCustomRule
                    )
                case .tourCustomRule:
                    tourStep(
                        icon: "square.and.pencil",
                        title: "Make Your Own",
                        description: "When you're ready to make your own, the inline editor lets you map any key to anything — no config file required.",
                        identifier: "first-success-tour-custom-rule",
                        next: nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 460)
        .overlay(alignment: .topTrailing) {
            Button(action: onFinished) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityIdentifier("first-success-close-button")
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Celebration Step

    private var celebrationStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("You're All Set")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(celebrationMessage)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                if let starterErrorMessage {
                    Text(starterErrorMessage)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("first-success-enable-error")
                }

                Button(action: primaryCelebrationAction) {
                    HStack {
                        if isEnabling {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(primaryButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isEnabling)
                .accessibilityIdentifier("first-success-enable-button")

                Button("Not Now") {
                    currentStep = .tourOverlay
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("first-success-skip-button")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    private var capsLockTapOutput: String? {
        guard
            let collection = kanataManager.ruleCollections.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }),
            case let .tapHoldPicker(config) = collection.configuration
        else {
            return nil
        }
        return config.selectedTapOutput ?? config.tapOptions.first?.output
    }

    private var capsLockAlreadyEscape: Bool {
        capsLockTapOutput == "esc"
    }

    private var capsLockTapIsCustomized: Bool {
        guard let capsLockTapOutput else { return false }
        return capsLockTapOutput != "hyper" && capsLockTapOutput != "esc"
    }

    private var celebrationMessage: String {
        if capsLockAlreadyEscape {
            return "Caps Lock already sends Escape. Want a quick tour of what you can do next?"
        }
        if capsLockTapIsCustomized {
            return "Caps Lock already has a custom tap binding, so we'll keep it as-is. Want a quick tour?"
        }
        return "Want your first remap? One click and Caps Lock becomes Escape."
    }

    private var primaryButtonTitle: String {
        if capsLockAlreadyEscape || capsLockTapIsCustomized {
            return "Start Tour"
        }
        return "Enable Caps Lock → Escape"
    }

    private func primaryCelebrationAction() {
        if capsLockAlreadyEscape || capsLockTapIsCustomized {
            currentStep = .tourOverlay
        } else {
            enableStarterRemap()
        }
    }

    private func enableStarterRemap() {
        guard !isEnabling else { return }
        isEnabling = true
        starterErrorMessage = nil
        Task { @MainActor in
            // Caps Lock Remap ships enabled by default (tap+hold both bound to
            // Hyper), so a plain add would collide with itself. Re-pointing its
            // tap output to Escape via the same coordinator-backed mutator the
            // Rules tab picker uses is what actually changes the applied
            // behavior — the tap-hold generator reads `configuration`, not the
            // collection's decorative `mappings` field. Still goes through
            // RuleCollectionsCoordinator → regenerateConfigFromCollections, so
            // the TCP reload plumbing is untouched.
            let applied = await kanataManager.updateCollectionTapOutput(
                RuleCollectionIdentifier.capsLockRemap,
                tapOutput: "esc",
                reportRollbackError: false
            )
            isEnabling = false
            if applied {
                currentStep = .success
            } else {
                starterErrorMessage = "KeyPath couldn't save that remap. Your current setup was left unchanged."
            }
        }
    }

    // MARK: - Success Step

    private var successStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "escape")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("Press Caps Lock")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("It's Escape now.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Continue") {
                currentStep = .tourOverlay
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("first-success-continue-button")
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Tour Steps

    private func tourStep(
        icon: String,
        title: String,
        description: String,
        identifier: String,
        next: Step?
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(next == nil ? "Got It" : "Next") {
                if let next {
                    currentStep = next
                } else {
                    onFinished()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(next == nil ? "first-success-tour-done-button" : "first-success-tour-next-button")
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
