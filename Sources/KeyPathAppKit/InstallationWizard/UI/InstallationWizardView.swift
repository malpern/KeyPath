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

    // Optional initial page to navigate to
    var initialPage: WizardPage?

    // New architecture components
    @StateObject private var stateManager = WizardStateManager()
    @StateObject private var autoFixer = WizardAutoFixerManager()
    private let stateInterpreter = WizardStateInterpreter()
    @StateObject private var navigationCoordinator = WizardNavigationCoordinator()
    @State private var asyncOperationManager = WizardAsyncOperationManager()
    @State private var toastManager = WizardToastManager()

    // InstallerEngine façade for unified installer operations
    private let installerEngine = InstallerEngine()
    private var privilegeBroker: PrivilegeBroker {
        PrivilegeBroker()
    }

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

    // Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        ZStack {
            // Dark mode-aware background for cross-fade effect
            WizardDesign.Colors.wizardBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Always show page content - no preflight view
                pageContent()
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        // Don't show overlay during validation - summary page has its own gear
                        if asyncOperationManager.hasRunningOperations, !isValidating {
                            operationProgressOverlay()
                                .allowsHitTesting(false) // Don't block X button interaction
                        }
                    }
            }
            .frame(
                width: (navigationCoordinator.currentPage == .summary)
                    ? WizardDesign.Layout.pageWidth * CGFloat(0.5) // Match list width; only height changes
                    : WizardDesign.Layout.pageWidth,
                height: nil
            )
            .frame(maxHeight: (navigationCoordinator.currentPage == .summary) ? 720 : .infinity) // Grow up to cap, then scroll
            .fixedSize(horizontal: true, vertical: false) // Allow vertical growth; keep width fixed
            .animation(.easeInOut(duration: 0.25), value: isValidating)
            // Remove animation on frame changes to prevent window movement
            .background(WizardDesign.Colors.wizardBackground) // Simple solid background, no visual effect
        }
        .withToasts(toastManager)
        .environmentObject(navigationCoordinator)
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
                navigationCoordinator.customSequence = showAllSummaryItems ? nil : navSequence
            }
        }
        // Global Close button overlay for all detail pages
        .overlay(alignment: .topTrailing) {
            if navigationCoordinator.currentPage != .summary {
                CloseButton()
                    .environmentObject(navigationCoordinator)
                    .padding(.top, 8 + 4) // Extra padding from edge
                    .padding(.trailing, 8 + 4) // Extra padding from edge
            }
        }
        .onAppear {
            hasKeyboardFocus = true
            setupWizard()
        }
        .onChange(of: asyncOperationManager.hasRunningOperations) { _, newValue in
            // When overlays disappear, reclaim focus for ESC key
            if !newValue {
                hasKeyboardFocus = true
            }
        }
        // Keep navigation sequence in sync with summary filter state
        .onChange(of: showAllSummaryItems) { _, showAll in
            navigationCoordinator.customSequence = showAll ? nil : navSequence
        }
        .onChange(of: navSequence) { _, newSeq in
            if !showAllSummaryItems {
                navigationCoordinator.customSequence = newSeq
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
        .alert("Approve KeyPath Background Item", isPresented: $showingBackgroundApprovalPrompt) {
            Button("Open Login Items") {
                showingBackgroundApprovalPrompt = false
                openLoginItemsSettings()
            }
            Button("Later", role: .cancel) {
                showingBackgroundApprovalPrompt = false
            }
        } message: {
            Text(
                "macOS blocked the helper because KeyPath isn't yet approved in System Settings → General → Login Items & Extensions. "
                    + "Open Login Items and enable KeyPath under Background Items to allow the helper to run."
            )
        }
    }

    // MARK: - UI Components

    // Header removed per design update; pages present their own centered titles.

    @ViewBuilder
    private func pageContent() -> some View {
        ZStack {
            switch navigationCoordinator.currentPage {
            case .summary:
                WizardSummaryPage(
                    systemState: systemState,
                    issues: currentIssues,
                    stateInterpreter: stateInterpreter,
                    onStartService: startKanataService,
                    onDismiss: { dismissAndRefreshMainScreen() },
                    onNavigateToPage: { page in
                        navigationCoordinator.navigateToPage(page)
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
                    isFixing: asyncOperationManager.hasRunningOperations,
                    onRefresh: { refreshState() },
                    kanataManager: kanataManager
                )
            case .inputMonitoring:
                WizardInputMonitoringPage(
                    systemState: systemState,
                    issues: currentIssues.filter { $0.category == .permissions },
                    allIssues: currentIssues,
                    stateInterpreter: stateInterpreter,
                    onRefresh: { refreshState() },
                    onNavigateToPage: { page in
                        navigationCoordinator.navigateToPage(page)
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
                    onRefresh: { refreshState() },
                    onNavigateToPage: { page in
                        navigationCoordinator.navigateToPage(page)
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
                    isFixing: asyncOperationManager.hasRunningOperations,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshState() },
                    kanataManager: kanataManager
                )
            case .kanataComponents:
                WizardKanataComponentsPage(
                    systemState: systemState,
                    issues: currentIssues,
                    isFixing: asyncOperationManager.hasRunningOperations,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshState() },
                    kanataManager: kanataManager
                )
            case .helper:
                WizardHelperPage(
                    systemState: systemState,
                    issues: currentIssues,
                    isFixing: asyncOperationManager.hasRunningOperations,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshState() },
                    kanataManager: kanataManager
                )
                .environmentObject(toastManager)
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
                    onRefresh: { refreshState() },
                    toastManager: toastManager
                )
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: navigationCoordinator.currentPage)
    }

    @ViewBuilder
    private func initializingOverlay() -> some View {
        // Ultra minimal - just system progress indicator
        ProgressView()
            .scaleEffect(1.0)
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

    private func setupWizard() {
        AppLogger.shared.log("🔍 [Wizard] Setting up wizard with new architecture")

        // Always reset navigation state for fresh run
        navigationCoordinator.navigationEngine.resetNavigationState()

        // Configure state manager
        stateManager.configure(kanataManager: kanataManager)
        autoFixer.configure(kanataManager: kanataManager, toastManager: toastManager)

        // Show summary page immediately with validation state
        // Determine initial page based on cached system snapshot (if available)
        let preferredPage = cachedPreferredPage()
        if let preferredPage, initialPage == nil {
            AppLogger.shared.log("🔍 [Wizard] Preferring cached page: \(preferredPage)")
            navigationCoordinator.navigateToPage(preferredPage)
        } else if let initialPage {
            AppLogger.shared.log("🔍 [Wizard] Navigating to initial page override: \(initialPage)")
            navigationCoordinator.navigateToPage(initialPage)
        } else {
            navigationCoordinator.navigateToPage(.summary)
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
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay

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
            stateManager: stateManager,
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
            stateManager.lastWizardSnapshot = WizardSnapshotRecord(
                state: result.state, issues: filteredIssues
            )
            // Start at summary page - no auto navigation
            // navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

            // Transition to results immediately when validation completes
            Task { @MainActor in
                // Mark validation as complete - this will transition gear to final icon
                withAnimation(.easeInOut(duration: 0.25)) {
                    isValidating = false
                }
            }

            AppLogger.shared.log(
                "🔍 [Wizard] Initial setup - State: \(result.state), Issues: \(filteredIssues.count), Target Page: \(navigationCoordinator.currentPage)"
            )
            AppLogger.shared.log(
                "🔍 [Wizard] Issue details: \(filteredIssues.map { "\($0.category)-\($0.title)" })")

            Task { @MainActor in
                if shouldNavigateToSummary(
                    currentPage: navigationCoordinator.currentPage,
                    state: result.state,
                    issues: filteredIssues
                ) {
                    AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
                    navigationCoordinator.navigateToPage(.summary)
                } else if let preferred = preferredDetailPage(for: result.state, issues: filteredIssues),
                          navigationCoordinator.currentPage != preferred {
                    AppLogger.shared.log("🔍 [Wizard] Deterministic routing to \(preferred) (single blocker)")
                    navigationCoordinator.navigateToPage(preferred)
                } else if navigationCoordinator.currentPage == .summary {
                    // Wait a tick for navSequence to be updated by WizardSystemStatusOverview's onChange handlers
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    autoNavigateIfSingleIssue(in: filteredIssues, state: result.state)
                }
            }

            // Targeted auto-navigation: if helper isn’t installed, go to Helper page first
            let recommended = navigationCoordinator.navigationEngine
                .determineCurrentPage(for: result.state, issues: filteredIssues)
            if recommended == .helper, navigationCoordinator.currentPage == .summary {
                AppLogger.shared.log("🔍 [Wizard] Auto-navigating to Helper page (helper missing)")
                navigationCoordinator.navigateToPage(.helper)
            }
        }
    }

    private func monitorSystemState() async {
        AppLogger.shared.log("🟡 [MONITOR] System state monitoring started with 60s interval")

        // Smart monitoring: Only poll when needed, much less frequently
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds instead of 10

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
        navigationCoordinator.currentPage == .summary
    }

    /// Perform targeted state check based on current page
    private func performSmartStateCheck(retryAllowed: Bool = true) async {
        // Check if force closing is in progress
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Smart state check blocked - force closing in progress")
            return
        }

        switch navigationCoordinator.currentPage {
        case .summary:
            // Full check only for summary page
            let operation = WizardOperations.stateDetection(
                stateManager: stateManager,
                progressCallback: { _ in }
            )
            asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
                let oldState = systemState
                let oldPage = navigationCoordinator.currentPage

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
                    "🔍 [Navigation] Current: \(navigationCoordinator.currentPage), Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
                )

                // No auto-navigation - stay on current page
                // navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

                Task { @MainActor in
                    if shouldNavigateToSummary(
                        currentPage: navigationCoordinator.currentPage,
                        state: result.state,
                        issues: filteredIssues
                    ) {
                        AppLogger.shared.log(
                            "🟢 [Wizard] Healthy system detected during monitor; routing to summary")
                        navigationCoordinator.navigateToPage(.summary)
                    }
                }

                if oldState != systemState || oldPage != navigationCoordinator.currentPage {
                    AppLogger.shared.log(
                        "🔍 [Wizard] State changed: \(oldState) -> \(systemState), page: \(oldPage) -> \(navigationCoordinator.currentPage)"
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

        // Use InstallerEngine to repair all issues at once
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

            let broker = privilegeBroker
            let report = await installerEngine.run(intent: .repair, using: broker)

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
            refreshState()

            // Post-repair health check for VHID-related issues
            if currentIssues.contains(where: { issue in
                if let action = issue.autoFixAction {
                    return action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon
                }
                return false
            }) {
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // allow services to settle
                    let latestResult = await stateManager.detectCurrentState()
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
                        let detail = kanataManager.getVirtualHIDBreakageSummary()
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

    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        // Single-flight guard for Fix buttons
        if inFlightFixActions.contains(action) {
            await MainActor.run {
                toastManager.showInfo("Fix already running…", duration: 3.0)
            }
            return false
        }
        if fixInFlight {
            await MainActor.run {
                toastManager.showInfo("Another fix is already running…", duration: 3.0)
            }
            return false
        }
        inFlightFixActions.insert(action)
        currentFixAction = action
        defer {
            inFlightFixActions.remove(action)
            currentFixAction = nil
        }
        await MainActor.run { fixInFlight = true }
        defer { Task { @MainActor in fixInFlight = false } }

        // IMMEDIATE crash-proof logging for ACTUAL Fix button
        Swift.print(
            "*** IMMEDIATE DEBUG *** ACTUAL Fix button clicked for action: \(action) at \(Date())")
        try? "*** IMMEDIATE DEBUG *** ACTUAL Fix button clicked for action: \(action) at \(Date())\n"
            .write(
                to: URL(fileURLWithPath: NSHomeDirectory() + "/actual-fix-button-debug.txt"),
                atomically: true, encoding: .utf8
            )

        AppLogger.shared.log("🔧 [Wizard] Auto-fix for specific action: \(action)")

        let broker = privilegeBroker

        // Short-circuit service installs when Login Items approval is pending
        if action == .installLaunchDaemonServices || action == .restartUnhealthyServices,
           await KanataDaemonManager.shared.refreshManagementState() == .smappservicePending {
            await MainActor.run {
                toastManager.showError(
                    "KeyPath background service needs approval in System Settings → Login Items. Enable ‘KeyPath’ then click Fix again.",
                    duration: 7.0
                )
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
        let report: InstallerReport
        do {
            report = try await runWithTimeout(seconds: timeoutSeconds) {
                await installerEngine.runSingleAction(action, using: broker)
            }
        } catch {
            let stateSummary = await describeServiceState()
            await MainActor.run {
                toastManager.showError(
                    "Fix timed out after \(Int(timeoutSeconds))s. \(stateSummary)", duration: 7.0
                )
            }
            AppLogger.shared.log("⚠️ [Wizard] Auto-fix timed out for action: \(action)")
            return false
        }

        let actionDescription = getAutoFixActionDescription(action)

        let smState = await KanataDaemonManager.shared.refreshManagementState()

        let deferToastActions: Set<AutoFixAction> = [
            .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
            .installLaunchDaemonServices
        ]
        let deferSuccessToast = report.success && deferToastActions.contains(action)
        var successToastPending = false

        await MainActor.run {
            if report.success {
                if deferSuccessToast {
                    successToastPending = true
                    toastManager.showInfo("Verifying…", duration: 3.0)
                } else {
                    toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                }
            } else {
                var errorMessage = report.failureReason
                    ?? getDetailedErrorMessage(for: action, actionDescription: actionDescription)

                if smState == .smappservicePending {
                    errorMessage =
                        "KeyPath background service needs approval in System Settings → Login Items. Enable ‘KeyPath’ and click Fix again."
                }

                toastManager.showError(errorMessage, duration: 7.0)
            }
        }

        // Log report details
        AppLogger.shared.log("🔧 [Wizard] Single-action fix completed - success: \(report.success)")
        for (index, result) in report.executedRecipes.enumerated() {
            AppLogger.shared.log(
                "🔧 [Wizard] Recipe \(index + 1): \(result.recipeID) - \(result.success ? "success" : "failed")"
            )
        }

        // Refresh system state after auto-fix
        Task {
            // Shorter delay - we have warm-up window to handle startup
            try? await Task.sleep(nanoseconds: 1_000_000_000) // allow services to start
            refreshState()

            // Notify StartupValidator to refresh main screen status
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
            AppLogger.shared.log(
                "🔄 [Wizard] Triggered StartupValidator refresh after successful auto-fix")

            // Schedule a follow-up health check; if still red, show a diagnostic error toast
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // allow additional settle time
                let latestResult = await stateManager.detectCurrentState()
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

                    if karabinerStatus == .completed {
                        if successToastPending {
                            await MainActor.run {
                                toastManager.showSuccess(
                                    "\(actionDescription) completed successfully", duration: 5.0
                                )
                            }
                        }
                    } else {
                        let detail = kanataManager.getVirtualHIDBreakageSummary()
                        AppLogger.shared.log(
                            "❌ [Wizard] Post-fix health check failed; will show diagnostic toast")
                        await MainActor.run {
                            if smStatePost == .smappservicePending {
                                toastManager.showError(
                                    "KeyPath background service needs approval in System Settings → Login Items. Enable ‘KeyPath’ and click Fix again.",
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

        return report.success
    }

    /// Get user-friendly description for auto-fix actions
    private func getAutoFixActionDescription(_ action: AutoFixAction) -> String {
        AppLogger.shared.log("🔍 [ActionDescription] getAutoFixActionDescription called for: \(action)")

        let description =
            switch action {
            case .installPrivilegedHelper:
                "Install privileged helper for system operations"
            case .reinstallPrivilegedHelper:
                "Reinstall privileged helper to restore functionality"
            case .terminateConflictingProcesses:
                "Terminate conflicting processes"
            case .startKarabinerDaemon:
                "Start Karabiner daemon"
            case .restartVirtualHIDDaemon:
                "Fix VirtualHID connection issues"
            case .installMissingComponents:
                "Install missing components"
            case .createConfigDirectories:
                "Create configuration directories"
            case .activateVHIDDeviceManager:
                "Activate VirtualHID Device Manager"
            case .installLaunchDaemonServices:
                "Install LaunchDaemon services"
            case .adoptOrphanedProcess:
                "Connect existing Kanata to KeyPath management"
            case .replaceOrphanedProcess:
                "Replace orphaned process with managed service"
            case .installBundledKanata:
                "Install Kanata binary"
            case .repairVHIDDaemonServices:
                "Repair VHID LaunchDaemon services"
            case .synchronizeConfigPaths:
                "Fix config path mismatch between KeyPath and Kanata"
            case .restartUnhealthyServices:
                "Restart failing system services"
            case .installLogRotation:
                "Install log rotation to keep logs under 10MB"
            case .replaceKanataWithBundled:
                "Replace kanata with Developer ID signed version"
            case .enableTCPServer:
                "Enable TCP server"
            case .setupTCPAuthentication:
                "Setup TCP authentication for secure communication"
            case .regenerateCommServiceConfiguration:
                "Update TCP service configuration"
            case .restartCommServer:
                "Restart Service with Authentication"
            case .fixDriverVersionMismatch:
                "Fix Karabiner driver version (v6 → v5)"
            case .installCorrectVHIDDriver:
                "Install Karabiner VirtualHID driver"
            }

        AppLogger.shared.log("🔍 [ActionDescription] Returning description: \(description)")
        return description
    }

    private func refreshState() {
        // Check if force closing is in progress
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Refresh state blocked - force closing in progress")
            return
        }

        let now = Date()
        if let last = lastRefreshAt, now.timeIntervalSince(last) < 0.3 {
            AppLogger.shared.log("🔍 [Wizard] Refresh skipped (debounced)")
            return
        }
        lastRefreshAt = now

        AppLogger.shared.log("🔍 [Wizard] Refreshing system state (using cache if available)")

        // Don't clear cache - let the 2-second TTL handle freshness
        // Only clear cache when we actually need fresh data (e.g., after auto-fix)

        // Cancel any previous refresh task to prevent race conditions
        refreshTask?.cancel()

        // Use async operation manager for non-blocking refresh
        let operation = WizardOperations.stateDetection(
            stateManager: stateManager,
            progressCallback: { _ in }
        )

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
            systemState = result.state
            currentIssues = filteredIssues
            stateManager.lastWizardSnapshot = WizardSnapshotRecord(
                state: result.state, issues: filteredIssues
            )
            Task { @MainActor in
                if shouldNavigateToSummary(
                    currentPage: navigationCoordinator.currentPage,
                    state: result.state,
                    issues: filteredIssues
                ) {
                    AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
                    navigationCoordinator.navigateToPage(.summary)
                } else if let preferred = preferredDetailPage(for: result.state, issues: filteredIssues),
                          navigationCoordinator.currentPage != preferred {
                    AppLogger.shared.log("🔄 [Wizard] Deterministic routing to \(preferred) after refresh")
                    navigationCoordinator.navigateToPage(preferred)
                } else if navigationCoordinator.currentPage == .summary {
                    // Wait a tick for navSequence to be updated by WizardSystemStatusOverview's onChange handlers
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    autoNavigateIfSingleIssue(in: filteredIssues, state: result.state)
                }
            }
            AppLogger.shared.log(
                "🔍 [Wizard] Refresh complete - Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
            )
        }
    }

    @MainActor
    private func autoNavigateIfSingleIssue(in issues: [WizardIssue], state _: WizardSystemState) {
        AppLogger.shared.log("🔍 [AutoNav] ===== autoNavigateIfSingleIssue CALLED =====")
        AppLogger.shared.log("🔍 [AutoNav] Current page: \(navigationCoordinator.currentPage)")
        AppLogger.shared.log("🔍 [AutoNav] Issues count: \(issues.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence count: \(navSequence.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence pages: \(navSequence.map(\.displayName))")

        guard navigationCoordinator.currentPage == .summary else {
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
        navigationCoordinator.navigateToPage(targetPage)
        AppLogger.shared.log("🔍 [AutoNav] Navigation command sent")
    }

    private func preferredDetailPage(for state: WizardSystemState, issues: [WizardIssue])
        -> WizardPage? {
        let page = navigationCoordinator.navigationEngine.determineCurrentPage(
            for: state, issues: issues
        )
        guard page != .summary else { return nil }

        let hasExactlyOneIssue = issues.count == 1
        let serviceOnly = issues.isEmpty && page == .service
        return (hasExactlyOneIssue || serviceOnly) ? page : nil
    }

    private func cachedPreferredPage() -> WizardPage? {
        // Use last known system state from WizardStateManager if available
        guard let cachedState = stateManager.lastWizardSnapshot else { return nil }
        let adaptedIssues = cachedState.issues
        let adaptedState = cachedState.state
        return preferredDetailPage(for: adaptedState, issues: adaptedIssues)
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

        // Cancel monitoring task
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Cancelling refresh task...")
        refreshTask?.cancel()
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Refresh task cancelled")

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
    private func getDetailedErrorMessage(for action: AutoFixAction, actionDescription: String)
        -> String {
        AppLogger.shared.log("🔍 [ErrorMessage] getDetailedErrorMessage called for action: \(action)")
        AppLogger.shared.log("🔍 [ErrorMessage] Action description: \(actionDescription)")

        var message =
            switch action {
            case .installLaunchDaemonServices:
                "Failed to install system services. Check that you provided admin password and try again."
            case .activateVHIDDeviceManager:
                "Failed to activate driver extensions. Please manually approve in System Settings > General > Login Items & Extensions."
            case .installBundledKanata:
                "Failed to install Kanata binary. Check admin permissions and try again."
            case .startKarabinerDaemon:
                "Failed to start system daemon."
            case .createConfigDirectories:
                "Failed to create configuration directories. Check file system permissions."
            case .restartVirtualHIDDaemon:
                "Failed to restart Virtual HID daemon."
            case .restartUnhealthyServices:
                "Failed to restart system services. This usually means:\n\n• Admin password was not provided when prompted\n"
                    + "• Missing services could not be installed\n• System permission denied for service restart\n\n"
                    + "Try the Fix button again and provide admin password when prompted."
            default:
                "Failed to \(actionDescription.lowercased()). Check logs for details and try again."
            }

        // Enrich daemon-related errors with a succinct diagnosis
        if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
            let detail = kanataManager.getVirtualHIDBreakageSummary()
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
        guard navigationCoordinator.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: navigationCoordinator.currentPage), idx > 0 else {
            return
        }
        let previousPage = sequence[idx - 1]
        navigationCoordinator.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Keyboard] Navigated to previous page: \(previousPage.displayName)")
    }

    /// Navigate to the next page using keyboard right arrow
    private func navigateToNextPage() {
        guard navigationCoordinator.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: navigationCoordinator.currentPage),
              idx < sequence.count - 1
        else { return }
        let nextPage = sequence[idx + 1]
        navigationCoordinator.navigateToPage(nextPage)
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

// MARK: - Timeout helper for auto-fix actions (file-private)

private struct AutoFixTimeoutError: Error {}

private func runWithTimeout<T: Sendable>(
    seconds: Double,
    operation: @Sendable @escaping () async -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AutoFixTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Auto-Fixer Manager

@MainActor
class WizardAutoFixerManager: ObservableObject {
    private(set) var autoFixer: WizardAutoFixer?

    func configure(kanataManager: RuntimeCoordinator, toastManager _: WizardToastManager) {
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with RuntimeCoordinator")
        // FIXED: Removed toastManager parameter (was unused, created Core→UI architecture violation)
        autoFixer = WizardAutoFixer(kanataManager: kanataManager)
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuration complete")
    }

    func canAutoFix(_ action: AutoFixAction) -> Bool {
        autoFixer?.canAutoFix(action) ?? false
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixerManager] performAutoFix called for action: \(action)")
        guard let autoFixer else {
            AppLogger.shared.log("❌ [AutoFixerManager] Internal autoFixer is nil - returning false")
            return false
        }
        AppLogger.shared.log("🔧 [AutoFixerManager] Delegating to internal autoFixer")
        return await autoFixer.performAutoFix(action)
    }
}

// MARK: - Keyboard Navigation Support

/// ViewModifier that adds keyboard navigation support with macOS version compatibility
struct KeyboardNavigationModifier: ViewModifier {
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void
    let onEscape: (() -> Void)?

    init(
        onLeftArrow: @escaping () -> Void, onRightArrow: @escaping () -> Void,
        onEscape: (() -> Void)? = nil
    ) {
        self.onLeftArrow = onLeftArrow
        self.onRightArrow = onRightArrow
        self.onEscape = onEscape
    }

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.leftArrow) {
                    onLeftArrow()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    onRightArrow()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onEscape?()
                    return .handled
                }
                .focusable(true)
        } else {
            // For macOS 13.0, keyboard navigation isn't available
            content
        }
    }
}

// MARK: - UI-Layer WizardOperations Extension

// This extends WizardOperations (from Core) with UI-specific factory methods that need UI types

extension WizardOperations {
    /// State detection operation (UI-layer only - uses WizardStateManager from UI target)
    static func stateDetection(
        stateManager: WizardStateManager,
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) -> AsyncOperation<SystemStateResult> {
        AsyncOperation<SystemStateResult>(
            id: "state_detection",
            name: "System State Detection"
        ) { operationProgressCallback in
            // Forward progress from SystemValidator to the operation callback
            let result = await stateManager.detectCurrentState { progress in
                progressCallback(progress)
                operationProgressCallback(progress)
            }
            progressCallback(1.0)
            operationProgressCallback(1.0)
            return result
        }
    }
}

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
