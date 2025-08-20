import SwiftUI

/// Comprehensive design system for the Installation Wizard
/// Provides consistent spacing, colors, typography, and component styling
enum WizardDesign {
    // MARK: - Spacing & Layout

    enum Spacing {
        /// Large vertical spacing for page sections
        static let pageVertical: CGFloat = 20 // Reduced from 32

        /// Medium spacing between major sections
        static let sectionGap: CGFloat = 16 // Reduced from 24

        /// Standard spacing between related items
        static let itemGap: CGFloat = 12 // Reduced from 16

        /// Small spacing for tightly grouped elements
        static let elementGap: CGFloat = 8 // Reduced from 12

        /// Minimal spacing for labels and values
        static let labelGap: CGFloat = 6 // Reduced from 8

        /// Card internal padding
        static let cardPadding: CGFloat = 16 // Reduced from 20

        /// Button internal padding
        static let buttonPadding: CGFloat = 12 // Reduced from 16

        /// Icon spacing from text
        static let iconGap: CGFloat = 12

        /// Indentation for sub-items
        static let indentation: CGFloat = 16
    }

    enum Layout {
        /// Standard wizard page width
        static let pageWidth: CGFloat = 700

        /// Standard wizard page height
        static let pageHeight: CGFloat = 680 // Reduced from 750 to fit content

        /// Maximum content width for readability
        static let maxContentWidth: CGFloat = 400

        /// Standard card width
        static let cardWidth: CGFloat = 400

        /// Large button width
        static let buttonWidthLarge: CGFloat = 300

        /// Medium button width
        static let buttonWidthMedium: CGFloat = 200

        /// Small button width (for compact buttons)
        static let buttonWidthSmall: CGFloat = 100

        /// Extra small button width (for icons/short text)
        static let buttonWidthExtraSmall: CGFloat = 80

        /// Icon size for wizard elements
        static let iconSize: CGFloat = 48

        /// Small icon size for status indicators
        static let iconSizeSmall: CGFloat = 16

        /// Status circle size
        static let statusCircleSize: CGFloat = 60 // Reduced from 80

        /// Standard corner radius for wizard components
        static let cornerRadius: CGFloat = 8
    }

    // MARK: - Colors

    enum Colors {
        /// Success state color
        static let success = Color.green

        /// Warning state color
        static let warning = Color.orange

        /// Error state color
        static let error = Color.red

        /// Critical error color
        static let critical = Color.purple

        /// Information color
        static let info = Color.blue

        /// In-progress/loading color
        static let inProgress = Color.blue

        /// Background for cards and sections
        static let cardBackground = Color(.controlBackgroundColor)

        /// Background for the entire wizard
        static let wizardBackground = Color(.windowBackgroundColor)

        /// Subtle borders and dividers
        static let border = Color(.separatorColor)

        /// Primary action color (matches accent)
        static let primaryAction = Color.accentColor

        /// Secondary text color
        static let secondaryText = Color.secondary

        /// Disabled element color
        static let disabled = Color(.disabledControlTextColor)
    }

    // MARK: - Typography

    enum Typography {
        /// Page titles (Welcome to KeyPath)
        static let pageTitle = Font.title.weight(.semibold)

        /// Section titles (System Status Overview)
        static let sectionTitle = Font.title2.weight(.semibold)

        /// Subsection headers (System Permissions)
        static let subsectionTitle = Font.headline

        /// Body text for descriptions
        static let body = Font.body

        /// Small descriptive text
        static let caption = Font.caption

        /// Button text
        static let button = Font.body.weight(.medium)

        /// Status text (Success, Failed, etc.)
        static let status = Font.subheadline.weight(.medium)

        /// Page subtitle/description
        static let subtitle = Font.body
    }

    // MARK: - Animation

    enum Animation {
        /// Standard page transition duration
        static let pageTransition: Double = 0.3

        /// Quick feedback animation
        static let feedback: Double = 0.2

        /// Loading/progress animation
        static let loading: Double = 1.0

        /// Status change animation
        static let statusChange: Double = 0.4

        /// Standard easing for page transitions
        static let pageEasing: SwiftUI.Animation = .easeInOut(duration: pageTransition)

        /// Quick bounce for button presses
        static let buttonFeedback: SwiftUI.Animation = .easeInOut(duration: feedback)

        /// Smooth status transitions
        static let statusTransition: SwiftUI.Animation = .easeInOut(duration: statusChange)
    }

    // MARK: - Component Styles

    enum Component {
        /// Standard card style for wizard sections
        struct Card: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(WizardDesign.Colors.cardBackground)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }

        /// Status indicator style
        struct StatusIndicator: ViewModifier {
            let status: InstallationStatus

            func body(content: Content) -> some View {
                content
                    .foregroundColor(colorForStatus(status))
                    .font(WizardDesign.Typography.status)
            }

            private func colorForStatus(_ status: InstallationStatus) -> Color {
                switch status {
                case .notStarted: WizardDesign.Colors.secondaryText
                case .inProgress: WizardDesign.Colors.inProgress
                case .completed: WizardDesign.Colors.success
                case .failed: WizardDesign.Colors.error
                }
            }
        }

        /// Primary button style
        struct PrimaryButton: ButtonStyle {
            let isLoading: Bool

            init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            func makeBody(configuration: Configuration) -> some View {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        configuration.label
                    }
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(.white)
                .frame(minWidth: 120, minHeight: 26) // Fixed minimum dimensions for primary buttons (20% height reduction)
                .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                .padding(.vertical, WizardDesign.Spacing.elementGap)
                .background(WizardDesign.Colors.primaryAction)
                .cornerRadius(8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                .disabled(isLoading)
            }
        }

        /// Secondary button style
        struct SecondaryButton: ButtonStyle {
            let isLoading: Bool

            init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            func makeBody(configuration: Configuration) -> some View {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        configuration.label
                    }
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(WizardDesign.Colors.primaryAction)
                .frame(minWidth: 120, minHeight: 26) // Match primary button dimensions
                .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                .padding(.vertical, WizardDesign.Spacing.elementGap)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WizardDesign.Colors.primaryAction, lineWidth: 1.5)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                .disabled(isLoading)
            }
        }

        /// Destructive button style (for dangerous actions)
        struct DestructiveButton: ButtonStyle {
            let isLoading: Bool

            init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            func makeBody(configuration: Configuration) -> some View {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        configuration.label
                    }
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(.white)
                .frame(minWidth: 120, minHeight: 26) // Fixed minimum dimensions (20% height reduction)
                .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                .padding(.vertical, WizardDesign.Spacing.elementGap)
                .background(WizardDesign.Colors.error)
                .cornerRadius(8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                .disabled(isLoading)
            }
        }

        // MARK: - Experimental Hero Layout Components

        /// Large centered hero section with icon, headline, and supporting copy
        struct HeroSection: View {
            let icon: String
            let iconColor: Color
            let headline: String
            let subtitle: String

            var body: some View {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Large icon (115pt)
                        Image(systemName: icon)
                            .font(.system(size: 115, weight: .light))
                            .foregroundColor(iconColor)
                            .symbolRenderingMode(.hierarchical)

                        // Large headline (23pt)
                        Text(headline)
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Supporting copy (17pt)
                        Text(subtitle)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        /// Ultra-compact content card for additional information
        struct CompactContentCard: View {
            let content: String
            let alignment: TextAlignment

            init(content: String, alignment: TextAlignment = .leading) {
                self.content = content
                self.alignment = alignment
            }

            var body: some View {
                VStack(alignment: alignment == .center ? .center : .leading, spacing: WizardDesign.Spacing.itemGap) {
                    Text(content)
                        .font(WizardDesign.Typography.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)

                    // Minimal spacer (6pt)
                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity)
                .padding(WizardDesign.Spacing.cardPadding)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply wizard card styling
    func wizardCard() -> some View {
        modifier(WizardDesign.Component.Card())
    }

    /// Apply status indicator styling
    func wizardStatusIndicator(_ status: InstallationStatus) -> some View {
        modifier(WizardDesign.Component.StatusIndicator(status: status))
    }

    /// Apply standard wizard page padding
    func wizardPagePadding() -> some View {
        padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.vertical, WizardDesign.Spacing.sectionGap)
    }

    /// Apply standard wizard content spacing
    func wizardContentSpacing() -> some View {
        frame(maxWidth: WizardDesign.Layout.maxContentWidth)
    }
}

// MARK: - Standardized Components

/// Reusable wizard button component
struct WizardButton: View {
    let title: String
    let style: ButtonStyle
    let isLoading: Bool
    let action: () async -> Void

    enum ButtonStyle {
        case primary, secondary, destructive
    }

    init(
        _ title: String, style: ButtonStyle = .primary, isLoading: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        switch style {
        case .primary:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isLoading))
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(isLoading ? "Operation in progress" : "Tap to \(title.lowercased())")
        case .secondary:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton(isLoading: isLoading))
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(isLoading ? "Operation in progress" : "Tap to \(title.lowercased())")
        case .destructive:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: isLoading))
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(
                isLoading
                    ? "Operation in progress"
                    : "Tap to \(title.lowercased()). This action may cause data loss.")
        }
    }
}

/// Reusable wizard status item component
struct WizardStatusItem: View {
    let icon: String
    let title: String
    let subtitle: String?
    let status: InstallationStatus
    let isNavigable: Bool
    let action: (() -> Void)?

    init(
        icon: String, title: String, subtitle: String? = nil, status: InstallationStatus,
        isNavigable: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.action = action
    }

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
            // Main icon only (no status icon on left)
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.system(size: 16))
                .frame(width: 20)

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WizardDesign.Typography.body)
                    .foregroundColor(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // All status indicators on the right
            HStack(spacing: 8) {
                // Status indicator - icon for all states
                Group {
                    if status == .notStarted {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.system(size: 16))
                            .symbolEffect(.bounce.up, options: .repeating)
                            .symbolEffect(.pulse.byLayer, options: .repeating)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.system(size: 16))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }

                // Navigation indicator
                if isNavigable {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, WizardDesign.Spacing.labelGap)
        .contentShape(Rectangle())
        .onTapGesture {
            if isNavigable {
                action?()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(statusText)")
        .accessibilityHint(isNavigable ? "Tap to navigate to \(title) page" : "")
    }

    private var statusIcon: String {
        switch status {
        case .notStarted: "circle"
        case .inProgress: "clock"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notStarted: WizardDesign.Colors.secondaryText
        case .inProgress: WizardDesign.Colors.inProgress
        case .completed: WizardDesign.Colors.success
        case .failed: WizardDesign.Colors.error
        }
    }

    private var statusText: String {
        switch status {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

/// Wizard page header component
struct WizardPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: HeaderStatus

    enum HeaderStatus {
        case success, warning, error, info

        var color: Color {
            switch self {
            case .success: WizardDesign.Colors.success
            case .warning: WizardDesign.Colors.warning
            case .error: WizardDesign.Colors.error
            case .info: WizardDesign.Colors.info
            }
        }
    }

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.1))
                    .frame(
                        width: WizardDesign.Layout.statusCircleSize,
                        height: WizardDesign.Layout.statusCircleSize
                    )

                Image(systemName: icon)
                    .font(.system(size: 32)) // Reduced from iconSize (48)
                    .foregroundColor(status.color)
                    .symbolRenderingMode(.multicolor)
            }

            // Title
            Text(title)
                .font(WizardDesign.Typography.sectionTitle)
                .fontWeight(.semibold)

            // Subtitle
            Text(subtitle)
                .font(WizardDesign.Typography.subtitle)
                .foregroundColor(WizardDesign.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .wizardContentSpacing()
        }
        .padding(.top, 12) // Reduced padding
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }
}
