import SwiftUI

/// Guidance card shown when kanata's permission status is "not verified" (unknown)
/// because the user skipped Full Disk Access. Provides step-by-step instructions
/// for manually adding kanata in System Settings.
struct KanataUnverifiedGuidanceCard: View {
    let permissionType: String
    let onOpenSettings: () -> Void
    let onRevealInFinder: () -> Void
    let onEnableFDA: () -> Void

    @State private var showWhyNoToggle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(WizardDesign.Colors.info)
                HStack(spacing: 0) {
                    Text("kanata")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(" \u{2014} Permission not verified")
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundColor(.secondary)
                }
            }

            // Step-by-step instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to add kanata:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                instructionStep(number: 1, text: "Click \u{201C}Open Settings\u{201D} below")
                instructionStep(number: 2, text: "Click the + button, then press \u{2318}\u{21E7}G")
                instructionStep(number: 3, text: "Type /Library/KeyPath/bin/ and select \u{201C}kanata\u{201D}")
            }

            // Collapsible "why no toggle" explanation
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWhyNoToggle.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("The toggle won\u{2019}t appear after adding \u{2014} this is normal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: showWhyNoToggle ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("kanata_guidance_why_no_toggle")

                if showWhyNoToggle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS doesn\u{2019}t show toggles for command-line tools in the Privacy list. The permission is still granted even though no toggle appears.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Link(
                            "Learn more about macOS privacy permissions",
                            destination: URL(
                                string:
                                    "https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac"
                            )!
                        )
                        .font(.caption)
                    }
                    .padding(.leading, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .accessibilityIdentifier("kanata_guidance_open_settings")
                .buttonStyle(WizardDesign.Component.SecondaryButton())

                Button("Reveal in Finder") {
                    onRevealInFinder()
                }
                .accessibilityIdentifier("kanata_guidance_reveal_finder")
                .buttonStyle(.link)
            }

            // Divider with "or"
            HStack {
                VStack { Divider() }
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack { Divider() }
            }
            .padding(.vertical, 2)

            // FDA escape hatch
            Button {
                onEnableFDA()
            } label: {
                HStack(spacing: 4) {
                    Text("Enable Enhanced Diagnostics to verify automatically")
                        .font(.subheadline)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
            }
            .accessibilityIdentifier("kanata_guidance_enable_fda")
            .buttonStyle(.link)
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(WizardDesign.Colors.info.opacity(0.05))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(WizardDesign.Colors.info.opacity(0.2), lineWidth: 1)
        )
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(WizardDesign.Colors.info)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.subheadline)
        }
    }
}
