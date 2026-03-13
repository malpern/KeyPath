import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Simplified summary page using extracted components
public struct WizardSummaryPage: View {
    public let systemState: WizardSystemState
    public let issues: [WizardIssue]
    public let stateInterpreter: WizardStateInterpreter
    public let onStartService: () -> Void
    public let onDismiss: () -> Void
    public let onNavigateToPage: ((WizardPage) -> Void)?
    public let isValidating: Bool // Show validating activity state during summary refresh
    @Binding public var showAllItems: Bool // Lifted to parent to drive navigation sequence
    @Binding public var navSequence: [WizardPage] // Ordered pages for back/next navigation

    // MARK: - Header State

    private enum HeaderMode {
        case validating // Blue indeterminate bar
        case issues // Error icon
        case success // Green check
    }

    @State private var headerMode: HeaderMode = .validating
    @State private var iconHovering: Bool = false
    @State private var fadeMaskOpacity: Double = 0.0
    @State private var visibleIssueCount: Int = 0
    /// Set after validation completes to trigger single-issue auto-navigation
    @State private var shouldAutoNavigateSingleIssue = false

    public init(
        systemState: WizardSystemState,
        issues: [WizardIssue],
        stateInterpreter: WizardStateInterpreter,
        onStartService: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onNavigateToPage: ((WizardPage) -> Void)?,
        isValidating: Bool,
        showAllItems: Binding<Bool>,
        navSequence: Binding<[WizardPage]>
    ) {
        self.systemState = systemState
        self.issues = issues
        self.stateInterpreter = stateInterpreter
        self.onStartService = onStartService
        self.onDismiss = onDismiss
        self.onNavigateToPage = onNavigateToPage
        self.isValidating = isValidating
        _showAllItems = showAllItems
        _navSequence = navSequence
    }

    public var body: some View {
        Group {
            if headerMode == .success {
                successCenteredView
            } else {
                issuesAndValidatingContent
            }
        }
        .modifier(WizardDesign.DisableFocusEffects())
        .background(WizardDesign.Colors.wizardBackground)
        .accessibilityIdentifier("wizard-page-summary")
        .overlay {
            WizardDesign.Colors.wizardBackground
                .opacity(fadeMaskOpacity)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: fadeMaskOpacity)
        }
        .onAppear {
            if isValidating {
                headerMode = .validating
            } else {
                headerMode = isEverythingComplete ? .success : .issues
            }
            Task { @MainActor in
                NSApp.keyWindow?.makeFirstResponder(nil)
                if let window = NSApp.keyWindow {
                    window.contentView?.subviews.forEach { view in
                        view.focusRingType = .none
                    }
                }
            }
        }
        .onChange(of: isValidating) { _, newValue in
            if !newValue {
                Task { @MainActor in
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    headerMode = isEverythingComplete ? .success : .issues
                }
                // Auto-navigate when there's exactly 1 issue (skip single-item list)
                if !isEverythingComplete, !showAllItems {
                    if navSequence.count == 1, let page = navSequence.first {
                        // navSequence already populated — navigate immediately
                        onNavigateToPage?(page)
                    } else {
                        // Wait for WizardSystemStatusOverview to compute navSequence
                        shouldAutoNavigateSingleIssue = true
                    }
                }
            }
        }
        // Two-phase auto-nav: WizardSystemStatusOverview computes navSequence
        // asynchronously in onAppear, so it may not be ready when isValidating
        // changes. We set the flag above, then wait for the sequence to arrive.
        .onChange(of: navSequence) { _, newSeq in
            guard shouldAutoNavigateSingleIssue else { return }
            // Only clear the flag when we actually navigate — an intermediate
            // empty sequence (e.g. clearing before repopulating) must not
            // consume the flag.
            guard !showAllItems, newSeq.count == 1, let page = newSeq.first else { return }
            shouldAutoNavigateSingleIssue = false
            onNavigateToPage?(page)
        }
        .onChange(of: isEverythingComplete) { _, newValue in
            if !isValidating {
                withAnimation(WizardDesign.Animation.statusTransition) {
                    headerMode = newValue ? .success : .issues
                }
            }
        }
    }

    // MARK: - Success Centered View

    private var successCenteredView: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: WizardDesign.Layout.heroIconSize, weight: .light))
                .foregroundColor(WizardDesign.Colors.success)
                .symbolRenderingMode(.hierarchical)
                .modifier(AvailabilitySymbolBounce())

            Text("KeyPath Ready")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)

            Button("Close Setup") {
                onDismiss()
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())
            .keyboardShortcut(.defaultAction)
            .padding(.top, WizardDesign.Spacing.elementGap)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityIdentifier("wizard-summary-status-success")
        .accessibilityLabel("KeyPath Ready")
    }

    // MARK: - Issues and Validating Content

    private var issuesAndValidatingContent: some View {
        ZStack(alignment: .top) {
            // Content area (issues list and actions) - positioned below fixed header
            VStack(spacing: 0) {
                // Spacer to push content below the fixed header area
                Spacer()
                    .frame(height: 180) // Space for header (60pt top + 120pt header)

                // System Status Overview
                // Cap list region height so window grows until cap, then scrolls internally
                if !isValidating {
                    // Cross-fade entire list to avoid row-wise jitter on filter toggle
                    Group {
                        WizardSystemStatusOverview(
                            systemState: systemState,
                            issues: issues,
                            stateInterpreter: stateInterpreter,
                            onNavigateToPage: onNavigateToPage,
                            kanataIsRunning: systemState == .active,
                            showAllItems: showAllItems,
                            navSequence: $navSequence,
                            visibleIssueCount: $visibleIssueCount
                        )
                    }
                    .id(showAllItems ? "list_all" : "list_errors")
                    .frame(maxHeight: listMaxHeight)
                    .transition(.opacity)
                } else {
                    // During validation, don't reserve list space; allow compact height
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
                    // No action section during validation; keep window minimal
                }
            }

            // Icon - absolutely positioned, independent of text
            ZStack {
                // Hover ring exactly centered with the icon
                if headerMode == .issues {
                    Circle()
                        .stroke(Color.primary.opacity(iconHovering ? 0.15 : 0.0), lineWidth: 2)
                        .frame(
                            width: WizardDesign.Layout.statusCircleSize + 8,
                            height: WizardDesign.Layout.statusCircleSize + 8
                        )
                        .allowsHitTesting(false)
                }

                if headerMode == .validating {
                    WizardActivityIndicator(
                        width: min(220, WizardDesign.Layout.statusCircleSize + 36),
                        height: 6
                    )
                    .transition(.opacity)
                } else {
                    // Final state icon (error or success) - simple fade transition
                    Image(systemName: headerIconName)
                        .font(.system(size: WizardDesign.Layout.statusCircleSize))
                        .foregroundColor(headerIconColor)
                        .modifier(AvailabilitySymbolBounce())
                }
            }
            .frame(
                width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize
            )
            .frame(maxWidth: .infinity) // Center horizontally
            .padding(.top, iconTopPadding) // Icon pinned from top (issues icon closer by 30%)
            .offset(y: iconVerticalTweak) // Optical alignment tweak shared with hover ring
            .zIndex(1)
            .animation(nil, value: showAllItems) // Keep header stable during list toggles
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
                    // Brief white cross-fade to mask internal list relayout
                    fadeMaskOpacity = 1.0
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllItems.toggle()
                        fadeMaskOpacity = 0.0
                    }
                }
            }
            .transition(.opacity) // Simple opacity transition, no scaling
            .accessibilityIdentifier("wizard-summary-status-\(headerMode == .validating ? "validating" : (headerMode == .success ? "success" : "issues"))")
            .accessibilityLabel(headerTitle)

            // Title text - positioned below icon, independent
            Text(headerTitle)
                .font(WizardDesign.Typography.sectionTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity) // Center horizontally
                .padding(.top, 60 + WizardDesign.Layout.statusCircleSize + WizardDesign.Spacing.elementGap)
                .fixedSize(horizontal: false, vertical: true)
                .zIndex(1)
                .animation(nil, value: showAllItems) // Prevent headline motion on toggle
            // Eye icon removed - error icon toggles list filtering
        }
    }

    // MARK: - Helper Properties

    private var isEverythingComplete: Bool {
        // CRITICAL: Trust the issues system - don't do additional file checks
        // The SystemValidator/IssueGenerator is the single source of truth
        // Any additional validation should be added there, not here

        // Check if system is active and running
        guard systemState == .active else {
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
            let n = WizardSummaryPage.computeIssueCount(
                visibleCount: visibleIssueCount,
                failedCount: failedIssueCount
            )
            if n == 0 {
                return "Finish setup to start KeyPath"
            }
            let suffix = n == 1 ? "issue" : "issues"
            return "\(n) setup \(suffix) to resolve"
        case .success:
            return "KeyPath Ready"
        }
    }

    private var headerIconName: String {
        switch headerMode {
        case .validating:
            "minus" // Not used, but required for exhaustive switch
        case .issues:
            "xmark.circle.fill"
        case .success:
            "checkmark.circle.fill"
        }
    }

    private var headerIconColor: Color {
        switch headerMode {
        case .validating:
            .secondary // Not used, but required for exhaustive switch
        case .issues:
            WizardDesign.Colors.error
        case .success:
            WizardDesign.Colors.success
        }
    }

    /// Adjust icon top padding: bring the issues icon 30% closer to the top
    private var iconTopPadding: CGFloat {
        switch headerMode {
        case .issues:
            CGFloat(60) * 0.7 // 30% closer to top
        default:
            60
        }
    }

    /// Max height for list region before internal scrolling kicks in
    private var listMaxHeight: CGFloat {
        460
    }

    /// Small optical alignment to normalize SF Symbol vertical metrics
    private var iconVerticalTweak: CGFloat {
        2.0
    }

    // MARK: - Issue Counting (summary indicator)

    private var failedIssueCount: Int {
        var count = 0

        // Check FDA status - without it, we can't verify Kanata permissions
        let hasFDA = WizardDependencies.fullDiskAccessChecker?.hasFullDiskAccess() ?? false

        // 1. Privileged Helper issues (installed? unhealthy?) => count as issue
        let hasHelperProblems = issues.contains { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelper || req == .privilegedHelperUnhealthy
            }
            return false
        }
        if hasHelperProblems { count += 1 }

        // 2. Conflicts (any => red)
        let hasConflicts = issues.contains { $0.category == .conflicts }
        if hasConflicts { count += 1 }

        // 3. Input Monitoring - only count if we can verify (FDA available) or it's KeyPath's own permission
        let hasKeyPathInputMonitoringIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathInputMonitoring
            }
            return false
        }
        let hasKanataInputMonitoringIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .kanataInputMonitoring
            }
            return false
        }
        // Count KeyPath issues always, Kanata issues only if we can verify (have FDA)
        if hasKeyPathInputMonitoringIssues || (hasFDA && hasKanataInputMonitoringIssues) {
            count += 1
        }

        // 4. Accessibility - same logic: only count verifiable issues
        let hasKeyPathAccessibilityIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathAccessibility
            }
            return false
        }
        let hasKanataAccessibilityIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .kanataAccessibility
            }
            return false
        }
        if hasKeyPathAccessibilityIssues || (hasFDA && hasKanataAccessibilityIssues) {
            count += 1
        }

        // 5. Karabiner Driver status (failed => red)
        let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        )
        if karabinerStatus == .failed { count += 1 }

        // 6. Keyboard Engine Setup (failed => red)
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.keyPathRuntime):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKanataIssues { count += 1 }

        // NOTE: Kanata Service (daemon issues) is NOT counted here because it's a
        // dependent item that's hidden when earlier prerequisites fail.
        // The service item only shows after: Karabiner Driver + Helper + Permissions are complete.
        // Counting hidden items would inflate the count and confuse users.

        return count
    }

    // MARK: - Testing helper

    public static func computeIssueCount(visibleCount: Int, failedCount: Int) -> Int {
        // Prefer what the user can see; fall back to aggregate when the filtered list is empty
        visibleCount > 0 ? visibleCount : failedCount
    }
}
