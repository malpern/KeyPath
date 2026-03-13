import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Comprehensive design system for the Installation Wizard
/// Provides consistent spacing, colors, typography, and component styling
public enum WizardDesign {
    // MARK: - Spacing & Layout

    public enum Spacing {
        /// Large vertical spacing for page sections
        public static let pageVertical: CGFloat = 20 // Reduced from 32

        /// Medium spacing between major sections
        public static let sectionGap: CGFloat = 16 // Reduced from 24

        /// Standard spacing between related items
        public static let itemGap: CGFloat = 12 // Reduced from 16

        /// Small spacing for tightly grouped elements
        public static let elementGap: CGFloat = 8 // Reduced from 12

        /// Minimal spacing for labels and values
        public static let labelGap: CGFloat = 6 // Reduced from 8

        /// Card internal padding
        public static let cardPadding: CGFloat = 16 // Reduced from 20

        /// Button internal padding
        public static let buttonPadding: CGFloat = 12 // Reduced from 16

        /// Icon spacing from text
        public static let iconGap: CGFloat = 12

        /// Indentation for sub-items
        public static let indentation: CGFloat = 16

        /// Icon overlay positioning
        public static let overlayOffsetLarge: (x: CGFloat, y: CGFloat) = (15, -5)
        public static let overlayOffsetSmall: (x: CGFloat, y: CGFloat) = (8, -3)

        /// Text line spacing (between title and subtitle)
        public static let textLineSpacing: CGFloat = 2

        /// Navigation control positioning
        public static let navigationControlTop: CGFloat = 8
        public static let navigationControlLeading: CGFloat = 8
    }

    public enum Toast {
        /// Maximum toast width
        public static let maxWidth: CGFloat = Layout.cardWidth

        /// Toast durations
        public enum Duration {
            public static let info: TimeInterval = 3.0
            public static let error: TimeInterval = 4.0
            public static let launchFailure: TimeInterval = 12.0
        }
    }

    public enum Layout {
        /// Standard wizard page width
        public static let pageWidth: CGFloat = 700

        /// Standard wizard page height (shorter to allow scrolling lists)
        public static let pageHeight: CGFloat = 270

        /// Maximum content width for readability
        public static let maxContentWidth: CGFloat = 400

        /// Standard card width
        public static let cardWidth: CGFloat = 400

        /// Large button width
        public static let buttonWidthLarge: CGFloat = 300

        /// Medium button width
        public static let buttonWidthMedium: CGFloat = 200

        /// Small button width (for compact buttons)
        public static let buttonWidthSmall: CGFloat = 100

        /// Extra small button width (for icons/short text)
        public static let buttonWidthExtraSmall: CGFloat = 80

        /// Icon size for wizard elements
        public static let iconSize: CGFloat = 48

        /// Small icon size for status indicators
        public static let iconSizeSmall: CGFloat = 16

        /// Status circle size
        public static let statusCircleSize: CGFloat = 60 // Reduced from 80

        /// Hero icon sizes
        public static let heroIconSize: CGFloat = 115
        public static let compactIconSize: CGFloat = 60

        /// Icon overlay sizes
        public static let heroOverlaySize: CGFloat = 40
        public static let compactOverlaySize: CGFloat = 24

        /// Icon container frame widths (to accommodate offsets)
        public static let heroIconFrameWidth: CGFloat = 155
        public static let compactIconFrameWidth: CGFloat = 75

        /// Standard corner radius for wizard components
        public static let cornerRadius: CGFloat = 8
    }

    // MARK: - Colors

    public enum Colors {
        /// Success state color
        public static let success = Color.green

        /// Warning state color
        public static let warning = Color.orange

        /// Error state color
        public static let error = Color.red

        /// Critical error color
        public static let critical = Color.purple

        /// Information color
        public static let info = Color.blue

        /// In-progress/loading color
        public static let inProgress = Color.blue

        /// Background for cards and sections
        public static let cardBackground = Color(.controlBackgroundColor)

        /// Background for the entire wizard
        public static let wizardBackground = Color(.windowBackgroundColor)

        /// Subtle borders and dividers
        public static let border = Color(.separatorColor)

        /// Primary action color (matches accent)
        public static let primaryAction = Color.accentColor

        /// Secondary text color
        public static let secondaryText = Color.secondary

        /// Disabled element color
        public static let disabled = Color(.disabledControlTextColor)
    }

    // MARK: - Typography

    public enum Typography {
        /// Page titles (Welcome to KeyPath)
        public static let pageTitle = Font.title.weight(.semibold)

        /// Section titles (System Status Overview)
        public static let sectionTitle = Font.title2.weight(.semibold)

        /// Subsection headers (System Permissions)
        public static let subsectionTitle = Font.headline

        /// Body text for descriptions
        public static let body = Font.body

        /// Small descriptive text
        public static let caption = Font.caption

        /// Button text
        public static let button = Font.body.weight(.medium)

        /// Status text (Success, Failed, etc.)
        public static let status = Font.subheadline.weight(.medium)

        /// Page subtitle/description
        public static let subtitle = Font.body
    }

    // MARK: - Animation

    public enum Animation {
        /// Standard page transition duration
        public static let pageTransition: Double = 0.3

        /// Quick feedback animation
        public static let feedback: Double = 0.2

        /// Loading/progress animation
        public static let loading: Double = 1.0

        /// Status change animation
        public static let statusChange: Double = 0.4

        /// Icon overlay transition
        public static let overlayTransition: Double = 0.2

        /// Standard easing for page transitions
        public static let pageEasing: SwiftUI.Animation = .easeInOut(duration: pageTransition)

        /// Quick bounce for button presses
        public static let buttonFeedback: SwiftUI.Animation = .easeInOut(duration: feedback)

        /// Smooth status transitions
        public static let statusTransition: SwiftUI.Animation = .easeInOut(duration: statusChange)

        /// Icon overlay animations
        public static let overlayChange: SwiftUI.Animation = .easeInOut(duration: overlayTransition)

        /// Hero icon entrance effect
        public static let heroIconEntrance: SwiftUI.Animation = .spring(response: 0.6, dampingFraction: 0.8)
    }

    // MARK: - Action Status

    /// Represents the status of an action being performed on a wizard page
    /// Used for inline status feedback (replacing toast notifications)
    public enum ActionStatus: Equatable {
        case idle
        case inProgress(message: String)
        case success(message: String)
        case error(message: String)

        public var isActive: Bool {
            switch self {
            case .idle: false
            case .inProgress, .success, .error: true
            }
        }

        public var message: String? {
            switch self {
            case .idle: nil
            case let .inProgress(message): message
            case let .success(message): message
            case let .error(message): message
            }
        }

        public var color: Color {
            switch self {
            case .idle: .secondary
            case .inProgress: Colors.inProgress
            case .success: Colors.success
            case .error: Colors.error
            }
        }
    }

    // MARK: - Symbol Effects

    // Note: Symbol effects are used directly in components due to Swift type system constraints

    // MARK: - Transitions

    @MainActor enum Transition {
        /// Card appearance from top
        public static let cardAppear: AnyTransition = .opacity.combined(with: .move(edge: .top))

        /// Overlay icon changes
        public static let overlayChange: AnyTransition = .opacity.combined(with: .scale(scale: 0.8))

        /// Technical details expansion
        public static let detailsExpand: AnyTransition = .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )

        /// Page slide forward (next page)
        public static let pageSlideForward: AnyTransition = .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )

        /// Page slide backward (previous page)
        public static let pageSlideBackward: AnyTransition = .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    // MARK: - View Modifiers

    /// Standardized hero section container modifier
    /// Top-aligned with generous padding for visual balance
    public struct HeroSectionContainer: ViewModifier {
        public func body(content: Content) -> some View {
            content
                .padding(.top, 48)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Component Styles

    public enum Component {
        /// Standard card style for wizard sections
        public struct Card: ViewModifier {
            public func body(content: Content) -> some View {
                content
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(WizardDesign.Colors.cardBackground)
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }

        /// Toast card style for overlay notifications
        public struct ToastCard: ViewModifier {
            public func body(content: Content) -> some View {
                content
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: WizardDesign.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: WizardDesign.Layout.cornerRadius)
                            .stroke(WizardDesign.Colors.border.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: WizardDesign.Toast.maxWidth)
            }
        }

        /// Status indicator style
        public struct StatusIndicator: ViewModifier {
            public let status: InstallationStatus

            public func body(content: Content) -> some View {
                content
                    .foregroundColor(colorForStatus(status))
                    .font(WizardDesign.Typography.status)
            }

            private func colorForStatus(_ status: InstallationStatus) -> Color {
                switch status {
                case .notStarted: WizardDesign.Colors.secondaryText
                case .inProgress: WizardDesign.Colors.inProgress
                case .warning: WizardDesign.Colors.warning
                case .completed: WizardDesign.Colors.success
                case .failed: WizardDesign.Colors.error
                case .unverified: WizardDesign.Colors.secondaryText
                }
            }
        }

        /// Primary button style
        public struct PrimaryButton: ButtonStyle {
            public let isLoading: Bool

            public init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            public func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(WizardDesign.Typography.button)
                    .foregroundColor(.white)
                    .frame(minWidth: 120, minHeight: 26) // Fixed minimum dimensions for primary buttons (20% height reduction)
                    .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                    .padding(.vertical, WizardDesign.Spacing.elementGap)
                    .background(WizardDesign.Colors.primaryAction)
                    .clipShape(.rect(cornerRadius: 8))
                    .opacity(isLoading ? 0.85 : 1.0)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                    .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                    .disabled(isLoading)
            }
        }

        /// Secondary button style
        public struct SecondaryButton: ButtonStyle {
            public let isLoading: Bool

            public init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            public func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(WizardDesign.Typography.button)
                    .foregroundColor(
                        configuration.isPressed
                            ? WizardDesign.Colors.wizardBackground // Invert for clear pressed feedback
                            : WizardDesign.Colors.primaryAction
                    )
                    .frame(minWidth: 120, minHeight: 26) // Match primary button dimensions
                    .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                    .padding(.vertical, WizardDesign.Spacing.elementGap)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(configuration.isPressed ? WizardDesign.Colors.primaryAction : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(WizardDesign.Colors.primaryAction, lineWidth: 1.5)
                    )
                    .opacity(isLoading ? 0.85 : 1.0)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                    .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                    .disabled(isLoading)
            }
        }

        /// Destructive button style (for dangerous actions)
        public struct DestructiveButton: ButtonStyle {
            public let isLoading: Bool

            public init(isLoading: Bool = false) {
                self.isLoading = isLoading
            }

            public func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(WizardDesign.Typography.button)
                    .foregroundColor(.white)
                    .frame(minWidth: 120, minHeight: 26) // Fixed minimum dimensions (20% height reduction)
                    .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                    .padding(.vertical, WizardDesign.Spacing.elementGap)
                    .background(WizardDesign.Colors.error)
                    .clipShape(.rect(cornerRadius: 8))
                    .opacity(isLoading ? 0.85 : 1.0)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                    .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                    .disabled(isLoading)
            }
        }

        // MARK: - Hero Layout Components

        /// Ultra-compact content card for additional information
        public struct CompactContentCard: View {
            public let content: String
            public let alignment: TextAlignment

            public init(content: String, alignment: TextAlignment = .leading) {
                self.content = content
                self.alignment = alignment
            }

            public var body: some View {
                VStack(
                    alignment: alignment == .center ? .center : .leading,
                    spacing: WizardDesign.Spacing.itemGap
                ) {
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
        public struct HeroSection: View {
            public let icon: String
            public let title: String
            public let subtitle: String
            public let status: HeroStatus
            public let actionLinks: [ActionLink]?

            public enum HeroStatus {
                case success(Color = WizardDesign.Colors.success)
                case warning(Color = WizardDesign.Colors.warning)
                case error(Color = WizardDesign.Colors.error)
                case info(Color = WizardDesign.Colors.info)

                public var color: Color {
                    switch self {
                    case let .success(color): color
                    case let .warning(color): color
                    case let .error(color): color
                    case let .info(color): color
                    }
                }

                public var overlayIcon: String {
                    switch self {
                    case .success: "checkmark.circle.fill"
                    case .warning: "exclamationmark.triangle.fill"
                    case .error: "xmark.circle.fill"
                    case .info: "info.circle.fill"
                    }
                }
            }

            public struct ActionLink {
                public let title: String
                public let action: () -> Void
            }

            public init(
                icon: String,
                title: String,
                subtitle: String,
                status: HeroStatus,
                actionLinks: [ActionLink]? = nil
            ) {
                self.icon = icon
                self.title = title
                self.subtitle = subtitle
                self.status = status
                self.actionLinks = actionLinks
            }

            public var body: some View {
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
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Standardized subtitle (17pt)
                        Text(subtitle)
                            .font(.headline.weight(.regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Action links below the subheader (if provided)
                        if let actionLinks, !actionLinks.isEmpty {
                            HStack(spacing: WizardDesign.Spacing.itemGap) {
                                ForEach(actionLinks.indices, id: \.self) { index in
                                    let link = actionLinks[index]
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

                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        /// Standardized icon with overlay for consistent positioning across wizard pages
        public struct IconWithOverlay: View {
            public let mainIcon: String
            public let overlayIcon: String
            public let mainColor: Color
            public let overlayColor: Color
            public let size: IconSize
            public let transparentOverlay: Bool

            public enum IconSize {
                case hero, compact

                public var mainSize: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroIconSize
                    case .compact: WizardDesign.Layout.compactIconSize
                    }
                }

                public var overlaySize: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroOverlaySize
                    case .compact: WizardDesign.Layout.compactOverlaySize
                    }
                }

                public var frameWidth: CGFloat {
                    switch self {
                    case .hero: WizardDesign.Layout.heroIconFrameWidth
                    case .compact: WizardDesign.Layout.compactIconFrameWidth
                    }
                }

                public var offset: (x: CGFloat, y: CGFloat) {
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

            public var body: some View {
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

    // MARK: - Utilities

    /// Disable focus visuals on macOS 14+ to avoid blue focus ring artifacts
    public struct DisableFocusEffects: ViewModifier {
        public func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.focusEffectDisabled(true)
            } else {
                content
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply wizard card styling
    public func wizardCard() -> some View {
        modifier(WizardDesign.Component.Card())
    }

    /// Apply status indicator styling
    public func wizardStatusIndicator(_ status: InstallationStatus) -> some View {
        modifier(WizardDesign.Component.StatusIndicator(status: status))
    }

    /// Apply standard wizard page padding
    public func wizardPagePadding() -> some View {
        padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.vertical, WizardDesign.Spacing.sectionGap)
    }

    /// Apply standard wizard content spacing
    public func wizardContentSpacing() -> some View {
        frame(maxWidth: WizardDesign.Layout.maxContentWidth)
    }

    /// Apply toast card styling
    public func wizardToastCard() -> some View {
        modifier(WizardDesign.Component.ToastCard())
    }
}

// MARK: - Success Celebration Animation

/// Animated checkmark burst for celebrating successful operations
public struct CheckmarkBurstView: View {
    @Binding public var isShowing: Bool

    public init(isShowing: Binding<Bool>) {
        _isShowing = isShowing
    }

    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 1
    @State private var particleScale: CGFloat = 0.3
    @State private var particleOpacity: Double = 1
    @State private var particleRotation: Double = 0

    private let particleCount = 8

    public var body: some View {
        ZStack {
            // Expanding ring
            Circle()
                .stroke(Color.green.opacity(0.4), lineWidth: 3)
                .frame(width: 80, height: 80)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Radiating particles
            ForEach(0 ..< particleCount, id: \.self) { index in
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .offset(y: -50 * particleScale)
                    .rotationEffect(.degrees(Double(index) * (360.0 / Double(particleCount)) + particleRotation))
                    .opacity(particleOpacity)
            }

            // Central checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .medium))
                .foregroundColor(.green)
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
        }
        .onChange(of: isShowing) { _, newValue in
            if newValue {
                animateBurst()
            }
        }
        .onAppear {
            if isShowing {
                animateBurst()
            }
        }
    }

    private func animateBurst() {
        // Reset states
        checkmarkScale = 0
        checkmarkOpacity = 0
        ringScale = 0.5
        ringOpacity = 1
        particleScale = 0.3
        particleOpacity = 1
        particleRotation = 0

        // Checkmark bounces in
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }

        // Ring expands outward
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 2.5
            ringOpacity = 0
        }

        // Particles burst outward with rotation
        withAnimation(.easeOut(duration: 0.5)) {
            particleScale = 2.0
            particleRotation = 30
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            particleOpacity = 0
        }

        // Fade out checkmark after delay
        withAnimation(.easeOut(duration: 0.3).delay(1.2)) {
            checkmarkOpacity = 0
            checkmarkScale = 0.8
        }

        // Reset showing state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isShowing = false
        }
    }
}

/// Mini checkmark burst for inline success feedback
public struct MiniCheckmarkBurst: View {
    @Binding var isShowing: Bool

    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 1

    public var body: some View {
        ZStack {
            // Small expanding ring
            Circle()
                .stroke(Color.green.opacity(0.5), lineWidth: 2)
                .frame(width: 24, height: 24)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onChange(of: isShowing) { _, newValue in
            if newValue {
                animate()
            }
        }
    }

    private func animate() {
        scale = 0
        opacity = 0
        ringScale = 0.5
        ringOpacity = 1

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }

        withAnimation(.easeOut(duration: 0.4)) {
            ringScale = 2.0
            ringOpacity = 0
        }
    }
}

// MARK: - Availability-safe symbol effect helper

public struct AvailabilitySymbolBounce: ViewModifier {
    public let repeating: Bool

    public init(repeating: Bool = false) {
        self.repeating = repeating
    }

    public func body(content: Content) -> some View {
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
public struct WizardButton: View {
    public let title: String
    public let style: ButtonStyle
    public let isLoading: Bool
    public let isDefaultAction: Bool
    public let action: () async -> Void

    public enum ButtonStyle {
        case primary, secondary, destructive
    }

    public init(
        _ title: String, style: ButtonStyle = .primary, isLoading: Bool = false,
        isDefaultAction: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.isDefaultAction = isDefaultAction
        self.action = action
    }

    public var body: some View {
        switch style {
        case .primary:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isLoading))
            .accessibilityIdentifier("wizard-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(isLoading ? "Operation in progress" : "Tap to \(title.lowercased())")
            .if(isDefaultAction) { $0.keyboardShortcut(.defaultAction) }
        case .secondary:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton(isLoading: isLoading))
            .accessibilityIdentifier("wizard-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(isLoading ? "Operation in progress" : "Tap to \(title.lowercased())")
        case .destructive:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: isLoading))
            .accessibilityIdentifier("wizard-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            .accessibilityLabel(isLoading ? "Loading, \(title)" : title)
            .accessibilityHint(
                isLoading
                    ? "Operation in progress"
                    : "Tap to \(title.lowercased()). This action may cause data loss."
            )
        }
    }
}

/// Reusable wizard status item component with animated status transitions
public struct WizardStatusItem: View {
    public let icon: String
    public let title: String
    public let subtitle: String?
    public let status: InstallationStatus
    public let isNavigable: Bool
    public let action: (() -> Void)?
    public let isFinalStatus: Bool
    public let showInitialClock: Bool
    public let tooltip: String?

    init(
        icon: String, title: String, subtitle: String? = nil, status: InstallationStatus,
        isNavigable: Bool = false,
        action: (() -> Void)? = nil,
        isFinalStatus: Bool = false,
        showInitialClock: Bool = false,
        tooltip: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.action = action
        self.isFinalStatus = isFinalStatus
        self.showInitialClock = showInitialClock
        self.tooltip = tooltip
    }

    public var body: some View {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
            AnimatedStatusIcon(
                status: status,
                isFinalStatus: isFinalStatus,
                showInitialClock: showInitialClock
            )

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

            // Navigation indicator
            if isNavigable {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, WizardDesign.Spacing.labelGap)
        .contentShape(Rectangle())
        .modifier(TapGestureModifier(isNavigable: isNavigable, action: action))
        .help(tooltip ?? "") // Show tooltip on hover if provided
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wizard-status-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel("\(title): \(statusText)")
        .accessibilityHint(isNavigable ? "Tap to navigate to \(title) page" : "")
    }

    private var statusText: String {
        switch status {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .warning: "Warning"
        case .completed: "Completed"
        case .failed: "Failed"
        case .unverified: "Unable to verify"
        }
    }
}

/// Animated status icon that shows clock -> colored final state transitions
public struct AnimatedStatusIcon: View {
    public let status: InstallationStatus
    public let isFinalStatus: Bool
    public let showInitialClock: Bool

    @State private var hasAnimated = false

    init(status: InstallationStatus, isFinalStatus: Bool = false, showInitialClock: Bool = false) {
        self.status = status
        self.isFinalStatus = isFinalStatus
        self.showInitialClock = showInitialClock
    }

    public var body: some View {
        Group {
            if showInitialClock, status == .completed || status == .failed {
                // Clock-to-final-state animation for completed/failed items
                if hasAnimated {
                    // Final state with adaptive circle background for contrast
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor)) // Adapts to dark mode
                            .frame(width: 16, height: 16)
                        Image(systemName: finalStateIcon)
                            .foregroundColor(finalStateColor)
                            .font(.headline)
                    }
                    .modifier(AvailabilitySymbolBounce())
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                            removal: .opacity
                        )
                    )
                } else {
                    // Initial clock state
                    Image(systemName: "clock.fill")
                        .foregroundColor(WizardDesign.Colors.inProgress)
                        .font(.headline)
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
                        .font(.headline)

                case .inProgress:
                    // Animated clock
                    Image(systemName: "clock.fill")
                        .foregroundColor(WizardDesign.Colors.inProgress)
                        .font(.headline)

                case .warning:
                    // Orange warning triangle with adaptive circle background
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor)) // Adapts to dark mode
                            .frame(width: 16, height: 16)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(WizardDesign.Colors.warning)
                            .font(.headline)
                    }
                    .modifier(AvailabilitySymbolBounce())

                case .completed:
                    // Green checkmark with adaptive circle background
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor)) // Adapts to dark mode
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(WizardDesign.Colors.success)
                            .font(.headline)
                    }
                    .modifier(AvailabilitySymbolBounce())

                case .failed:
                    // Red X with adaptive circle background
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor)) // Adapts to dark mode
                            .frame(width: 16, height: 16)
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(WizardDesign.Colors.error)
                            .font(.headline)
                    }
                    .modifier(AvailabilitySymbolBounce())

                case .unverified:
                    // Gray question mark - cannot verify without FDA
                    ZStack {
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 16, height: 16)
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .font(.headline)
                    }
                }
            }
        }
    }

    private var finalStateIcon: String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unverified: "questionmark.circle"
        default: "circle"
        }
    }

    private var finalStateColor: Color {
        switch status {
        case .completed: WizardDesign.Colors.success
        case .failed: WizardDesign.Colors.error
        case .unverified: WizardDesign.Colors.secondaryText
        default: WizardDesign.Colors.secondaryText
        }
    }
}

/// Wizard page header component
public struct WizardPageHeader: View {
    public let icon: String
    public let title: String
    public let subtitle: String
    public let status: HeaderStatus

    public enum HeaderStatus {
        case success, warning, error, info

        public var color: Color {
            switch self {
            case .success: WizardDesign.Colors.success
            case .warning: WizardDesign.Colors.warning
            case .error: WizardDesign.Colors.error
            case .info: WizardDesign.Colors.info
            }
        }
    }

    public var body: some View {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
            // Icon - green checkmark circle fills the space
            Image(systemName: icon)
                .font(.system(size: WizardDesign.Layout.statusCircleSize))
                .foregroundColor(status.color)

            // Title
            Text(title)
                .font(WizardDesign.Typography.sectionTitle)
                .fontWeight(.semibold)

            // Subtitle
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(WizardDesign.Typography.subtitle)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .wizardContentSpacing()
            }
        }
        .padding(.top, 36) // Increased top padding after removing window header
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wizard-hero-section")
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tap Gesture Modifier

private struct TapGestureModifier: ViewModifier {
    public let isNavigable: Bool
    public let action: (() -> Void)?

    func body(content: Content) -> some View {
        if isNavigable, let action {
            content.onTapGesture {
                action()
            }
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    /// Wraps content in a standardized hero section container with Spacer() and padding
    public func heroSectionContainer() -> some View {
        modifier(WizardDesign.HeroSectionContainer())
    }

    /// Conditionally apply a modifier
    @ViewBuilder
    public func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
