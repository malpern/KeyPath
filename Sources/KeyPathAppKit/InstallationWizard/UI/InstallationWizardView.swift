import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataViewModel: KanataViewModel

    // Access underlying RuntimeCoordinator for business logic
    private var kanataManager: RuntimeCoordinator {
        kanataViewModel.underlyingManager
    }

    @MainActor
    private func showStatusBanner(_ message: String) {
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

    // Optional initial page to navigate to
    var initialPage: WizardPage?

    // New architecture components
    @StateObject private var stateMachine = WizardStateMachine()
    @StateObject private var autoFixer = WizardAutoFixerManager()
    private let stateInterpreter = WizardStateInterpreter()
    @State private var asyncOperationManager = WizardAsyncOperationManager()
    @State private var toastManager = WizardToastManager()

    // UI state
    @State private var isValidating: Bool = true // Track validation state for gear icon
    @State private var preflightStart = Date()
    @State private var evaluationProgress: Double = 0.0
    @State private var systemState: WizardSystemState = .initializing
    @State private var currentIssues: [WizardIssue] = []
    @State private var showAllSummaryItems: Bool = false
    @State private var navSequence: [WizardPage] = []
    @State private var inFlightFixActions: Set<AutoFixAction> = []
    @State private var showingBackgroundApprovalPrompt = false
    @State private var currentFixAction: AutoFixAction?
    @State private var fixInFlight: Bool = false
    @State private var lastRefreshAt: Date?

    // Task management for race condition prevention
    @State private var refreshTask: Task<Void, Never>?
    @State private var isForceClosing = false // Prevent new operations after nuclear close
    @State private var loginItemsPollingTask: Task<Void, Never>? // Polls for Login Items approval
    @State private var statusBannerMessage: String?
    @State private var statusBannerTimestamp: Date?

    // Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    private var currentFixDescriptionForUI: String? {
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
            let criticalCount = currentIssues.filter { $0.severity == .critical }.count
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

    // MARK: - UI Components

    // Header removed per design update; pages present their own centered titles.

    @ViewBuilder
    private func pageContent() -> some View {
        ZStack {
            switch stateMachine.currentPage {
            case .summary:
                WizardSummaryPage(
                    systemState: systemState,
                    issues: currentIssues,
                    stateInterpreter: stateInterpreter,
                    onStartService: startKanataService,
                    onDismiss: { dismissAndRefreshMainScreen() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    isValidating: isValidating,
                    showAllItems: $showAllSummaryItems,
                    navSequence: $navSequence
                )
            case .fullDiskAccess:
                WizardFullDiskAccessPage(
                    systemState: systemState,
                    issues: currentIssues
                )
            case .conflicts:
                WizardConflictsPage(
                    systemState: systemState,
                    issues: currentIssues.filter { $0.category == .conflicts },
                    allIssues: currentIssues,
                    isFixing: fixInFlight,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .inputMonitoring:
                WizardInputMonitoringPage(
                    systemState: systemState,
                    issues: currentIssues.filter { $0.category == .permissions },
                    allIssues: currentIssues,
                    stateInterpreter: stateInterpreter,
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: kanataManager
                )
            case .accessibility:
                WizardAccessibilityPage(
                    systemState: systemState,
                    issues: currentIssues.filter { $0.category == .permissions },
                    allIssues: currentIssues,
                    onRefresh: { refreshSystemState() },
                    onNavigateToPage: { page in
                        stateMachine.navigateToPage(page)
                    },
                    onDismiss: {
                        dismissAndRefreshMainScreen()
                    },
                    kanataManager: kanataManager
                )
            case .karabinerComponents:
                WizardKarabinerComponentsPage(
                    systemState: systemState,
                    issues: currentIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .kanataComponents:
                WizardKanataComponentsPage(
                    systemState: systemState,
                    issues: currentIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .kanataMigration:
                WizardKanataMigrationPage(
                    onMigrationComplete: { hasRunningKanata in
                        // After migration, check if we need to stop external kanata
                        if hasRunningKanata {
                            stateMachine.navigateToPage(.stopExternalKanata)
                        } else {
                            // No running kanata, continue to next step
                            refreshSystemState()
                            if currentIssues.contains(where: { $0.category == .installation && $0.identifier == .component(.kanataBinaryMissing) }) {
                                stateMachine.navigateToPage(.kanataComponents)
                            } else {
                                stateMachine.navigateToPage(.summary)
                            }
                        }
                    },
                    onSkip: {
                        // Skip migration, continue to next step
                        refreshSystemState()
                        stateMachine.navigateToPage(.summary)
                    }
                )
            case .stopExternalKanata:
                WizardStopKanataPage(
                    onComplete: {
                        // After stopping, refresh state and continue
                        refreshSystemState()
                        if currentIssues.contains(where: { $0.category == .installation && $0.identifier == .component(.kanataBinaryMissing) }) {
                            stateMachine.navigateToPage(.kanataComponents)
                        } else {
                            stateMachine.navigateToPage(.summary)
                        }
                    },
                    onCancel: {
                        // User cancelled, go back to migration
                        stateMachine.navigateToPage(.kanataMigration)
                    }
                )
            case .helper:
                WizardHelperPage(
                    systemState: systemState,
                    issues: currentIssues,
                    isFixing: fixInFlight,
                    blockingFixDescription: currentFixDescriptionForUI,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshSystemState() },
                    kanataManager: kanataManager
                )
            case .communication:
                WizardCommunicationPage(
                    systemState: systemState,
                    issues: currentIssues,
                    onAutoFix: performAutoFix
                )
            case .service:
                WizardKanataServicePage(
                    systemState: systemState,
                    issues: currentIssues,
                    onRefresh: { refreshSystemState() }
                )
            }
        }
        // Directional page transition based on navigation direction
        .transition(
            stateMachine.isNavigatingForward
                ? WizardDesign.Transition.pageSlideForward
                : WizardDesign.Transition.pageSlideBackward
        )
    }

    @ViewBuilder
    private func operationProgressOverlay() -> some View {
        let operationName = getCurrentOperationName()

        // Minimal overlay for system state detection - just progress indicator
        if operationName.contains("System State Detection") {
            ProgressView()
                .scaleEffect(1.0)
        } else {
            // Enhanced overlay with cancellation support
            VStack(spacing: 16) {
                WizardOperationProgress(
                    operationName: operationName,
                    progress: getCurrentOperationProgress(),
                    isIndeterminate: isCurrentOperationIndeterminate()
                )

                // No cancel button - use X in top-right instead
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - State Management

    private func setupWizard() async {
        AppLogger.shared.log("🔍 [Wizard] Setting up wizard with new architecture")

        // Always reset navigation state for fresh run
        stateMachine.navigationEngine.resetNavigationState()

        // Configure state providers
        stateMachine.configure(kanataManager: kanataManager)
        autoFixer.configure(
            kanataManager: kanataManager,
            toastManager: toastManager,
            statusReporter: { message in
                showStatusBanner(message)
                Task { await WizardTelemetry.shared.record(
                    WizardEvent(
                        timestamp: Date(),
                        category: .statusBanner,
                        name: "banner",
                        result: nil,
                        details: ["message": message]
                    )
                ) }
            }
        )

        // Show summary page immediately with validation state
        // Determine initial page based on cached system snapshot (if available)
        let preferredPage = await cachedPreferredPage()
        if let preferredPage, initialPage == nil {
            AppLogger.shared.log("🔍 [Wizard] Preferring cached page: \(preferredPage)")
            stateMachine.navigateToPage(preferredPage)
        } else if let initialPage {
            AppLogger.shared.log("🔍 [Wizard] Navigating to initial page override: \(initialPage)")
            stateMachine.navigateToPage(initialPage)
        } else {
            stateMachine.navigateToPage(.summary)
        }

        Task {
            await MainActor.run {
                // Start validation state
                preflightStart = Date()
                evaluationProgress = 0.0
                isValidating = true
                systemState = .initializing
                currentIssues = []
                AppLogger.shared.log("🚀 [Wizard] Summary page shown immediately, starting validation")
                AppLogger.shared.log("⏱️ [TIMING] Wizard validation START")
            }

            // Small delay to ensure UI is ready before starting heavy checks
            _ = await WizardSleep.ms(100) // 100ms delay

            guard !Task.isCancelled else { return }
            await performInitialStateCheck()
        }
    }

    private func performInitialStateCheck(retryAllowed: Bool = true) async {
        // Check if user has already closed wizard
        guard !Task.isCancelled else {
            AppLogger.shared.log("🔍 [Wizard] Initial state check cancelled - wizard closing")
            return
        }

        // Check if force closing flag is set
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Initial state check blocked - force closing in progress")
            return
        }

        AppLogger.shared.log("🔍 [Wizard] Performing initial state check")
        AppLogger.shared.log("⏱️ [TIMING] Wizard validation START")

        let operation = WizardOperations.stateDetection(
            stateMachine: stateMachine,
            progressCallback: { progress in
                // Update progress on MainActor (callback may be called from background)
                Task { @MainActor in
                    evaluationProgress = progress
                }
            }
        )

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            let wizardDuration = Date().timeIntervalSince(preflightStart)
            AppLogger.shared.log(
                "⏱️ [TIMING] Wizard validation COMPLETE: \(String(format: "%.3f", wizardDuration))s")

            // Freshness guard: drop stale results and retry once
            if !isFresh(result) {
                AppLogger.shared.log(
                    "⚠️ [Wizard] Discarding stale initial state result (age: \(snapshotAge(result))s)."
                )
                if retryAllowed {
                    Task { await performInitialStateCheck(retryAllowed: false) }
                } else {
                    AppLogger.shared.log(
                        "⚠️ [Wizard] Stale result retry already attempted; keeping existing state.")
                }
                return
            }

            let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
            systemState = result.state
            currentIssues = filteredIssues
            stateMachine.lastWizardSnapshot = WizardSnapshotRecord(
                state: result.state, issues: filteredIssues
            )
            // Start at summary page - no auto navigation
            // stateMachine.autoNavigateIfNeeded(for: result.state, issues: result.issues)

            // Transition to results immediately when validation completes
            Task { @MainActor in
                // Mark validation as complete - this will transition gear to final icon
                withAnimation(.easeInOut(duration: 0.25)) {
                    isValidating = false
                }
            }

            AppLogger.shared.log(
                "🔍 [Wizard] Initial setup - State: \(result.state), Issues: \(filteredIssues.count), Target Page: \(stateMachine.currentPage)"
            )
            AppLogger.shared.log(
                "🔍 [Wizard] Issue details: \(filteredIssues.map { "\($0.category)-\($0.title)" })")

            Task { @MainActor in
                if shouldNavigateToSummary(
                    currentPage: stateMachine.currentPage,
                    state: result.state,
                    issues: filteredIssues
                ) {
                    AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
                    stateMachine.navigateToPage(.summary)
                } else if let preferred = await preferredDetailPage(for: result.state, issues: filteredIssues),
                          stateMachine.currentPage != preferred {
                    AppLogger.shared.log("🔍 [Wizard] Deterministic routing to \(preferred) (single blocker)")
                    stateMachine.navigateToPage(preferred)
                } else if stateMachine.currentPage == .summary {
                    // Wait a tick for navSequence to be updated by WizardSystemStatusOverview's onChange handlers
                    _ = await WizardSleep.ms(50) // 50ms
                    autoNavigateIfSingleIssue(in: filteredIssues, state: result.state)
                }
            }

            // Targeted auto-navigation: if helper isn't installed, go to Helper page first
            let recommended = await stateMachine.navigationEngine
                .determineCurrentPage(for: result.state, issues: filteredIssues)
            if recommended == .helper, stateMachine.currentPage == .summary {
                AppLogger.shared.log("🔍 [Wizard] Auto-navigating to Helper page (helper missing)")
                stateMachine.navigateToPage(.helper)
            }
        }
    }

    private func monitorSystemState() async {
        AppLogger.shared.log("🟡 [MONITOR] System state monitoring started with 60s interval")

        // Smart monitoring: Only poll when needed, much less frequently
        while !Task.isCancelled {
            _ = await WizardSleep.seconds(60) // 60 seconds instead of 10

            // Skip state detection if async operations are running to avoid conflicts
            guard !asyncOperationManager.hasRunningOperations else {
                continue
            }

            // Only poll if we're on summary page or user recently interacted
            let shouldPoll = shouldPerformBackgroundPolling()
            guard shouldPoll else {
                continue
            }

            // Use page-specific detection instead of full system scan
            await performSmartStateCheck()
        }

        AppLogger.shared.log("🟡 [MONITOR] System state monitoring stopped")
    }

    /// Determine if background polling is needed
    private func shouldPerformBackgroundPolling() -> Bool {
        // Only poll on summary page where overview is shown
        stateMachine.currentPage == .summary
    }

    /// Perform targeted state check based on current page
    private func performSmartStateCheck(retryAllowed: Bool = true) async {
        // Check if force closing is in progress
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Smart state check blocked - force closing in progress")
            return
        }

        switch stateMachine.currentPage {
        case .summary:
            // Full check only for summary page
            let operation = WizardOperations.stateDetection(
                stateMachine: stateMachine,
                progressCallback: { _ in }
            )
            asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
                let oldState = systemState
                let oldPage = stateMachine.currentPage

                // Freshness guard: drop stale results and retry once
                if !isFresh(result) {
                    AppLogger.shared.log(
                        "⚠️ [Wizard] Ignoring stale smart state result (age: \(snapshotAge(result))s)."
                    )
                    if retryAllowed {
                        Task { await performSmartStateCheck(retryAllowed: false) }
                    } else {
                        AppLogger.shared.log(
                            "⚠️ [Wizard] Stale smart-state retry already attempted; leaving state unchanged.")
                    }
                    return
                }

                let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
                systemState = result.state
                currentIssues = filteredIssues

                AppLogger.shared.log(
                    "🔍 [Navigation] Current: \(stateMachine.currentPage), Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
                )

                // No auto-navigation - stay on current page
                // stateMachine.autoNavigateIfNeeded(for: result.state, issues: result.issues)

                Task { @MainActor in
                    if shouldNavigateToSummary(
                        currentPage: stateMachine.currentPage,
                        state: result.state,
                        issues: filteredIssues
                    ) {
                        AppLogger.shared.log(
                            "🟢 [Wizard] Healthy system detected during monitor; routing to summary")
                        stateMachine.navigateToPage(.summary)
                    }
                }

                if oldState != systemState || oldPage != stateMachine.currentPage {
                    AppLogger.shared.log(
                        "🔍 [Wizard] State changed: \(oldState) -> \(systemState), page: \(oldPage) -> \(stateMachine.currentPage)"
                    )
                }
            }
        case .inputMonitoring, .accessibility, .conflicts:
            // 🎯 Phase 2: Quick checks removed - SystemValidator does full check
            // The full check is fast enough (<1s) and prevents partial state issues
            // If needed later, can add specific quick methods to SystemValidator
            break
        default:
            // No background polling for other pages
            break
        }
    }

    // MARK: - Freshness Guard

    private func isFresh(_ result: SystemStateResult) -> Bool {
        snapshotAge(result) <= 3.0
    }

    private func snapshotAge(_ result: SystemStateResult) -> TimeInterval {
        Date().timeIntervalSince(result.detectionTimestamp)
    }

    // MARK: - Actions

    private func performAutoFix() {
        AppLogger.shared.log(
            "🔍 [Wizard] *** FIX BUTTON CLICKED *** Auto-fix started via InstallerEngine")
        AppLogger.shared.log("🔍 [Wizard] Current issues: \(currentIssues.count) total")

        // Log each current issue for debugging
        for (index, issue) in currentIssues.enumerated() {
            if let autoFixAction = issue.autoFixAction {
                AppLogger.shared.log(
                    "🔍 [Wizard] Issue \(index): \(issue.identifier) -> AutoFix: \(autoFixAction)")
            } else {
                AppLogger.shared.log(
                    "🔍 [Wizard] Issue \(index): \(issue.identifier) -> AutoFix: nil")
            }
        }

        // Use InstallerEngine to repair all issues at once (with façade fast-path)
        Task {
            guard !fixInFlight else {
                await MainActor.run {
                    toastManager.showInfo("Another fix is already running…", duration: 3.0)
                }
                return
            }
            await MainActor.run { fixInFlight = true }
            defer { Task { @MainActor in fixInFlight = false } }

            let smState = await KanataDaemonManager.shared.refreshManagementState()
            if smState == .smappservicePending {
                await MainActor.run {
                    toastManager.showError(
                        "Enable KeyPath in System Settings → Login Items before running Fix.",
                        duration: 6.0
                    )
                }
                return
            }

            if await attemptFastRestartFix() {
                AppLogger.shared.log(
                    "✅ [Wizard] Fast-path restart resolved issues; skipping InstallerEngine repair"
                )
                return
            }

            if await attemptAutoFixActions() {
                AppLogger.shared.log(
                    "✅ [Wizard] Auto-fix actions resolved issues; skipping InstallerEngine repair"
                )
                await MainActor.run {
                    toastManager.showSuccess("Issues resolved", duration: 4.0)
                }
                return
            }

            let report = await kanataManager.runFullRepair(reason: "Wizard Fix button fallback repair")

            await MainActor.run {
                if report.success {
                    let successCount = report.executedRecipes.filter(\.success).count
                    let totalCount = report.executedRecipes.count
                    if totalCount > 0 {
                        toastManager.showSuccess(
                            "Repaired \(successCount) of \(totalCount) issue(s) successfully",
                            duration: 5.0
                        )
                    } else {
                        toastManager.showInfo("No issues found to repair", duration: 3.0)
                    }
                } else {
                    let failureReason = report.failureReason ?? "Unknown error"
                    toastManager.showError("Repair failed: \(failureReason)", duration: 7.0)
                }
            }

            // Log report details
            AppLogger.shared.log(
                "🔧 [Wizard] InstallerEngine repair completed - success: \(report.success)")
            AppLogger.shared.log("🔧 [Wizard] Executed recipes: \(report.executedRecipes.count)")
            for (index, result) in report.executedRecipes.enumerated() {
                AppLogger.shared.log(
                    "🔧 [Wizard] Recipe \(index + 1): \(result.recipeID) - \(result.success ? "success" : "failed")"
                )
            }
            if let failureReason = report.failureReason {
                AppLogger.shared.log("❌ [Wizard] Failure reason: \(failureReason)")
            }

            // Refresh state after repair
            refreshSystemState()

            // Post-repair health check for VHID-related issues
            if currentIssues.contains(where: { issue in
                if let action = issue.autoFixAction {
                    return action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon
                }
                return false
            }) {
                Task {
                    _ = await WizardSleep.seconds(2) // allow services to settle
                    let latestResult = await stateMachine.detectCurrentState()
                    let filteredIssues = sanitizedIssues(from: latestResult.issues, for: latestResult.state)
                    await MainActor.run {
                        systemState = latestResult.state
                        currentIssues = filteredIssues
                    }
                    let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
                        systemState: latestResult.state,
                        issues: filteredIssues
                    )
                    AppLogger.shared.log(
                        "🔍 [Wizard] Post-repair health check: karabinerStatus=\(karabinerStatus)")
                    if karabinerStatus != .completed {
                        let detail = await kanataManager.getVirtualHIDBreakageSummary()
                        AppLogger.shared.log(
                            "❌ [Wizard] Post-repair health check failed; showing diagnostic toast")
                        await MainActor.run {
                            toastManager.showError(
                                "Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0
                            )
                        }
                    }
                }
            }
        }
    }

    private func attemptFastRestartFix() async -> Bool {
        AppLogger.shared.log(
            "🔄 [Wizard] Attempting KanataService restart before running InstallerEngine repair"
        )
        let restarted = await kanataManager.restartServiceWithFallback(
            reason: "Wizard Fix button fast path"
        )
        guard restarted else {
            AppLogger.shared.warn("⚠️ [Wizard] Fast-path restart failed; falling back to InstallerEngine")
            return false
        }

        let latestResult = await stateMachine.detectCurrentState()
        let filteredIssues = await MainActor.run { applySystemStateResult(latestResult) }

        let resolved = filteredIssues.isEmpty && latestResult.state == .active

        if resolved {
            await MainActor.run {
                toastManager.showSuccess("Kanata service recovered", duration: 4.0)
            }
        } else {
            AppLogger.shared.log(
                "ℹ️ [Wizard] Fast-path restart completed but issues remain (\(filteredIssues.count) issue(s))"
            )
        }

        return resolved
    }

    private func attemptAutoFixActions() async -> Bool {
        guard autoFixer.autoFixer != nil else {
            AppLogger.shared.warn("⚠️ [Wizard] AutoFixer not configured - cannot run auto-fix actions")
            return false
        }

        let issuesSnapshot = await MainActor.run { currentIssues }
        let uniqueActions = Array(Set(issuesSnapshot.compactMap(\.autoFixAction)))
        guard !uniqueActions.isEmpty else {
            AppLogger.shared.log("ℹ️ [Wizard] No auto-fix actions available for current issues")
            return false
        }

        AppLogger.shared.log("🔧 [Wizard] Attempting \(uniqueActions.count) auto-fix action(s) before InstallerEngine repair")

        for action in uniqueActions {
            AppLogger.shared.log("🔧 [Wizard] Running auto-fix action: \(action)")
            let success = await autoFixer.performAutoFix(action)
            AppLogger.shared.log("🔧 [Wizard] Auto-fix action \(action) completed with success=\(success)")
            guard success else { continue }

            let latestResult = await stateMachine.detectCurrentState()
            let filteredIssues = await MainActor.run { applySystemStateResult(latestResult) }
            let resolved = filteredIssues.isEmpty && latestResult.state == .active

            if resolved {
                AppLogger.shared.log("✅ [Wizard] System healthy after auto-fix action: \(action)")
                return true
            }
        }

        AppLogger.shared.log("ℹ️ [Wizard] Auto-fix actions did not fully resolve issues")
        return false
    }

    private func performAutoFix(_ action: AutoFixAction, suppressToast: Bool = false) async -> Bool {
        // Single-flight guard for Fix buttons
        if inFlightFixActions.contains(action) {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showInfo("Fix already running…", duration: 3.0)
                }
            }
            return false
        }
        if fixInFlight {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showInfo("Another fix is already running…", duration: 3.0)
                }
            }
            return false
        }
        inFlightFixActions.insert(action)
        currentFixAction = action
        fixInFlight = true
        defer {
            inFlightFixActions.remove(action)
            currentFixAction = nil
            fixInFlight = false
        }

        AppLogger.shared.log("🔧 [Wizard] Auto-fix for specific action: \(action)")

        // Short-circuit service installs when Login Items approval is pending
        if action == .installLaunchDaemonServices || action == .restartUnhealthyServices,
           await KanataDaemonManager.shared.refreshManagementState() == .smappservicePending {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showError(
                        "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' then click Fix again.",
                        duration: 7.0
                    )
                }
            }
            return false
        }
        // Give VHID/launch-service operations more time
        let timeoutSeconds = switch action {
        case .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
             .installLaunchDaemonServices:
            30.0
        default:
            12.0
        }
        let actionDescription = getAutoFixActionDescription(action)

        let smState = await KanataDaemonManager.shared.refreshManagementState()

        let deferToastActions: Set<AutoFixAction> = [
            .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
            .installLaunchDaemonServices
        ]
        let deferSuccessToast = deferToastActions.contains(action)
        var successToastPending = false

        let success: Bool
        do {
            success = try await runWithTimeout(seconds: timeoutSeconds) {
                await autoFixer.performAutoFix(action)
            }
        } catch {
            let stateSummary = await describeServiceState()
            if !suppressToast {
                await MainActor.run {
                    toastManager.showError(
                        "Fix timed out after \(Int(timeoutSeconds))s. \(stateSummary)", duration: 7.0
                    )
                }
            }
            AppLogger.shared.log("⚠️ [Wizard] Auto-fix timed out for action: \(action)")
            return false
        }

        let errorMessage = success ? "" : await getDetailedErrorMessage(for: action, actionDescription: actionDescription)

        if !suppressToast {
            await MainActor.run {
                if success {
                    if deferSuccessToast {
                        successToastPending = true
                        toastManager.showInfo("Verifying…", duration: 3.0)
                    } else {
                        toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                    }
                } else {
                    let message = (!success && smState == .smappservicePending) ?
                        "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' and click Fix again."
                        : errorMessage
                    toastManager.showError(message, duration: 7.0)
                }
            }
        }

        AppLogger.shared.log("🔧 [Wizard] Single-action fix completed - success: \(success)")

        // Refresh system state after auto-fix
        Task {
            // Shorter delay - we have warm-up window to handle startup
            _ = await WizardSleep.seconds(1) // allow services to start
            refreshSystemState()

            // Notify StartupValidator to refresh main screen status
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
            AppLogger.shared.log(
                "🔄 [Wizard] Triggered StartupValidator refresh after successful auto-fix")

            // Schedule a follow-up health check; if still red, show a diagnostic error toast
            Task {
                _ = await WizardSleep.seconds(2) // allow additional settle time
                let latestResult = await stateMachine.detectCurrentState()
                let filteredIssues = sanitizedIssues(from: latestResult.issues, for: latestResult.state)
                await MainActor.run {
                    systemState = latestResult.state
                    currentIssues = filteredIssues
                }
                let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
                    systemState: latestResult.state,
                    issues: filteredIssues
                )
                AppLogger.shared.log("🔍 [Wizard] Post-fix health check: karabinerStatus=\(karabinerStatus)")
                if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon ||
                    action == .installCorrectVHIDDriver || action == .repairVHIDDaemonServices {
                    let smStatePost = await KanataDaemonManager.shared.refreshManagementState()
                    // IMPORTANT: Run off MainActor to avoid blocking UI - detectConnectionHealth spawns pgrep subprocesses
                    let vhidHealthy = await Task.detached {
                        await VHIDDeviceManager().detectConnectionHealth()
                    }.value

                    if karabinerStatus == .completed || vhidHealthy {
                        if successToastPending, !suppressToast {
                            await MainActor.run {
                                toastManager.showSuccess(
                                    "\(actionDescription) completed successfully", duration: 5.0
                                )
                            }
                        }
                    } else if !suppressToast {
                        let detail = await kanataManager.getVirtualHIDBreakageSummary()
                        AppLogger.shared.log(
                            "❌ [Wizard] Post-fix health check failed; will show diagnostic toast")
                        await MainActor.run {
                            if smStatePost == .smappservicePending {
                                toastManager.showError(
                                    "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' and click Fix again.",
                                    duration: 7.0
                                )
                            } else {
                                toastManager.showError(
                                    "Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0
                                )
                            }
                        }
                    }
                }
            }
        }

        return success
    }

    /// UI-only descriptions for auto-fix actions (delegated to AutoFixActionDescriptions)
    private func describeAutoFixActionForUI(_ action: AutoFixAction) -> String {
        AutoFixActionDescriptions.describe(action)
    }

    /// Get user-friendly description for auto-fix actions
    private func getAutoFixActionDescription(_ action: AutoFixAction) -> String {
        AppLogger.shared.log("🔍 [ActionDescription] getAutoFixActionDescription called for: \(action)")
        let description = AutoFixActionDescriptions.describe(action)
        AppLogger.shared.log("🔍 [ActionDescription] Returning description: \(description)")
        return description
    }

    // MARK: - Unified State Refresh

    /// Consolidated refresh method that handles all refresh scenarios
    /// - Parameters:
    ///   - showSpinner: Whether to show the validating spinner (used when returning to summary)
    ///   - previousPage: The page we're coming from (enables special handling for communication page)
    private func refreshSystemState(showSpinner: Bool = false, previousPage: WizardPage? = nil) {
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Refresh blocked - force closing in progress")
            return
        }

        // Debounce rapid refreshes
        let now = Date()
        if let last = lastRefreshAt, now.timeIntervalSince(last) < 0.3 {
            AppLogger.shared.log("🔍 [Wizard] Refresh skipped (debounced)")
            return
        }
        lastRefreshAt = now

        AppLogger.shared.log("🔍 [Wizard] Refreshing system state (showSpinner=\(showSpinner), from=\(previousPage?.rawValue ?? "nil"))")

        // Cancel any previous refresh task
        refreshTask?.cancel()

        // Show spinner if requested (used when returning to summary page)
        if showSpinner {
            withAnimation(.easeInOut(duration: 0.2)) {
                isValidating = true
            }
            currentIssues = []
        }

        refreshTask = Task { [previousPage, showSpinner] in
            // Wait for in-flight operations to complete (only when showing spinner)
            if showSpinner, await MainActor.run(body: { asyncOperationManager.hasRunningOperations }) {
                AppLogger.shared.log("🔍 [Wizard] Refresh waiting for in-flight operations")
                while !Task.isCancelled,
                      await MainActor.run(body: { asyncOperationManager.hasRunningOperations }) {
                    _ = await WizardSleep.ms(200)
                }
            }

            guard !Task.isCancelled else { return }

            // Give TCP server time to recover after leaving communication page
            if previousPage == .communication {
                _ = await WizardSleep.seconds(1)
            }

            // Run state detection with optional retry for communication page
            await MainActor.run {
                performStateDetection(
                    previousPage: previousPage,
                    attempt: 0,
                    showSpinner: showSpinner
                )
            }
        }
    }

    /// Internal: Performs state detection with retry logic for communication page
    @MainActor
    private func performStateDetection(previousPage: WizardPage?, attempt: Int, showSpinner: Bool) {
        guard !isForceClosing else { return }

        let operation = WizardOperations.stateDetection(
            stateMachine: stateMachine,
            progressCallback: { _ in }
        )

        asyncOperationManager.execute(operation: operation) { [previousPage, attempt, showSpinner] (result: SystemStateResult) in
            // Retry once if coming from communication page and seeing transient issues
            if previousPage == .communication, attempt == 0, shouldRetryForCommunication(result: result) {
                AppLogger.shared.log("🔍 [Wizard] Deferring result for TCP warm-up, will retry")
                Task {
                    _ = await WizardSleep.seconds(1.5)
                    await MainActor.run {
                        performStateDetection(previousPage: previousPage, attempt: 1, showSpinner: showSpinner)
                    }
                }
                return
            }

            _ = applySystemStateResult(result)

            if showSpinner {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isValidating = false
                }
            }
        }
    }

    /// Check if we should retry due to transient communication issues
    private func shouldRetryForCommunication(result: SystemStateResult) -> Bool {
        // Retry if service appears not running
        switch result.state {
        case .serviceNotRunning, .daemonNotRunning:
            return true
        default:
            break
        }

        // Also retry if there are transient communication issues (TCP warm-up)
        return result.issues.contains { issue in
            guard case let .component(component) = issue.identifier else { return false }
            switch component {
            case .kanataTCPServer,
                 .communicationServerConfiguration,
                 .communicationServerNotResponding,
                 .tcpServerConfiguration,
                 .tcpServerNotResponding:
                return true
            default:
                return false
            }
        }
    }

    @MainActor
    private func autoNavigateIfSingleIssue(in issues: [WizardIssue], state _: WizardSystemState) {
        AppLogger.shared.log("🔍 [AutoNav] ===== autoNavigateIfSingleIssue CALLED =====")
        AppLogger.shared.log("🔍 [AutoNav] Current page: \(stateMachine.currentPage)")
        AppLogger.shared.log("🔍 [AutoNav] Issues count: \(issues.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence count: \(navSequence.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence pages: \(navSequence.map(\.displayName))")

        guard stateMachine.currentPage == .summary else {
            AppLogger.shared.log("🔍 [AutoNav] SKIP: Not on summary page")
            return
        }

        // If there's exactly 1 item in the summary list, navigate to it directly
        // navSequence represents what's actually displayed, so trust it
        guard navSequence.count == 1, let targetPage = navSequence.first else {
            AppLogger.shared.log(
                "🔍 [AutoNav] ❌ NOT AUTO-NAVIGATING: navSequence has \(navSequence.count) items")
            return
        }

        AppLogger.shared.log("🔍 [AutoNav] ✅ AUTO-NAVIGATING to \(targetPage) (single item in summary)")
        stateMachine.navigateToPage(targetPage)
        AppLogger.shared.log("🔍 [AutoNav] Navigation command sent")
    }

    private func preferredDetailPage(for state: WizardSystemState, issues: [WizardIssue])
        async -> WizardPage? {
        let page = await stateMachine.navigationEngine.determineCurrentPage(
            for: state, issues: issues
        )
        guard page != .summary else { return nil }

        let hasExactlyOneIssue = issues.count == 1
        let serviceOnly = issues.isEmpty && page == .service
        return (hasExactlyOneIssue || serviceOnly) ? page : nil
    }

    private func cachedPreferredPage() async -> WizardPage? {
        // Use last known system state from WizardStateMachine if available
        guard let cachedState = stateMachine.lastWizardSnapshot else { return nil }
        let adaptedIssues = cachedState.issues
        let adaptedState = cachedState.state
        return await preferredDetailPage(for: adaptedState, issues: adaptedIssues)
    }

    private func sanitizedIssues(from issues: [WizardIssue], for state: WizardSystemState)
        -> [WizardIssue] {
        guard shouldSuppressCommunicationIssues(for: state) else {
            return issues
        }

        let filtered = issues.filter { !isCommunicationIssue($0) }
        if filtered.count != issues.count {
            AppLogger.shared.log(
                "🔇 [Wizard] Suppressing \(issues.count - filtered.count) communication issue(s) because Kanata service is not running"
            )
        }
        return filtered
    }

    @MainActor
    private func applySystemStateResult(_ result: SystemStateResult) -> [WizardIssue] {
        let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
        systemState = result.state
        currentIssues = filteredIssues
        stateMachine.lastWizardSnapshot = WizardSnapshotRecord(
            state: result.state,
            issues: filteredIssues
        )
        stateMachine.markRefreshComplete()

        // Only auto-navigate if user hasn't been interacting with the wizard
        // This prevents jarring navigation away from a page after a fix completes
        let shouldAutoNavigate = !stateMachine.userInteractionMode

        if shouldNavigateToSummary(
            currentPage: stateMachine.currentPage,
            state: result.state,
            issues: filteredIssues
        ) {
            AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
            stateMachine.navigateToPage(.summary)
        } else if shouldAutoNavigate {
            Task {
                if let preferred = await preferredDetailPage(for: result.state, issues: filteredIssues),
                   stateMachine.currentPage != preferred {
                    AppLogger.shared.log("🔄 [Wizard] Deterministic routing to \(preferred) after refresh")
                    stateMachine.navigateToPage(preferred)
                }
            }
        }
        if stateMachine.currentPage == .summary, shouldAutoNavigate {
            Task { @MainActor in
                _ = await WizardSleep.ms(50) // 50ms
                autoNavigateIfSingleIssue(in: filteredIssues, state: result.state)
            }
        }

        AppLogger.shared.log(
            "🔍 [Wizard] State applied - Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
        )

        return filteredIssues
    }

    private func shouldSuppressCommunicationIssues(for state: WizardSystemState) -> Bool {
        if case .active = state {
            return false
        }
        return true
    }

    private func isCommunicationIssue(_ issue: WizardIssue) -> Bool {
        guard case let .component(component) = issue.identifier else {
            return false
        }

        switch component {
        case .kanataTCPServer,
             .communicationServerConfiguration,
             .communicationServerNotResponding,
             .tcpServerConfiguration,
             .tcpServerNotResponding:
            return true
        default:
            return false
        }
    }

    private func startKanataService() {
        Task {
            // Show safety confirmation before starting
            let shouldStart = await showStartConfirmation()

            if shouldStart {
                if systemState != .active {
                    let operation = WizardOperations.startService(kanataManager: kanataManager)

                    asyncOperationManager.execute(operation: operation) { (success: Bool) in
                        if success {
                            AppLogger.shared.log("✅ [Wizard] Kanata service started successfully")
                            toastManager.showSuccess("Kanata service started")
                            dismissAndRefreshMainScreen()
                        } else {
                            AppLogger.shared.log("❌ [Wizard] Failed to start Kanata service")
                            let failureMessage =
                                kanataManager.lastError
                                    ?? "Kanata service failed to stay running. Review /var/log/com.keypath.kanata.stderr.log for details."
                            toastManager.showError(failureMessage)
                        }
                    } onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [Wizard] Error starting Kanata service: \(error.localizedDescription)")
                        toastManager.showError("Start failed: \(error.localizedDescription)")
                    }
                } else {
                    // Service already running, dismiss wizard
                    dismissAndRefreshMainScreen()
                }
            }
        }
    }

    @State private var showingStartConfirmation = false
    @State private var startConfirmationResult: CheckedContinuation<Bool, Never>?
    @State private var showingCloseConfirmation = false

    private func handleCloseButtonTapped() {
        // INSTANT CLOSE: Cancel operations immediately and force close
        asyncOperationManager.cancelAllOperationsAsync()

        // Check for critical issues - but don't block the close
        let criticalIssues = currentIssues.filter { $0.severity == .critical }

        if criticalIssues.isEmpty {
            // Force immediate close - bypass any SwiftUI environment blocking
            forceInstantClose()
        } else {
            // Show confirmation but allow instant close anyway
            showingCloseConfirmation = true
        }
    }

    /// Force immediate wizard dismissal bypassing any potential SwiftUI blocking
    private func forceInstantClose() {
        dismissAndRefreshMainScreen()
    }

    /// Dismiss wizard and trigger main screen validation refresh
    private func dismissAndRefreshMainScreen() {
        // Cancel any Login Items polling before dismissing
        stopLoginItemsApprovalPolling()

        // Use DispatchQueue to ensure immediate execution
        DispatchQueue.main.async {
            // Trigger StartupValidator refresh before dismissing
            // This ensures main screen status updates after wizard changes
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
            AppLogger.shared.log("🔄 [Wizard] Triggered StartupValidator refresh before dismiss")

            dismiss()
        }
    }

    /// Performs cancellation and cleanup in the background after UI dismissal
    private func performBackgroundCleanup() {
        // Use structured concurrency; hop to MainActor for UI-safe cleanup without blocking
        Task { @MainActor [weak asyncOperationManager] in
            asyncOperationManager?.cancelAllOperationsAsync()
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            NSWorkspace.shared.openApplication(
                at: fallbackURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil
            )
        }
    }

    /// Start polling for Login Items approval status change
    private func startLoginItemsApprovalPolling() {
        stopLoginItemsApprovalPolling() // Cancel any existing polling

        AppLogger.shared.log("🔍 [LoginItems] Starting approval polling (3 min timeout)...")

        loginItemsPollingTask = Task { @MainActor in
            // Poll every 2 seconds for up to 3 minutes (90 attempts)
            let maxAttempts = 90
            for attempt in 1 ... maxAttempts {
                guard !Task.isCancelled else {
                    AppLogger.shared.log("🔍 [LoginItems] Polling cancelled")
                    return
                }

                // Check SMAppService status
                let state = await KanataDaemonManager.shared.refreshManagementState()
                // Only log every 10th attempt to reduce noise
                if attempt % 10 == 1 {
                    AppLogger.shared.log("🔍 [LoginItems] Poll #\(attempt)/\(maxAttempts): state=\(state)")
                }

                if state == .smappserviceActive {
                    // User approved! Dismiss dialog, refresh and show success
                    AppLogger.shared.log("✅ [LoginItems] Approval detected at poll #\(attempt)! Refreshing wizard state...")

                    await MainActor.run {
                        // Dismiss the dialog if it's still showing
                        showingBackgroundApprovalPrompt = false
                        toastManager.showSuccess("KeyPath approved in Login Items")
                    }

                    // Refresh the wizard state
                    refreshSystemState()

                    return
                }

                // Wait before next poll
                _ = await WizardSleep.seconds(2) // 2 seconds
            }

            AppLogger.shared.log("⏰ [LoginItems] Polling timed out after 3 minutes")
            toastManager.showInfo("Login Items check timed out. Click refresh to check again.")
        }
    }

    /// Stop polling for Login Items approval
    private func stopLoginItemsApprovalPolling() {
        loginItemsPollingTask?.cancel()
        loginItemsPollingTask = nil
    }

    /// Nuclear option: Force wizard closed immediately, bypass all operations and confirmations
    private func forciblyCloseWizard() {
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Starting nuclear shutdown at \(Date())")

        // Set force closing flag to prevent any new operations
        isForceClosing = true
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Force closing flag set - no new operations allowed")

        // Immediately clear operation state to stop UI spinners
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Clearing operation state...")
        Task { @MainActor in
            AppLogger.shared.log("🔴 [FORCE-CLOSE] MainActor task - clearing operations")
            asyncOperationManager.runningOperations.removeAll()
            asyncOperationManager.operationProgress.removeAll()
            isValidating = false // Stop validation state
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Operation state cleared")
            AppLogger.shared.flushBuffer()
        }

        // Cancel monitoring tasks
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Cancelling refresh task...")
        refreshTask?.cancel()
        stopLoginItemsApprovalPolling()
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Refresh and polling tasks cancelled")

        // Force immediate dismissal - no confirmation, no state checks, no waiting
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Calling dismiss()...")
        AppLogger.shared.flushBuffer() // Ensure logs are written before dismissal
        dismiss()
        AppLogger.shared.log("🔴 [FORCE-CLOSE] dismiss() called")

        // Clean up in background after UI is gone
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Starting background cleanup...")
        Task { @MainActor [weak asyncOperationManager] in
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Background cleanup task started")
            asyncOperationManager?.cancelAllOperationsAsync()
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Background cleanup completed")
            AppLogger.shared.flushBuffer()
        }

        AppLogger.shared.log("🔴 [FORCE-CLOSE] Nuclear shutdown completed")
        AppLogger.shared.flushBuffer()
    }

    private func showStartConfirmation() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                startConfirmationResult = continuation
                showingStartConfirmation = true
            }
        }
    }

    // MARK: - Operation Progress Helpers

    private func getCurrentOperationName() -> String {
        // Get the first running operation and provide a user-friendly name
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return "Processing..."
        }

        if operationId.contains("auto_fix_terminateConflictingProcesses") {
            return "Terminating Conflicting Processes"
        } else if operationId.contains("auto_fix_installMissingComponents") {
            return "Installing Missing Components"
        } else if operationId.contains("auto_fix_activateVHIDDeviceManager") {
            return "Activating Driver Extensions"
        } else if operationId.contains("auto_fix_installBundledKanata") {
            return "Installing Kanata binary"
        } else if operationId.contains("auto_fix_startKarabinerDaemon") {
            return "Starting System Daemon"
        } else if operationId.contains("auto_fix_restartVirtualHIDDaemon") {
            return "Restarting Virtual HID Daemon"
        } else if operationId.contains("auto_fix_installLaunchDaemonServices") {
            return "Installing Launch Services"
        } else if operationId.contains("auto_fix_createConfigDirectories") {
            return "Creating Configuration Directories"
        } else if operationId.contains("state_detection") {
            return "Detecting System State"
        } else if operationId.contains("start_service") {
            return "Starting Kanata Service"
        } else if operationId.contains("grant_permission") {
            return "Waiting for Permission Grant"
        } else if operationId.contains("auto_fix_restartUnhealthyServices") {
            return "Restarting Failing Services"
        } else {
            return "Processing Operation"
        }
    }

    private func getCurrentOperationProgress() -> Double {
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return 0.0
        }
        return asyncOperationManager.getProgress(operationId)
    }

    private func isCurrentOperationIndeterminate() -> Bool {
        // Most operations provide progress, but some like permission grants are indeterminate
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return true
        }

        return operationId.contains("grant_permission") || operationId.contains("state_detection")
    }

    /// Get detailed error message for specific auto-fix failures
    private func getDetailedErrorMessage(for action: AutoFixAction, actionDescription _: String)
        async -> String {
        AppLogger.shared.log("🔍 [ErrorMessage] getDetailedErrorMessage called for action: \(action)")

        var message = AutoFixActionDescriptions.errorMessage(for: action)

        // Enrich daemon-related errors with a succinct diagnosis
        if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
            let detail = await kanataManager.getVirtualHIDBreakageSummary()
            if !detail.isEmpty {
                message += "\n\n" + detail
            }
        }

        AppLogger.shared.log("🔍 [ErrorMessage] Returning message: \(message)")
        return message
    }

    // MARK: - Keyboard Navigation

    /// Navigate to the previous page using keyboard left arrow
    private func navigateToPreviousPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage), idx > 0 else {
            return
        }
        let previousPage = sequence[idx - 1]
        stateMachine.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Keyboard] Navigated to previous page: \(previousPage.displayName)")
    }

    /// Navigate to the next page using keyboard right arrow
    private func navigateToNextPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage),
              idx < sequence.count - 1
        else { return }
        let nextPage = sequence[idx + 1]
        stateMachine.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Keyboard] Navigated to next page: \(nextPage.displayName)")
    }

    // MARK: - Computed Properties

    private func getBuildTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        // Use compile time if available, otherwise current time
        return formatter.string(from: Date())
    }

    /// Quick summary to surface state when a fix times out
    private func describeServiceState() async -> String {
        let state = await KanataDaemonManager.shared.refreshManagementState()
        let vhidRunning = await VHIDDeviceManager().detectRunning()
        return "VHID running=\(vhidRunning ? "yes" : "no"); services=\(state.description)"
    }
}

// MARK: - Extracted Components

// KeyboardNavigationModifier -> Components/KeyboardNavigationModifier.swift
// WizardOperations.stateDetection -> Core/WizardOperationsUIExtension.swift
// AutoFixActionDescriptions -> Core/AutoFixActionDescriptions.swift

// MARK: - Focus Ring Suppression Helper

extension InstallationWizardView {
    /// Recursively disable focus rings in all subviews
    private func disableFocusRings(in view: NSView) {
        view.focusRingType = .none
        for subview in view.subviews {
            disableFocusRings(in: subview)
        }
    }
}
