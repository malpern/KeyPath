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

        /// Icon overlay positioning
        static let overlayOffsetLarge: (x: CGFloat, y: CGFloat) = (15, -5)
        static let overlayOffsetSmall: (x: CGFloat, y: CGFloat) = (8, -3)

        /// Text line spacing (between title and subtitle)
        static let textLineSpacing: CGFloat = 2
    }

    enum Toast {
        /// Maximum toast width
        static let maxWidth: CGFloat = Layout.cardWidth

        /// Toast durations
        enum Duration {
            static let info: TimeInterval = 3.0
            static let error: TimeInterval = 4.0
            static let launchFailure: TimeInterval = 12.0
        }
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

        /// Hero icon sizes
        static let heroIconSize: CGFloat = 115
        static let compactIconSize: CGFloat = 60

        /// Icon overlay sizes
        static let heroOverlaySize: CGFloat = 40
        static let compactOverlaySize: CGFloat = 24

        /// Icon container frame widths (to accommodate offsets)
        static let heroIconFrameWidth: CGFloat = 155
        static let compactIconFrameWidth: CGFloat = 75

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

        /// Icon overlay transition
        static let overlayTransition: Double = 0.2

        /// Standard easing for page transitions
        static let pageEasing: SwiftUI.Animation = .easeInOut(duration: pageTransition)

        /// Quick bounce for button presses
        static let buttonFeedback: SwiftUI.Animation = .easeInOut(duration: feedback)

        /// Smooth status transitions
        static let statusTransition: SwiftUI.Animation = .easeInOut(duration: statusChange)

        /// Icon overlay animations
        static let overlayChange: SwiftUI.Animation = .easeInOut(duration: overlayTransition)

        /// Hero icon entrance effect
        static let heroIconEntrance: SwiftUI.Animation = .spring(response: 0.6, dampingFraction: 0.8)
    }

    // MARK: - Symbol Effects

    // Note: Symbol effects are used directly in components due to Swift type system constraints

    // MARK: - Transitions

    @MainActor enum Transition {
        /// Card appearance from top
        static let cardAppear: AnyTransition = .opacity.combined(with: .move(edge: .top))

        /// Overlay icon changes
        static let overlayChange: AnyTransition = .opacity.combined(with: .scale(scale: 0.8))

        /// Technical details expansion
        static let detailsExpand: AnyTransition = .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
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

        /// Toast card style for overlay notifications
        struct ToastCard: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WizardDesign.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: WizardDesign.Layout.cornerRadius)
                            .stroke(WizardDesign.Colors.border.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: WizardDesign.Toast.maxWidth)
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

        // MARK: - Hero Layout Components

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

        /// Hero section layout component that eliminates duplication across wizard pages
        struct HeroSection: View {
            let icon: String
            let title: String
            let subtitle: String
            let status: HeroStatus
            let actionLinks: [ActionLink]?
            let contentCard: (() -> AnyView)?

            enum HeroStatus {
                case success(Color = WizardDesign.Colors.success)
                case warning(Color = WizardDesign.Colors.warning)
                case error(Color = WizardDesign.Colors.error)
                case info(Color = WizardDesign.Colors.info)

                var color: Color {
                    switch self {
                    case let .success(color): color
                    case let .warning(color): color
                    case let .error(color): color
                    case let .info(color): color
                    }
                }

                var overlayIcon: String {
                    switch self {
                    case .success: "checkmark.circle.fill"
                    case .warning: "exclamationmark.triangle.fill"
                    case .error: "xmark.circle.fill"
                    case .info: "info.circle.fill"
                    }
                }
            }

            struct ActionLink {
                let title: String
                let action: () -> Void
            }

            init(
                icon: String,
                title: String,
                subtitle: String,
                status: HeroStatus,
                actionLinks: [ActionLink]? = nil,
                contentCard: (() -> AnyView)? = nil
            ) {
                self.icon = icon
                self.title = title
                self.subtitle = subtitle
                self.status = status
                self.actionLinks = actionLinks
                self.contentCard = contentCard
            }

            var body: some View {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Standardized icon with overlay
                        IconWithOverlay(
                            mainIcon: icon,
                            overlayIcon: status.overlayIcon,
                            mainColor: status.color,
                            overlayColor: status.color,
                            size: .hero,
                            transparentOverlay: true
                        )

                        // Standardized title (23pt)
                        Text(title)
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Standardized subtitle (17pt)
                        Text(subtitle)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Action links below the subheader (if provided)
                        if let actionLinks, !actionLinks.isEmpty {
                            HStack(spacing: WizardDesign.Spacing.itemGap) {
                                ForEach(Array(actionLinks.enumerated()), id: \.offset) { index, link in
                                    if index > 0 {
                                        Text("•")
                                            .foregroundColor(.secondary)
                                    }

                                    Button(link.title) {
                                        link.action()
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                            .padding(.top, WizardDesign.Spacing.elementGap)
                        }

                        // Optional content card
                        if let contentCard {
                            contentCard()
                                .padding(.top, WizardDesign.Spacing.sectionGap)
                        }
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        /// Standardized icon with overlay for consistent positioning across wizard pages
        struct IconWithOverlay: View {
            let mainIcon: String
            let overlayIcon: String
            let mainColor: Color
            let overlayColor: Color
            let size: IconSize
            let transparentOverlay: Bool

            enum IconSize {
                case hero, compact

                var mainSize: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroIconSize
                    case .compact: WizardDesign.Layout.compactIconSize
                    }
                }

                var overlaySize: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroOverlaySize
                    case .compact: WizardDesign.Layout.compactOverlaySize
                    }
                }

                var frameWidth: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroIconFrameWidth
                    case .compact: WizardDesign.Layout.compactIconFrameWidth
                    }
                }

                var offset: (x: CGFloat, y: CGFloat) {
                    switch self {
                    case .hero: WizardDesign.Spacing.overlayOffsetLarge
                    case .compact: WizardDesign.Spacing.overlayOffsetSmall
                    }
                }
            }

            init(
                mainIcon: String,
                overlayIcon: String,
                mainColor: Color,
                overlayColor: Color,
                size: IconSize,
                transparentOverlay: Bool = true
            ) {
                self.mainIcon = mainIcon
                self.overlayIcon = overlayIcon
                self.mainColor = mainColor
                self.overlayColor = overlayColor
                self.size = size
                self.transparentOverlay = transparentOverlay
            }

            var body: some View {
                ZStack {
                    // Main icon
                    Image(systemName: mainIcon)
                        .font(.system(size: size.mainSize, weight: .light))
                        .foregroundColor(mainColor)
                        .symbolRenderingMode(.hierarchical)
                        .modifier(AvailabilitySymbolBounce())

                    // Overlay icon in top right
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: overlayIcon)
                                .font(.system(size: size.overlaySize, weight: .medium))
                                .foregroundColor(overlayColor)
                                .background(
                                    transparentOverlay
                                        ? Color.clear
                                        : WizardDesign.Colors.wizardBackground
                                )
                                .clipShape(Circle())
                                .offset(x: size.offset.x, y: size.offset.y)
                                .transition(WizardDesign.Transition.overlayChange)
                        }
                        Spacer()
                    }
                    .frame(width: size.frameWidth, height: size.mainSize)
                }
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

    /// Apply toast card styling
    func wizardToastCard() -> some View {
        modifier(WizardDesign.Component.ToastCard())
    }
}

// MARK: - Availability-safe symbol effect helper

struct AvailabilitySymbolBounce: ViewModifier {
    let repeating: Bool

    init(repeating: Bool = false) {
        self.repeating = repeating
    }

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            if repeating {
                content.symbolEffect(.bounce, options: .repeating)
            } else {
                content.symbolEffect(.bounce, options: .nonRepeating)
            }
        } else {
            content
        }
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

/// Reusable wizard status item component with animated status transitions
struct WizardStatusItem: View {
    let icon: String
    let title: String
    let subtitle: String?
    let status: InstallationStatus
    let isNavigable: Bool
    let action: (() -> Void)?
    let isFinalStatus: Bool
    let showInitialClock: Bool

    init(
        icon: String, title: String, subtitle: String? = nil, status: InstallationStatus,
        isNavigable: Bool = false,
        action: (() -> Void)? = nil,
        isFinalStatus: Bool = false,
        showInitialClock: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.action = action
        self.isFinalStatus = isFinalStatus
        self.showInitialClock = showInitialClock
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
                // Enhanced animated status indicator
                AnimatedStatusIcon(
                    status: status,
                    isFinalStatus: isFinalStatus,
                    showInitialClock: showInitialClock
                )

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

    private var statusText: String {
        switch status {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

/// Animated status icon that shows clock -> colored final state transitions
struct AnimatedStatusIcon: View {
    let status: InstallationStatus
    let isFinalStatus: Bool
    let showInitialClock: Bool

    @State private var hasAnimated = false

    init(status: InstallationStatus, isFinalStatus: Bool = false, showInitialClock: Bool = false) {
        self.status = status
        self.isFinalStatus = isFinalStatus
        self.showInitialClock = showInitialClock
    }

    var body: some View {
        Group {
            if showInitialClock, status == .completed || status == .failed {
                // Clock-to-final-state animation for completed/failed items
                if hasAnimated {
                    // Final state
                    Image(systemName: finalStateIcon)
                        .foregroundColor(finalStateColor)
                        .font(.system(size: 16))
                        .modifier(AvailabilitySymbolBounce())
                        .modifier(AvailabilitySymbolBounce(repeating: isFinalStatus))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                            removal: .opacity
                        ))
                } else {
                    // Initial clock state
                    Image(systemName: "clock.fill")
                        .foregroundColor(WizardDesign.Colors.inProgress)
                        .font(.system(size: 16))
                        .onAppear {
                            // Animate to final state immediately (no delay)
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                hasAnimated = true
                            }
                        }
                }
            } else {
                // Standard behavior for other states
                switch status {
                case .notStarted:
                    // Empty circle
                    Image(systemName: "circle")
                        .foregroundColor(WizardDesign.Colors.secondaryText)
                        .font(.system(size: 16))

                case .inProgress:
                    // Animated clock
                    Image(systemName: "clock.fill")
                        .foregroundColor(WizardDesign.Colors.inProgress)
                        .font(.system(size: 16))

                case .completed:
                    // Direct green checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(WizardDesign.Colors.success)
                        .font(.system(size: 16))
                        .modifier(AvailabilitySymbolBounce())
                        .modifier(AvailabilitySymbolBounce(repeating: isFinalStatus))

                case .failed:
                    // Direct red X
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(WizardDesign.Colors.error)
                        .font(.system(size: 16))
                        .modifier(AvailabilitySymbolBounce())
                }
            }
        }
    }

    private var finalStateIcon: String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        default: "circle"
        }
    }

    private var finalStateColor: Color {
        switch status {
        case .completed: WizardDesign.Colors.success
        case .failed: WizardDesign.Colors.error
        default: WizardDesign.Colors.secondaryText
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
