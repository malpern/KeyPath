import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var kanataViewModel: KanataViewModel

    /// Access underlying RuntimeCoordinator for business logic
    var kanataManager: RuntimeCoordinator {
        kanataViewModel.underlyingManager
    }

    @MainActor
    func showStatusBanner(_ message: String) {
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
    var initialPage: WizardPage?

    // New architecture components
    @StateObject var stateMachine = WizardStateMachine()
    @StateObject var autoFixer = WizardAutoFixerManager()
    let stateInterpreter = WizardStateInterpreter()
    @State var asyncOperationManager = WizardAsyncOperationManager()
    @State var toastManager = WizardToastManager()

    // UI state
    @State var isValidating: Bool = true // Track validation state for gear icon
    @State var preflightStart = Date()
    @State var evaluationProgress: Double = 0.0
    // stateMachine.wizardState and stateMachine.wizardIssues now live in stateMachine (single source of truth)
    @State var showAllSummaryItems: Bool = false
    @State var navSequence: [WizardPage] = []
    @State var inFlightFixActions: Set<AutoFixAction> = []
    @State var showingBackgroundApprovalPrompt = false
    @State var currentFixAction: AutoFixAction?
    @State var fixInFlight: Bool = false
    @State var lastRefreshAt: Date?
    @State var showingStartConfirmation = false
    @State var startConfirmationResult: CheckedContinuation<Bool, Never>?
    @State var showingCloseConfirmation = false

    // Task management for race condition prevention
    @State var refreshTask: Task<Void, Never>?
    @State var isForceClosing = false // Prevent new operations after nuclear close
    @State var loginItemsPollingTask: Task<Void, Never>? // Polls for Login Items approval
    @State var statusBannerMessage: String?
    @State var statusBannerTimestamp: Date?

    /// Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    var currentFixDescriptionForUI: String? {
        guard let currentFixAction else { return nil }
        return describeAutoFixActionForUI(currentFixAction)
    }

    var body: some View {
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
                    .overlay {
                        // Don't show overlay during validation - summary page has its own gear
                        if asyncOperationManager.hasRunningOperations, !isValidating {
                            operationProgressOverlay()
                                .allowsHitTesting(false) // Don't block X button interaction
                        }
                    }
            }
            .frame(width: WizardDesign.Layout.pageWidth)
            .frame(maxHeight: (stateMachine.currentPage == .summary) ? 540 : .infinity) // Grow up to cap, then scroll
            .fixedSize(horizontal: true, vertical: false) // Allow vertical growth; keep width fixed
            .animation(.easeInOut(duration: 0.25), value: isValidating)
            // Prevent vertical position animation during page transitions
            .animation(nil, value: stateMachine.currentPage)
            // Remove animation on frame changes to prevent window movement
            .background(WizardDesign.Colors.wizardBackground) // Simple solid background, no visual effect
        }
        .withToasts(toastManager)
        .environmentObject(stateMachine)
        .focused($hasKeyboardFocus) // Enable focus for reliable ESC key handling
        // Aggressively disable focus rings during validation
        .onChange(of: isValidating) { _, newValue in
            if newValue {
                // Clear focus when validation starts
                DispatchQueue.main.async {
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
        // Global Close button overlay for all detail pages
        .overlay(alignment: .topTrailing) {
            if stateMachine.currentPage != .summary {
                CloseButton()
                    .environmentObject(stateMachine)
                    .padding(.top, 8 + 4) // Extra padding from edge
                    .padding(.trailing, 8 + 4) // Extra padding from edge
                    // Prevent close button from animating during page transitions
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
            // Notify window to resize for new content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .wizardContentSizeChanged, object: nil)
            }
        }
        .onChange(of: navSequence) { _, newSeq in
            if !showAllSummaryItems {
                stateMachine.customSequence = newSeq
            }
        }
        .onChange(of: showingStartConfirmation) { _, newValue in
            // Reclaim focus when start confirmation dialog closes
            if !newValue {
                hasKeyboardFocus = true
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
        .onReceive(NotificationCenter.default.publisher(for: .smAppServiceApprovalRequired)) { _ in
            showingBackgroundApprovalPrompt = true
        }
        .overlay {
            if showingStartConfirmation {
                StartConfirmationDialog(
                    isPresented: $showingStartConfirmation,
                    onConfirm: {
                        startConfirmationResult?.resume(returning: true)
                        startConfirmationResult = nil
                    },
                    onCancel: {
                        startConfirmationResult?.resume(returning: false)
                        startConfirmationResult = nil
                    }
                )
            }
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
