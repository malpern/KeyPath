import AppKit
import KeyPathWizardCore
import SwiftUI

/// One-time welcome page shown before any diagnostics on a fresh install (issue #932).
///
/// Value-first: the hero is a row of keycaps, each showing one of KeyPath's
/// superpowers, in the same visual language as the live keyboard overlay.
/// The setup work ahead is compressed into a single reassuring line above the
/// CTA — the wizard's own pages explain each step when it happens.
struct WizardWelcomePage: View {
    let onGetStarted: () -> Void

    @State private var keycapsVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: WizardDesign.Spacing.pageVertical)

            keycapHero

            Spacer().frame(height: 40)

            titleBlock

            Spacer().frame(height: 32)

            footer

            Spacer(minLength: WizardDesign.Spacing.pageVertical)
        }
        .padding(.horizontal, WizardDesign.Spacing.pageVertical * 2)
        .padding(.vertical, WizardDesign.Spacing.pageVertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .accessibilityIdentifier("wizard-welcome-page")
        .onAppear { animateKeycapsIn() }
    }

    // MARK: - Hero: keycaps that show, not tell

    private var keycapHero: some View {
        HStack(alignment: .top, spacing: WizardDesign.Spacing.sectionGap + 8) {
            HeroKeycap(
                fill: Color(red: 0.36, green: 0.40, blue: 0.47),
                rotation: -6,
                yOffset: 8,
                caption: "Supercharge\nCaps Lock",
                visible: keycapsVisible,
                delay: 0.0
            ) {
                VStack(spacing: 3) {
                    Text("esc")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.85)
                }
            }
            HeroKeycap(
                fill: Color(red: 0.20, green: 0.66, blue: 0.39),
                rotation: 4,
                yOffset: -6,
                caption: "Arrows on\nhome row",
                visible: keycapsVisible,
                delay: 0.08
            ) {
                Image(systemName: "arrowkeys.fill")
                    .font(.system(size: 24, weight: .semibold))
            }
            HeroKeycap(
                fill: Color(red: 0.55, green: 0.49, blue: 0.91),
                rotation: -3,
                yOffset: 4,
                caption: "Tile\nwindows",
                visible: keycapsVisible,
                delay: 0.16
            ) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            HeroKeycap(
                fill: Color(red: 0.93, green: 0.55, blue: 0.18),
                rotation: 6,
                yOffset: -4,
                caption: "Launch\nanything",
                visible: keycapsVisible,
                delay: 0.24
            ) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "KeyPath superpowers: supercharge Caps Lock, arrows on the home row, tile windows without the mouse, launch anything from a key"
        )
        .accessibilityIdentifier("wizard-welcome-hero")
    }

    // MARK: - Title + value

    private var titleBlock: some View {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
            Text("Welcome to KeyPath")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)

            Text("Keys that do more.")
                .font(.title3.weight(.regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wizard-welcome-title")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Footer: expectation + CTA

    private var footer: some View {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
            Text("Setup takes about two minutes. We'll guide you through each step.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wizard-welcome-expectation")

            HStack(spacing: WizardDesign.Spacing.labelGap) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text("Private by design — your keystrokes never leave your Mac.")
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("wizard-welcome-privacy")
            .padding(.bottom, WizardDesign.Spacing.elementGap)

            WizardButton("Get Started", style: .primary, isDefaultAction: true) {
                onGetStarted()
            }
        }
    }

    // MARK: - Entrance

    private func animateKeycapsIn() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            keycapsVisible = true
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                keycapsVisible = true
            }
        }
    }
}

// MARK: - Hero Keycap

/// A single oversized keycap in the live-overlay visual language: rounded,
/// saturated fill, white glyph, soft colored shadow, playful tilt.
private struct HeroKeycap<Glyph: View>: View {
    let fill: Color
    let rotation: Double
    let yOffset: CGFloat
    let caption: String
    let visible: Bool
    let delay: Double
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [fill.opacity(0.92), fill],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: fill.opacity(0.45), radius: 10, x: 0, y: 6)

                glyph()
                    .foregroundColor(.white)
            }
            .frame(width: 84, height: 84)
            .rotationEffect(.degrees(rotation))

            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .offset(y: yOffset)
        .scaleEffect(visible ? 1 : 0.6)
        .opacity(visible ? 1 : 0)
        .animation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? nil
                : .spring(response: 0.55, dampingFraction: 0.72).delay(delay),
            value: visible
        )
        .accessibilityHidden(true) // Combined label on the hero container
    }
}
