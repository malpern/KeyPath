import KeyPathCore
import KeyPathWizardCore
import AppKit
import SwiftUI

/// Simplified summary page using extracted components
struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let isValidating: Bool // Show spinning gear during validation
    @Binding var showAllItems: Bool // Lifted to parent to drive navigation sequence
    @Binding var navSequence: [WizardPage] // Ordered pages for back/next navigation

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
        kanataViewModel.underlyingManager
    }

    // MARK: - Header State
    private enum HeaderMode {
        case validating // Spinning gear
        case issues // Error icon
        case success // Green check
    }

    @State private var headerMode: HeaderMode = .validating
    @State private var gearRotation: Double = 0 // For continuous spinning animation
    @State private var iconHovering: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Content area (issues list and actions) - positioned below fixed header
            VStack(spacing: 0) {
                // Spacer to push content below the fixed header area
                Spacer()
                    .frame(height: 180) // Space for header (60pt top + 120pt header)

                // System Status Overview
                // Cap list region height so window grows until cap, then scrolls internally
                if !isValidating {
                    WizardSystemStatusOverview(
                        systemState: systemState,
                        issues: issues,
                        stateInterpreter: stateInterpreter,
                        onNavigateToPage: onNavigateToPage,
                        kanataIsRunning: kanataManager.isRunning,
                        showAllItems: showAllItems,
                        navSequence: $navSequence
                    )
                    .frame(maxHeight: listMaxHeight)
                    .transition(.opacity) // Simple fade in, no sliding
                } else {
                    // Reserve space during validation to keep window size stable
                    Spacer()
                        .frame(height: listMaxHeight)
                }

                // Minimal separation before action section
                Spacer(minLength: 0)

                // Action Section
                // Always reserve space to prevent window resizing
                if !isValidating {
                    WizardActionSection(
                        systemState: systemState,
                        isFullyConfigured: isEverythingComplete,
                        onStartService: onStartService,
                        onDismiss: onDismiss
                    )
                    .padding(.bottom, WizardDesign.Spacing.elementGap) // Reduce bottom padding
                    .transition(.opacity)
                } else {
                    // Reserve space during validation to keep window size stable
                    Spacer()
                        .frame(height: 60) // Approximate height for action section
                }
            }

            // Icon - absolutely positioned, independent of text
            Group {
                if headerMode == .validating {
                    // Spinning gear during validation - continuous rotation
                    Image(systemName: "gear")
                        .font(.system(size: WizardDesign.Layout.statusCircleSize))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(gearRotation))
                        .onAppear {
                            // Start continuous rotation when gear appears
                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                gearRotation = 360
                            }
                        }
                        .onDisappear {
                            // Stop rotation when gear disappears
                            gearRotation = 0
                        }
                } else {
                    // Final state icon (error or success) - simple fade transition
                    Image(systemName: headerIconName)
                        .font(.system(size: WizardDesign.Layout.statusCircleSize))
                        .foregroundColor(headerIconColor)
                        .modifier(AvailabilitySymbolBounce())
                }
            }
            .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)
            .frame(maxWidth: .infinity) // Center horizontally
            .padding(.top, iconTopPadding) // Icon pinned from top (issues icon closer by 30%)
            .overlay(alignment: .center) {
                // Subtle hover ring when clickable (issues mode only)
                if headerMode == .issues {
                    Circle()
                        .stroke(Color.primary.opacity(iconHovering ? 0.15 : 0.0), lineWidth: 2)
                        .frame(width: WizardDesign.Layout.statusCircleSize + 8, height: WizardDesign.Layout.statusCircleSize + 8)
                        .animation(.easeInOut(duration: 0.15), value: iconHovering)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
            .onHover { hovering in
                if headerMode == .issues {
                    iconHovering = hovering
                } else {
                    iconHovering = false
                }
            }
            .onTapGesture {
                // Toggle showAll when in issues mode; animate list transition
                if headerMode == .issues {
                    withAnimation(WizardDesign.Animation.statusTransition) {
                        showAllItems.toggle()
                    }
                }
            }
            .transition(.opacity) // Simple opacity transition, no scaling
            .onAppear {
                // Initialize header mode based on validation state
                if isValidating {
                    headerMode = .validating
                } else {
                    headerMode = isEverythingComplete ? .success : .issues
                }
                // Aggressively clear focus to avoid blue focus ring artifacts
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    // Also disable focus rings on the window itself
                    if let window = NSApp.keyWindow {
                        window.contentView?.subviews.forEach { view in
                            view.focusRingType = .none
                        }
                    }
                }
            }
            .onChange(of: isValidating) { _, newValue in
                if !newValue {
                    // Transition from gear to final state - clear focus during transition
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        headerMode = isEverythingComplete ? .success : .issues
                    }
                }
            }
            .onChange(of: isEverythingComplete) { _, newValue in
                // Update header mode if validation is complete
                if !isValidating {
                    withAnimation(WizardDesign.Animation.statusTransition) {
                        headerMode = newValue ? .success : .issues
                    }
                }
            }

            // Title text - positioned below icon, independent
            Text(headerTitle)
                .font(WizardDesign.Typography.sectionTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity) // Center horizontally
                .padding(.top, 60 + WizardDesign.Layout.statusCircleSize + WizardDesign.Spacing.elementGap)
            // Eye icon removed - error icon toggles list filtering
        }
        .modifier(WizardDesign.DisableFocusEffects())
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Properties

    private var isEverythingComplete: Bool {
        // CRITICAL: Trust the issues system - don't do additional file checks
        // The SystemValidator/IssueGenerator is the single source of truth
        // Any additional validation should be added there, not here

        // Check if system is active and running
        guard systemState == .active, kanataManager.isRunning else {
            return false
        }

        // Check that there are no issues
        // If there are configuration problems, they will appear in the issues list
        return issues.isEmpty
    }

    private var headerTitle: String {
        switch headerMode {
        case .validating:
            return "Setting up KeyPath"
        case .issues:
            let n = failedIssueCount
            let suffix = n == 1 ? "issue" : "issues"
            return "\(n) setup \(suffix) to resolve"
        case .success:
            return "KeyPath Ready"
        }
    }

    private var headerIconName: String {
        switch headerMode {
        case .validating:
            return "gear" // Not used, but required for exhaustive switch
        case .issues:
            return "xmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private var headerIconColor: Color {
        switch headerMode {
        case .validating:
            return .secondary // Not used, but required for exhaustive switch
        case .issues:
            return WizardDesign.Colors.error
        case .success:
            return WizardDesign.Colors.success
        }
    }

    // Adjust icon top padding: bring the issues icon 30% closer to the top
    private var iconTopPadding: CGFloat {
        switch headerMode {
        case .issues:
            return CGFloat(60) * 0.7 // 30% closer to top
        default:
            return 60
        }
    }

    // Max height for list region before internal scrolling kicks in
    private var listMaxHeight: CGFloat {
        460
    }

    // MARK: - Issue Counting (summary indicator)

    private var failedIssueCount: Int {
        var count = 0

        // 1. Privileged Helper not installed (red)
        let hasHelperNotInstalled = issues.contains { issue in
            if case let .component(req) = issue.identifier { return req == .privilegedHelper }
            return false
        }
        if hasHelperNotInstalled { count += 1 }

        // 2. Conflicts (any => red)
        let hasConflicts = issues.contains { $0.category == .conflicts }
        if hasConflicts { count += 1 }

        // 3. Input Monitoring (any missing => red)
        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathInputMonitoring || p == .kanataInputMonitoring
            }
            return false
        }
        if hasInputMonitoringIssues { count += 1 }

        // 4. Accessibility (any missing => red)
        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathAccessibility || p == .kanataAccessibility
            }
            return false
        }
        if hasAccessibilityIssues { count += 1 }

        // 5. Karabiner Driver status (failed => red)
        let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        )
        if karabinerStatus == .failed { count += 1 }

        // 6. Kanata Engine Setup (failed => red)
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService),
                     .component(.orphanedKanataProcess):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKanataIssues { count += 1 }

        return max(count, 1) // never show 0 in error mode
    }
}
