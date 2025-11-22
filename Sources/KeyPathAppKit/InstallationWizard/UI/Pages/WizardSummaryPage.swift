import AppKit
import KeyPathCore
import KeyPathWizardCore
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
  let isValidating: Bool  // Show spinning gear during validation
  @Binding var showAllItems: Bool  // Lifted to parent to drive navigation sequence
  @Binding var navSequence: [WizardPage]  // Ordered pages for back/next navigation

  // Access underlying KanataManager for business logic
  private var kanataManager: KanataManager {
    kanataViewModel.underlyingManager
  }

  // MARK: - Header State

  private enum HeaderMode {
    case validating  // Spinning gear
    case issues  // Error icon
    case success  // Green check
  }

  @State private var headerMode: HeaderMode = .validating
  @State private var gearRotation: Double = 0  // For continuous spinning animation
  @State private var iconHovering: Bool = false
  @State private var fadeMaskOpacity: Double = 0.0
  @State private var visibleIssueCount: Int = 0

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        ZStack(alignment: .top) {
          // Content stack
          VStack(spacing: 16) {
            // Spacer to push content below the fixed header area
            Spacer(minLength: 0)
              .frame(height: 180)

            // System Status Overview
            if !isValidating {
              Group {
                WizardSystemStatusOverview(
                  systemState: systemState,
                  issues: issues,
                  stateInterpreter: stateInterpreter,
                  onNavigateToPage: onNavigateToPage,
                  kanataIsRunning: kanataManager.isRunning,
                  showAllItems: showAllItems,
                  navSequence: $navSequence,
                  visibleIssueCount: $visibleIssueCount
                )
              }
              .id(showAllItems ? "list_all" : "list_errors")
              .frame(maxWidth: 720)
              .transition(.opacity)
            }

            // Action Section inline (keeps layout predictable; scrolls if needed)
            if !isValidating {
              WizardActionSection(
                systemState: systemState,
                isFullyConfigured: isEverythingComplete,
                onStartService: onStartService,
                onDismiss: onDismiss
              )
              .frame(maxWidth: 720)
              .padding(.top, 8)
              .transition(.opacity)
            }

            Spacer(minLength: 12)
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 24)
          .padding(.bottom, 24 + proxy.safeAreaInsets.bottom)

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
      .frame(
        width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize
      )
      .frame(maxWidth: .infinity)  // Center horizontally
      .padding(.top, iconTopPadding)  // Icon pinned from top (issues icon closer by 30%)
      .offset(y: iconVerticalTweak)  // Optical alignment tweak shared with hover ring
      .zIndex(1)
      .animation(nil, value: showAllItems)  // Keep header stable during list toggles
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
      .transition(.opacity)  // Simple opacity transition, no scaling
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
          // White cross-fade when revealing list for the first time
          fadeMaskOpacity = 1.0
          withAnimation(.easeInOut(duration: 0.22)) {
            fadeMaskOpacity = 0.0
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
        .frame(maxWidth: .infinity)  // Center horizontally
        .padding(.top, 60 + WizardDesign.Layout.statusCircleSize + WizardDesign.Spacing.elementGap)
        .fixedSize(horizontal: false, vertical: true)
        .zIndex(1)
        .animation(nil, value: showAllItems)  // Prevent headline motion on toggle
        // Eye icon removed - error icon toggles list filtering
        }
        .frame(
          maxWidth: .infinity,
          minHeight: max(proxy.size.height, 520),
          alignment: .top
        )
        .background(WizardDesign.Colors.wizardBackground)
        // Full-surface white fade to simplify transitions
        .overlay {
          Color.white
            .opacity(fadeMaskOpacity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: fadeMaskOpacity)
        }
      }
      .background(WizardDesign.Colors.wizardBackground.ignoresSafeArea())
    }
    .modifier(WizardDesign.DisableFocusEffects())
    .frame(
      minWidth: 640,
      idealWidth: 800,
      maxWidth: 900,
      minHeight: 520,
      idealHeight: 640,
      maxHeight: 820
    )
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
      "gear"  // Not used, but required for exhaustive switch
    case .issues:
      "xmark.circle.fill"
    case .success:
      "checkmark.circle.fill"
    }
  }

  private var headerIconColor: Color {
    switch headerMode {
    case .validating:
      .secondary  // Not used, but required for exhaustive switch
    case .issues:
      WizardDesign.Colors.error
    case .success:
      WizardDesign.Colors.success
    }
  }

  // Adjust icon top padding: bring the issues icon 30% closer to the top
  private var iconTopPadding: CGFloat {
    switch headerMode {
    case .issues:
      CGFloat(60) * 0.7  // 30% closer to top
    default:
      60
    }
  }

  // Max height for list region before internal scrolling kicks in
  private var listMaxHeight: CGFloat {
    460
  }

  // Small optical alignment to normalize SF Symbol vertical metrics
  private var iconVerticalTweak: CGFloat { 2.0 }

  // MARK: - Issue Counting (summary indicator)

  private var failedIssueCount: Int {
    var count = 0

    // 1. Privileged Helper issues (installed? unhealthy?) => count as issue
    let hasHelperProblems = issues.contains { issue in
      if case .component(let req) = issue.identifier {
        return req == .privilegedHelper || req == .privilegedHelperUnhealthy
      }
      return false
    }
    if hasHelperProblems { count += 1 }

    // 2. Conflicts (any => red)
    let hasConflicts = issues.contains { $0.category == .conflicts }
    if hasConflicts { count += 1 }

    // 3. Input Monitoring (any missing => red)
    let hasInputMonitoringIssues = issues.contains { issue in
      if case .permission(let p) = issue.identifier {
        return p == .keyPathInputMonitoring || p == .kanataInputMonitoring
      }
      return false
    }
    if hasInputMonitoringIssues { count += 1 }

    // 4. Accessibility (any missing => red)
    let hasAccessibilityIssues = issues.contains { issue in
      if case .permission(let p) = issue.identifier {
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

    // NOTE: Kanata Service (daemon issues) is NOT counted here because it's a
    // dependent item that's hidden when earlier prerequisites fail.
    // The service item only shows after: Karabiner Driver + Helper + Permissions are complete.
    // Counting hidden items would inflate the count and confuse users.

        return count
    }

    // MARK: - Testing helper
    static func computeIssueCount(visibleCount: Int, failedCount: Int) -> Int {
        // Prefer what the user can see; fall back to aggregate when the filtered list is empty
        visibleCount > 0 ? visibleCount : failedCount
    }
}
