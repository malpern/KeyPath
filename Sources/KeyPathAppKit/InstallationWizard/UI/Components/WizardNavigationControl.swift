import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// System Preferences-style navigation control for wizard detail pages
/// Automatically reads navigation state from environment
struct WizardNavigationControl: View {
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Left arrow
            Button(action: {
                if let previous = navigationCoordinator.previousPage {
                    navigationCoordinator.navigateToPage(previous)
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium)) // 25% larger (11 * 1.25 = 13.75 ≈ 14)
                    .foregroundColor(navigationCoordinator.canNavigateBack ? .primary : .secondary.opacity(0.4))
                    .frame(width: 25, height: 25) // 25% larger (20 * 1.25 = 25)
            }
            .buttonStyle(.plain)
            .disabled(!navigationCoordinator.canNavigateBack)

            // Separator
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 0.5, height: 18) // Slightly taller to match larger control

            // Right arrow
            Button(action: {
                if let next = navigationCoordinator.nextPage {
                    navigationCoordinator.navigateToPage(next)
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium)) // 25% larger
                    .foregroundColor(navigationCoordinator.canNavigateForward ? .primary : .secondary.opacity(0.4))
                    .frame(width: 25, height: 25) // 25% larger
            }
            .buttonStyle(.plain)
            .disabled(!navigationCoordinator.canNavigateForward)
        }
        .padding(.horizontal, 6) // Increased from 4 (25% larger + extra)
        .padding(.vertical, 3) // Increased from 2 (25% larger + extra)
        .background(
            RoundedRectangle(cornerRadius: 5) // Slightly larger corner radius
                .fill(isHovering ? Color(NSColor.controlBackgroundColor).opacity(0.9) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isHovering ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

/// ViewModifier that adds navigation control overlay to wizard detail pages
struct WizardDetailPageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                WizardNavigationControl()
                    .padding(.top, WizardDesign.Spacing.navigationControlTop + 4) // Extra padding from edge
                    .padding(.leading, WizardDesign.Spacing.navigationControlLeading + 4) // Extra padding from edge
            }
    }
}

extension View {
    /// Adds the standard navigation control overlay to wizard detail pages
    func wizardDetailPage() -> some View {
        modifier(WizardDetailPageModifier())
    }
}

/// Close button for wizard detail pages with hover state
struct CloseButton: View {
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @State private var isHovering = false

    var body: some View {
        Button {
            navigationCoordinator.navigateToPage(.summary)
            AppLogger.shared.log("✖️ [Wizard] Close pressed — navigating to summary")
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12.5, weight: .medium)) // 25% larger (10 * 1.25 = 12.5)
                .foregroundColor(.primary) // Adapts to dark mode
                .frame(width: 20, height: 20) // 25% larger (16 * 1.25 = 20)
                .background(
                    Circle()
                        .fill(isHovering ? Color(NSColor.secondaryLabelColor).opacity(0.8) : Color(NSColor.secondaryLabelColor))
                )
        }
        .buttonStyle(.plain)
        .help("Return to Overview")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
