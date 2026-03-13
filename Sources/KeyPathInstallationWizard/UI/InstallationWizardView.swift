import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Preference key that tracks the content height of the wizard page,
/// enabling auto-resize on any content change (not just page transitions).
public struct WizardContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Main installation wizard view using clean architecture
public struct InstallationWizardView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.runtimeCoordinator) var kanataManager

    @MainActor
    public func showStatusBanner(_ message: String) {
        statusBannerMessage = message
        statusBannerTimestamp = Date()

        // Auto-dismiss after 6 seconds if not updated
        let marker = statusBannerTimestamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            // Ensure we only clear if timestamp matches (no newer message arrived)
            if marker == statusBannerTimestamp {
                statusBannerMessage = nil
            }
        }
    }

    /// Optional initial page to navigate to
    public var initialPage: WizardPage?

    // New architecture components
    @State public var stateMachine = WizardStateMachine()
    @State public var autoFixer = WizardAutoFixerManager()
    public let stateInterpreter = WizardStateInterpreter()
    @State public var asyncOperationManager = WizardAsyncOperationManager()
    @State public var toastManager = WizardToastManager()

    // UI state
    @State public var isValidating: Bool = true // Track validation state for summary activity indicator
    @State public var preflightStart = Date()
    @State public var evaluationProgress: Double = 0.0
    // stateMachine.wizardState and stateMachine.wizardIssues now live in stateMachine (single source of truth)
    @State public var showAllSummaryItems: Bool = false
    @State public var navSequence: [WizardPage] = []
    @State public var inFlightFixActions: Set<AutoFixAction> = []
    @State public var showingBackgroundApprovalPrompt = false
    @State public var currentFixAction: AutoFixAction?
    @State public var fixInFlight: Bool = false
    @State public var lastRefreshAt: Date?
    @State public var showingCloseConfirmation = false

    // Task management for race condition prevention
    @State public var refreshTask: Task<Void, Never>?
    @State public var isForceClosing = false // Prevent new operations after nuclear close
    @State public var loginItemsPollingTask: Task<Void, Never>? // Polls for Login Items approval
    @State public var statusBannerMessage: String?
    @State public var statusBannerTimestamp: Date?

    /// Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    /// True when the current page is already showing a contextual/in-page progress indicator.
    /// Used to suppress the global operation overlay to avoid duplicate progress treatments.
    @State private var hasInlineProgressIndicator: Bool = false

    public init(initialPage: WizardPage? = nil) {
        self.initialPage = initialPage
    }

    public var currentFixDescriptionForUI: String? {
        guard let currentFixAction else { return nil }
        return describeAutoFixActionForUI(currentFixAction)
    }

    public var body: some View {
        ZStack {
            if let banner = statusBannerMessage {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(banner)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color.gray.opacity(0.15)),
                        alignment: .bottom
                    )
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }

            // Dark mode-aware background for cross-fade effect
            WizardDesign.Colors.wizardBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Always show page content - no preflight view
                pageContent()
                    .id(stateMachine.currentPage) // Force view recreation on page change
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: WizardContentHeightKey.self, value: geo.size.height)
                    })
                    .onPreferenceChange(WizardContentHeightKey.self) { _ in
                        NotificationCenter.default.post(name: .wizardContentSizeChanged, object: nil)
                    }
                    .onPreferenceChange(WizardInlineProgressVisiblePreferenceKey.self) { newValue in
                        hasInlineProgressIndicator = newValue
                    }
                    .overlay {
                        // Don't show overlay during validation - summary page has its own validating indicator
                        // Also suppress overlay when the page already shows an inline progress bar,
                        // to avoid two simultaneous indeterminate bars.
                        if asyncOperationManager.hasRunningOperations, !isValidating, !hasInlineProgressIndicator {
                            operationProgressOverlay()
                                .allowsHitTesting(false) // Don't block X button interaction
                        }
                    }
            }
            .frame(width: WizardDesign.Layout.pageWidth)
            .frame(minHeight: 480, maxHeight: .infinity) // Consistent min height prevents size jumps between pages
            .fixedSize(horizontal: true, vertical: false) // Allow vertical growth; keep width fixed
            .animation(.easeInOut(duration: 0.25), value: isValidating)
            // Prevent vertical position animation during page transitions
            .animation(nil, value: stateMachine.currentPage)
            // Remove animation on frame changes to prevent window movement
            .background(WizardDesign.Colors.wizardBackground) // Simple solid background, no visual effect
        }
        .withToasts(toastManager)
        .environment(stateMachine)
        .focused($hasKeyboardFocus) // Enable focus for reliable ESC key handling
        // Aggressively disable focus rings during validation
        .onChange(of: isValidating) { _, newValue in
            if newValue {
                // Clear focus when validation starts (deferred to next run loop for AppKit interop)
                Task { @MainActor in
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    if let window = NSApp.keyWindow, let contentView = window.contentView {
                        disableFocusRings(in: contentView)
                    }
                }
            } else {
                // Validation finished; set navigation sequence based on current filter
                stateMachine.customSequence = showAllSummaryItems ? nil : navSequence
            }
        }
        // Global navigation + close button overlay for all detail pages
        .overlay(alignment: .top) {
            if stateMachine.currentPage != .summary {
                HStack {
                    WizardNavigationControl()
                    Spacer()
                    CloseButton()
                }
                .environment(stateMachine)
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .animation(nil, value: stateMachine.currentPage)
            }
        }
        .onAppear {
            hasKeyboardFocus = true
            Task { await setupWizard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserFeedback"))) { note in
            if let message = note.userInfo?["message"] as? String {
                showStatusBanner(message)
            }
        }
        .onChange(of: asyncOperationManager.hasRunningOperations) { _, newValue in
            // When overlays disappear, reclaim focus for ESC key
            if !newValue {
                hasKeyboardFocus = true
            }
        }
        // Keep navigation sequence in sync with summary filter state
        .onChange(of: showAllSummaryItems) { _, showAll in
            stateMachine.customSequence = showAll ? nil : navSequence
        }
        .onChange(of: stateMachine.currentPage) { oldPage, newPage in
            AppLogger.shared.log("🧭 [Wizard] View detected page change: \(oldPage) → \(newPage)")
            if newPage == .summary, !isValidating {
                refreshSystemState(showSpinner: true, previousPage: oldPage)
            }
        }
        .onChange(of: navSequence) { _, newSeq in
            if !showAllSummaryItems {
                stateMachine.customSequence = newSeq
            }
        }
        .onChange(of: showingCloseConfirmation) { _, newValue in
            // Reclaim focus when close confirmation dialog closes
            if !newValue {
                hasKeyboardFocus = true
            }
        }
        // Add keyboard navigation support for left/right arrow keys and ESC (macOS 14.0+)
        .modifier(
            KeyboardNavigationModifier(
                onLeftArrow: navigateToPreviousPage,
                onRightArrow: navigateToNextPage,
                onEscape: forciblyCloseWizard
            )
        )
        // Ensure ESC always closes the wizard, even if key focus isn't on our view
        .onExitCommand {
            forciblyCloseWizard()
        }
        .task {
            // Monitor state changes
            await monitorSystemState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardSmAppServiceApprovalRequired)) { _ in
            showingBackgroundApprovalPrompt = true
        }
        .alert("Close Setup Wizard?", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                showingCloseConfirmation = false
            }
            Button("Close Anyway", role: .destructive) {
                forceInstantClose()
                performBackgroundCleanup()
            }
            .keyboardShortcut(.defaultAction) // Return key for destructive action
        } message: {
            let criticalCount = stateMachine.wizardIssues.filter { $0.severity == .critical }.count
            Text(
                "There \(criticalCount == 1 ? "is" : "are") \(criticalCount) critical \(criticalCount == 1 ? "issue" : "issues") "
                    + "that may prevent KeyPath from working properly. Are you sure you want to close the setup wizard?"
            )
        }
        .alert("Enable KeyPath in Login Items", isPresented: $showingBackgroundApprovalPrompt) {
            Button("OK") {
                showingBackgroundApprovalPrompt = false
                openLoginItemsSettings()
            }
            .keyboardShortcut(.defaultAction)
            Button("Later", role: .cancel) {
                showingBackgroundApprovalPrompt = false
                stopLoginItemsApprovalPolling()
            }
        } message: {
            Text(
                "Login Items will open. Find KeyPath under Background Items and flip the switch to enable it."
            )
        }
        .onChange(of: showingBackgroundApprovalPrompt) { _, isShowing in
            if isShowing {
                // Start polling immediately when dialog appears, so approval is detected
                // even if user enables KeyPath before clicking OK
                startLoginItemsApprovalPolling()
            }
        }
    }
}
