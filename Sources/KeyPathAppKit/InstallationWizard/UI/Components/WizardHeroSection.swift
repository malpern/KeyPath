import SwiftUI

/// Reusable hero section component for wizard pages
/// Provides consistent icon, title, subtitle, and optional action button layout
struct WizardHeroSection: View {
    // MARK: - Configuration

    let icon: String
    let iconColor: Color
    let overlayIcon: String?
    let overlayColor: Color?
    let overlaySize: OverlaySize
    let title: String
    let subtitle: String
    let actionButtonTitle: String?
    let actionButtonAction: (() -> Void)?
    let iconTapAction: (() -> Void)?

    // MARK: - State

    @State private var iconHovering: Bool = false

    enum OverlaySize {
        case large // 40pt icon, offset(x: 15, y: -5), frame(140x115)
        case small // 24pt icon, offset(x: 8, y: -3), frame(60x60)
    }

    // MARK: - Initialization

    init(
        icon: String,
        iconColor: Color,
        overlayIcon: String? = nil,
        overlayColor: Color? = nil,
        overlaySize: OverlaySize = .large,
        title: String,
        subtitle: String,
        actionButtonTitle: String? = nil,
        actionButtonAction: (() -> Void)? = nil,
        iconTapAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.overlayIcon = overlayIcon
        self.overlayColor = overlayColor
        self.overlaySize = overlaySize
        self.title = title
        self.subtitle = subtitle
        self.actionButtonTitle = actionButtonTitle
        self.actionButtonAction = actionButtonAction
        self.iconTapAction = iconTapAction
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Icon with optional overlay
            iconView

            // Title
            Text(title)
                .font(.system(size: 23, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Optional action button
            if let actionButtonTitle, let actionButtonAction {
                Button(action: actionButtonAction) {
                    Text(actionButtonTitle)
                }
                .buttonStyle(.link)
            }
        }
        // Padding removed - pages control padding via heroSectionContainer() modifier
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        if let iconTapAction {
            Button(action: iconTapAction) {
                iconStack
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                iconHovering = hovering
            }
            .accessibilityLabel("Open \(title)")
        } else {
            iconStack
        }
    }

    private var iconStack: some View {
        ZStack {
            // Hover ring - only show if icon is tappable
            if iconTapAction != nil {
                Circle()
                    .stroke(Color.primary.opacity(iconHovering ? 0.15 : 0.0), lineWidth: 2)
                    .frame(width: 123, height: 123) // 115 + 8
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.2), value: iconHovering)
            }

            // Main icon
            Image(systemName: icon)
                .font(.system(size: 115, weight: .light))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .modifier(AvailabilitySymbolBounce())

            // Overlay icon (if provided)
            if let overlayIcon, let overlayColor {
                overlayIconView(icon: overlayIcon, color: overlayColor)
            }
        }
        .contentShape(Circle())
    }

    @ViewBuilder
    private func overlayIconView(icon: String, color: Color) -> some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: overlaySize == .large ? 40 : 24, weight: .medium))
                    .foregroundStyle(color)
                    .background(WizardDesign.Colors.wizardBackground)
                    .clipShape(Circle())
                    .offset(
                        x: overlaySize == .large ? 10 : 8,
                        y: overlaySize == .large ? -4 : -3
                    )
            }
            Spacer()
        }
        .frame(
            width: overlaySize == .large ? 115 : 60,
            height: overlaySize == .large ? 115 : 60
        )
    }
}

// MARK: - Convenience Initializers

extension WizardHeroSection {
    /// Convenience initializer for success state with large checkmark overlay
    static func success(
        icon: String,
        title: String,
        subtitle: String,
        actionButtonTitle: String? = nil,
        actionButtonAction: (() -> Void)? = nil,
        iconTapAction: (() -> Void)? = nil
    ) -> WizardHeroSection {
        WizardHeroSection(
            icon: icon,
            iconColor: WizardDesign.Colors.success,
            overlayIcon: "checkmark.circle.fill",
            overlayColor: WizardDesign.Colors.success,
            overlaySize: .large,
            title: title,
            subtitle: subtitle,
            actionButtonTitle: actionButtonTitle,
            actionButtonAction: actionButtonAction,
            iconTapAction: iconTapAction
        )
    }

    /// Convenience initializer for warning state with small warning overlay
    static func warning(
        icon: String,
        title: String,
        subtitle: String,
        actionButtonTitle: String? = nil,
        actionButtonAction: (() -> Void)? = nil,
        iconTapAction: (() -> Void)? = nil
    ) -> WizardHeroSection {
        WizardHeroSection(
            icon: icon,
            iconColor: WizardDesign.Colors.warning,
            overlayIcon: "exclamationmark.circle.fill",
            overlayColor: WizardDesign.Colors.warning,
            overlaySize: .large,
            title: title,
            subtitle: subtitle,
            actionButtonTitle: actionButtonTitle,
            actionButtonAction: actionButtonAction,
            iconTapAction: iconTapAction
        )
    }

    /// Convenience initializer for error state with small error overlay
    static func error(
        icon: String,
        title: String,
        subtitle: String,
        actionButtonTitle: String? = nil,
        actionButtonAction: (() -> Void)? = nil,
        iconTapAction: (() -> Void)? = nil
    ) -> WizardHeroSection {
        WizardHeroSection(
            icon: icon,
            iconColor: WizardDesign.Colors.error,
            overlayIcon: "xmark.circle.fill",
            overlayColor: WizardDesign.Colors.error,
            overlaySize: .large,
            title: title,
            subtitle: subtitle,
            actionButtonTitle: actionButtonTitle,
            actionButtonAction: actionButtonAction,
            iconTapAction: iconTapAction
        )
    }
}

// MARK: - Inline Status View

/// Displays inline status feedback below content
/// Used as a replacement for toast notifications
struct InlineStatusView: View {
    let status: WizardDesign.ActionStatus
    let message: String

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.elementGap) {
            // Status indicator (spinner or icon)
            Group {
                switch status {
                case .inProgress:
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)

                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WizardDesign.Colors.success)

                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WizardDesign.Colors.error)

                case .idle:
                    EmptyView()
                }
            }

            // Status message
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(status.color)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, WizardDesign.Spacing.cardPadding)
        .padding(.vertical, WizardDesign.Spacing.elementGap)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status.color.opacity(0.1))
        )
    }
}
