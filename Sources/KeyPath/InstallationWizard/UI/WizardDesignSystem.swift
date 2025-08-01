import SwiftUI

/// Comprehensive design system for the Installation Wizard
/// Provides consistent spacing, colors, typography, and component styling
enum WizardDesign {
    
    // MARK: - Spacing & Layout
    
    enum Spacing {
        /// Large vertical spacing for page sections
        static let pageVertical: CGFloat = 32
        
        /// Medium spacing between major sections  
        static let sectionGap: CGFloat = 24
        
        /// Standard spacing between related items
        static let itemGap: CGFloat = 16
        
        /// Small spacing for tightly grouped elements
        static let elementGap: CGFloat = 12
        
        /// Minimal spacing for labels and values
        static let labelGap: CGFloat = 8
        
        /// Card internal padding
        static let cardPadding: CGFloat = 20
        
        /// Button internal padding
        static let buttonPadding: CGFloat = 16
        
        /// Icon spacing from text
        static let iconGap: CGFloat = 12
        
        /// Indentation for sub-items
        static let indentation: CGFloat = 16
    }
    
    enum Layout {
        /// Standard wizard page width
        static let pageWidth: CGFloat = 700
        
        /// Standard wizard page height  
        static let pageHeight: CGFloat = 700
        
        /// Maximum content width for readability
        static let maxContentWidth: CGFloat = 400
        
        /// Standard card width
        static let cardWidth: CGFloat = 400
        
        /// Large button width
        static let buttonWidthLarge: CGFloat = 300
        
        /// Medium button width
        static let buttonWidthMedium: CGFloat = 200
        
        /// Icon size for wizard elements
        static let iconSize: CGFloat = 48
        
        /// Small icon size for status indicators
        static let iconSizeSmall: CGFloat = 16
        
        /// Status circle size
        static let statusCircleSize: CGFloat = 80
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
                case .notStarted: return WizardDesign.Colors.secondaryText
                case .inProgress: return WizardDesign.Colors.inProgress
                case .completed: return WizardDesign.Colors.success
                case .failed: return WizardDesign.Colors.error
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
                HStack(spacing: WizardDesign.Spacing.iconGap) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    configuration.label
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(.white)
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
                HStack(spacing: WizardDesign.Spacing.iconGap) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    configuration.label
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(WizardDesign.Colors.primaryAction)
                .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                .padding(.vertical, WizardDesign.Spacing.elementGap)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WizardDesign.Colors.primaryAction, lineWidth: 1)
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
                HStack(spacing: WizardDesign.Spacing.iconGap) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    configuration.label
                }
                .font(WizardDesign.Typography.button)
                .foregroundColor(.white)
                .padding(.horizontal, WizardDesign.Spacing.buttonPadding)
                .padding(.vertical, WizardDesign.Spacing.elementGap)
                .background(WizardDesign.Colors.error)
                .cornerRadius(8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(WizardDesign.Animation.buttonFeedback, value: configuration.isPressed)
                .disabled(isLoading)
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
        self.frame(maxWidth: WizardDesign.Layout.maxContentWidth)
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
    
    init(_ title: String, style: ButtonStyle = .primary, isLoading: Bool = false, action: @escaping () async -> Void) {
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
        case .secondary:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton(isLoading: isLoading))
        case .destructive:
            Button(title) {
                Task {
                    await action()
                }
            }
            .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: isLoading))
        }
    }
}

/// Reusable wizard status item component
struct WizardStatusItem: View {
    let icon: String
    let title: String
    let status: InstallationStatus
    let isNavigable: Bool
    let action: (() -> Void)?
    
    init(icon: String, title: String, status: InstallationStatus, isNavigable: Bool = false, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.status = status
        self.isNavigable = isNavigable
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.system(size: WizardDesign.Layout.iconSizeSmall))
                .frame(width: 20)
            
            // Main icon
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.system(size: 16))
                .frame(width: 20)
            
            // Title
            Text(title)
                .font(WizardDesign.Typography.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status text
            Text(statusText)
                .wizardStatusIndicator(status)
            
            // Navigation indicator
            if isNavigable {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, WizardDesign.Spacing.labelGap)
        .contentShape(Rectangle())
        .onTapGesture {
            if isNavigable {
                action?()
            }
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .notStarted: return "circle"
        case .inProgress: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .notStarted: return WizardDesign.Colors.secondaryText
        case .inProgress: return WizardDesign.Colors.inProgress
        case .completed: return WizardDesign.Colors.success
        case .failed: return WizardDesign.Colors.error
        }
    }
    
    private var statusText: String {
        switch status {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
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
            case .success: return WizardDesign.Colors.success
            case .warning: return WizardDesign.Colors.warning
            case .error: return WizardDesign.Colors.error
            case .info: return WizardDesign.Colors.info
            }
        }
    }
    
    var body: some View {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.1))
                    .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)
                
                Image(systemName: icon)
                    .font(.system(size: WizardDesign.Layout.iconSize))
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
        .padding(.top, WizardDesign.Spacing.pageVertical)
    }
}