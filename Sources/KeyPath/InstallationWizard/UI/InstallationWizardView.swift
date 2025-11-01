import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataViewModel: KanataViewModel

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
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

    // UI state
    @State private var isInitializing = true
    @State private var systemState: WizardSystemState = .initializing
    @State private var currentIssues: [WizardIssue] = []

    // Task management for race condition prevention
    @State private var refreshTask: Task<Void, Never>?
    @State private var isForceClosing = false // Prevent new operations after nuclear close

    // Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with page dots - always visible with fixed height
            wizardHeader()
                .frame(height: 90) // Reduced height for header

            // Page Content takes remaining space
            pageContent()
                .frame(maxWidth: .infinity)
                .overlay {
                    if isInitializing {
                        initializingOverlay()
                            .allowsHitTesting(false) // Don't block X button interaction
                    }
                }
                .overlay {
                    if asyncOperationManager.hasRunningOperations {
                        operationProgressOverlay()
                            .allowsHitTesting(false) // Don't block X button interaction
                    }
                }
        }
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
        .background(VisualEffectBackground())
        .withToasts(toastManager)
        .environmentObject(navigationCoordinator)
        .focused($hasKeyboardFocus) // Enable focus for reliable ESC key handling
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
        } message: {
            let criticalCount = currentIssues.filter { $0.severity == .critical }.count
            Text(
                "There \(criticalCount == 1 ? "is" : "are") \(criticalCount) critical \(criticalCount == 1 ? "issue" : "issues") " +
                    "that may prevent KeyPath from working properly. Are you sure you want to close the setup wizard?"
            )
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private func wizardHeader() -> some View {
        VStack(spacing: 8) { // Reduced spacing
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 24)) // Smaller icon
                        .foregroundColor(.blue)

                    Text("KeyPath Setup")
                        .font(.title3) // Smaller title
                        .fontWeight(.bold)
                }

                Spacer()

                // Build timestamp and close button
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Build: \(getBuildTimestamp())")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("✕") {
                        // NUCLEAR OPTION: Immediate close, bypass everything
                        AppLogger.shared.log("🔴 [X-BUTTON] CLICKED at \(Date())")
                        AppLogger.shared.log("🔴 [X-BUTTON] Starting nuclear close sequence")
                        AppLogger.shared.flushBuffer() // Force immediate write
                        forciblyCloseWizard()
                    }
                    .buttonStyle(.plain)
                    .font(.title3) // Smaller close button
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close setup wizard")
                    .disabled(false) // Always allow closing
                    .onAppear {
                        AppLogger.shared.log("🔴 [X-BUTTON] Button appeared - ready for clicks")
                        AppLogger.shared.flushBuffer()
                    }
                }
                .accessibilityHint("Close the KeyPath setup wizard")
            }

            PageDotsIndicator(currentPage: navigationCoordinator.currentPage) { page in
                // Don't allow manual navigation if operations are running
                guard !asyncOperationManager.hasRunningOperations else { return }

                navigationCoordinator.navigateToPage(page)
                AppLogger.shared.log(
                    "🔍 [Wizard] User manually navigated to \(page) - entering user interaction mode")
            }
            .fixedSize(horizontal: false, vertical: true) // Prevent dots from expanding
        }
        .fixedSize(horizontal: false, vertical: true) // Keep header at fixed height
        .padding()
        .background(AppGlassBackground(style: .headerStrong))
    }

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
                    isInitializing: isInitializing
                )
            case .fullDiskAccess:
                WizardFullDiskAccessPage()
            case .conflicts:
                WizardConflictsPage(
                    issues: currentIssues.filter { $0.category == .conflicts },
                    isFixing: asyncOperationManager.hasRunningOperations,
                    onAutoFix: performAutoFix,
                    onRefresh: { refreshState() },
                    kanataManager: kanataManager
                )
            case .inputMonitoring:
                WizardInputMonitoringPage(
                    systemState: systemState,
                    issues: currentIssues.filter { $0.category == .permissions },
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
            case .communication:
                WizardCommunicationPage(
                    onAutoFix: performAutoFix
                )
            case .service:
                WizardKanataServicePage(
                    systemState: systemState,
                    issues: currentIssues,
                    onRefresh: { refreshState() }
                )
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
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

        // If an initial page was specified, navigate to it
        if let initialPage {
            AppLogger.shared.log("🔍 [Wizard] Navigating to initial page: \(initialPage)")
            navigationCoordinator.navigateToPage(initialPage)
        }

        // Configure state manager
        stateManager.configure(kanataManager: kanataManager)
        autoFixer.configure(kanataManager: kanataManager, toastManager: toastManager)

        // Show UI immediately with minimal setup
        Task {
            // Instant UI rendering - no delay
            await MainActor.run {
                isInitializing = false // Show wizard UI immediately
                // Set basic default state so UI can render
                systemState = .initializing
                currentIssues = []
                AppLogger.shared.log("🚀 [Wizard] UI shown immediately, heavy checks deferred")
            }

            // Defer heavy system detection to background
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for heavy checks

            guard !Task.isCancelled else { return }
            await performInitialStateCheck()
        }
    }

    private func performInitialStateCheck() async {
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

        let operation = WizardOperations.stateDetection(stateManager: stateManager)

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            systemState = result.state
            currentIssues = result.issues
            // Start at summary page - no auto navigation
            // navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

            withAnimation {
                isInitializing = false
            }

            AppLogger.shared.log(
                "🔍 [Wizard] Initial setup - State: \(result.state), Issues: \(result.issues.count), Target Page: \(navigationCoordinator.currentPage)"
            )
            AppLogger.shared.log(
                "🔍 [Wizard] Issue details: \(result.issues.map { "\($0.category)-\($0.title)" })")

            // Targeted auto-navigation: if helper isn’t installed, go to Helper page first
            let recommended = navigationCoordinator.navigationEngine
                .determineCurrentPage(for: result.state, issues: result.issues)
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
    private func performSmartStateCheck() async {
        // Check if force closing is in progress
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Smart state check blocked - force closing in progress")
            return
        }

        switch navigationCoordinator.currentPage {
        case .summary:
            // Full check only for summary page
            let operation = WizardOperations.stateDetection(stateManager: stateManager)
            asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
                let oldState = systemState
                let oldPage = navigationCoordinator.currentPage

                systemState = result.state
                currentIssues = result.issues

                AppLogger.shared.log(
                    "🔍 [Navigation] Current: \(navigationCoordinator.currentPage), Issues: \(result.issues.map { "\($0.category)-\($0.title)" })"
                )

                // No auto-navigation - stay on current page
                // navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

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

    // MARK: - Actions

    private func performAutoFix() {
        // IMMEDIATE crash-proof logging with multiple output methods
        Swift.print("*** IMMEDIATE DEBUG *** Fix button clicked at \(Date())")
        try? "*** IMMEDIATE DEBUG *** Fix button clicked at \(Date())\n".write(
            to: URL(fileURLWithPath: NSHomeDirectory() + "/fix-button-debug.txt"), atomically: true,
            encoding: .utf8
        )

        Task {
            do {
                AppLogger.shared.log(
                    "🔍 [Wizard] *** FIX BUTTON CLICKED *** Auto-fix started - BUILD VERSION CHECK")
                Swift.print("*** CRASH-PROOF *** AppLogger.log called successfully")
                AppLogger.shared.log("🔍 [Wizard] TIMESTAMP: \(Date())")
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

                // Find issues that can be auto-fixed
                let autoFixableIssues = currentIssues.compactMap(\.autoFixAction)
                AppLogger.shared.log("🔍 [Wizard] Auto-fixable actions found: \(autoFixableIssues)")

                for action in autoFixableIssues {
                    guard let actualAutoFixer = autoFixer.autoFixer else {
                        AppLogger.shared.log("❌ [Wizard] AutoFixer not configured - skipping auto-fix")
                        continue
                    }
                    // Start Fix Session for VHID-related actions to make the path explicit
                    let fixSession = UUID().uuidString
                    if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
                        AppLogger.shared.log("🧭 [FIX-VHID \(fixSession)] START bulk action: \(action)")
                    }

                    let operation = WizardOperations.autoFix(action: action, autoFixer: actualAutoFixer)
                    let actionDescription = getAutoFixActionDescription(action)

                    asyncOperationManager.execute(operation: operation) { (success: Bool) in
                        AppLogger.shared.log(
                            "🔧 [Wizard] Auto-fix \(action): \(success ? "success" : "failed")")

                        // Show toast notification
                        if success {
                            Task { @MainActor in
                                toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                            }
                            // Follow-up: if this was a daemon action, re-check and emit diagnostic toast if still unhealthy
                            if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
                                        systemState: systemState,
                                        issues: currentIssues
                                    )
                                    AppLogger.shared.log("🔍 [Wizard] Post-fix (bulk) health check: karabinerStatus=\(karabinerStatus)")
                                    if karabinerStatus != .completed {
                                        let detail = kanataManager.getVirtualHIDBreakageSummary()
                                        AppLogger.shared.log("❌ [Wizard] Post-fix (bulk) failed; showing diagnostic toast")
                                        await MainActor.run {
                                            toastManager.showError("Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0)
                                        }
                                    }
                                }
                            }
                        } else {
                            Task { @MainActor in
                                AppLogger.shared.log("❌ [Wizard] Auto-fix FAILED for action: \(action)")
                                AppLogger.shared.log("❌ [Wizard] Action description: \(actionDescription)")
                                let errorMessage = getDetailedErrorMessage(
                                    for: action, actionDescription: actionDescription
                                )
                                AppLogger.shared.log("❌ [Wizard] Generated error message: \(errorMessage)")
                                toastManager.showError(errorMessage, duration: 7.0)
                            }
                        }

                        if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
                            let diag = kanataManager.getVirtualHIDBreakageSummary()
                            AppLogger.shared.log("🧭 [FIX-VHID \(fixSession)] END bulk action: \(action) success=\(success)\n\(diag)")
                        }
                    }
                }

                // Refresh state after auto-fix attempts
                refreshState()

                AppLogger.shared.log("🔍 [Wizard] *** PERFORMAUTOFIX COMPLETED SUCCESSFULLY ***")
                Swift.print("*** CRASH-PROOF *** performAutoFix completed successfully")
            }
        }
    }

    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        // IMMEDIATE crash-proof logging for ACTUAL Fix button
        Swift.print(
            "*** IMMEDIATE DEBUG *** ACTUAL Fix button clicked for action: \(action) at \(Date())")
        try? "*** IMMEDIATE DEBUG *** ACTUAL Fix button clicked for action: \(action) at \(Date())\n"
            .write(
                to: URL(fileURLWithPath: NSHomeDirectory() + "/actual-fix-button-debug.txt"),
                atomically: true, encoding: .utf8
            )

        AppLogger.shared.log("🔧 [Wizard] Auto-fix for specific action: \(action)")

        // Immediately mark auto-fix as running to prevent monitoring loop interference
        let operationId = "auto_fix_\(String(describing: action))"
        _ = await MainActor.run {
            asyncOperationManager.runningOperations.insert(operationId)
        }

        guard let actualAutoFixer = autoFixer.autoFixer else {
            AppLogger.shared.log("❌ [Wizard] AutoFixer not configured for single auto-fix")
            return false
        }
        let operation = WizardOperations.autoFix(action: action, autoFixer: actualAutoFixer)
        let actionDescription = getAutoFixActionDescription(action)

        return await withCheckedContinuation { continuation in
            Task {
                // Remove our manual operation ID since execute() will handle it properly
                _ = await MainActor.run {
                    asyncOperationManager.runningOperations.remove(operationId)
                }

                asyncOperationManager.execute(
                    operation: operation,
                    onSuccess: { success in
                        AppLogger.shared.log(
                            "🔧 [Wizard] Auto-fix \(action): \(success ? "success" : "failed")")

                        // Show toast notification
                        if success {
                            Task { @MainActor in
                                toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                            }
                            // Refresh system state after successful auto-fix, then return success
                            Task {
                                // Shorter delay - we have warm-up window to handle startup
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                                refreshState()

                                // Notify StartupValidator to refresh main screen status
                                NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
                                AppLogger.shared.log("🔄 [Wizard] Triggered StartupValidator refresh after successful auto-fix")

                                // Schedule a follow-up health check; if still red, show a diagnostic error toast
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds to allow state to settle
                                    let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
                                        systemState: systemState,
                                        issues: currentIssues
                                    )
                                    AppLogger.shared.log("🔍 [Wizard] Post-fix health check: karabinerStatus=\(karabinerStatus)")
                                    if (action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon), karabinerStatus != .completed {
                                        let detail = kanataManager.getVirtualHIDBreakageSummary()
                                        AppLogger.shared.log("❌ [Wizard] Post-fix health check failed; will show diagnostic toast")
                                        await MainActor.run {
                                            toastManager.showError("Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0)
                                        }
                                    }
                                }

                                continuation.resume(returning: success)
                            }
                        } else {
                            // Clear permission cache on failure - might be stale permission status
                            // Oracle handles caching automatically
                            Task { @MainActor in
                                let errorMessage = getDetailedErrorMessage(
                                    for: action, actionDescription: actionDescription
                                )
                                toastManager.showError(errorMessage, duration: 7.0)
                            }
                            continuation.resume(returning: success)
                        }
                    },
                    onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [Wizard] Auto-fix \(action) error: \(error.localizedDescription)")

                        // Show error toast
                        Task { @MainActor in
                            toastManager.showError("Error: \(error.localizedDescription)")
                        }

                        continuation.resume(returning: false)
                    }
                )
            }
        }
    }

    /// Get user-friendly description for auto-fix actions
    private func getAutoFixActionDescription(_ action: AutoFixAction) -> String {
        AppLogger.shared.log("🔍 [ActionDescription] getAutoFixActionDescription called for: \(action)")

        let description = switch action {
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

        AppLogger.shared.log("🔍 [Wizard] Refreshing system state (using cache if available)")

        // Don't clear cache - let the 2-second TTL handle freshness
        // Only clear cache when we actually need fresh data (e.g., after auto-fix)

        // Cancel any previous refresh task to prevent race conditions
        refreshTask?.cancel()

        // Use async operation manager for non-blocking refresh
        let operation = WizardOperations.stateDetection(stateManager: stateManager)

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            systemState = result.state
            currentIssues = result.issues
            AppLogger.shared.log(
                "🔍 [Wizard] Refresh complete - Issues: \(result.issues.map { "\($0.category)-\($0.title)" })"
            )
        }
    }

    private func startKanataService() {
        Task {
            // Show safety confirmation before starting
            let shouldStart = await showStartConfirmation()

            if shouldStart {
                if !kanataManager.isRunning {
                    let operation = WizardOperations.startService(kanataManager: kanataManager)

                    asyncOperationManager.execute(operation: operation) { (success: Bool) in
                        if success {
                            AppLogger.shared.log("✅ [Wizard] Kanata service started successfully")
                            dismissAndRefreshMainScreen()
                        } else {
                            AppLogger.shared.log("❌ [Wizard] Failed to start Kanata service")
                        }
                    } onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [Wizard] Error starting Kanata service: \(error.localizedDescription)")
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
        // Use Task.detached to avoid any main thread scheduling overhead
        Task { @MainActor [weak asyncOperationManager] in
            asyncOperationManager?.cancelAllOperationsAsync()
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
            isInitializing = false // Stop any initializing spinners
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

        var message = switch action {
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
            "Failed to restart system services. This usually means:\n\n• Admin password was not provided when prompted\n" +
                "• Missing services could not be installed\n• System permission denied for service restart\n\n" +
                "Try the Fix button again and provide admin password when prompted."
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
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex > 0
        else { return }

        let previousPage = allPages[currentIndex - 1]
        navigationCoordinator.navigateToPage(previousPage)

        AppLogger.shared.log("⬅️ [Keyboard] Navigated to previous page: \(previousPage.displayName)")
    }

    /// Navigate to the next page using keyboard right arrow
    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }

        let nextPage = allPages[currentIndex + 1]
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
}

// MARK: - Auto-Fixer Manager

@MainActor
class WizardAutoFixerManager: ObservableObject {
    private(set) var autoFixer: WizardAutoFixer?

    func configure(kanataManager: KanataManager, toastManager _: WizardToastManager) {
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with KanataManager")
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

    init(onLeftArrow: @escaping () -> Void, onRightArrow: @escaping () -> Void, onEscape: (() -> Void)? = nil) {
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
    static func stateDetection(stateManager: WizardStateManager) -> AsyncOperation<SystemStateResult> {
        AsyncOperation<SystemStateResult>(
            id: "state_detection",
            name: "System State Detection"
        ) { progressCallback in
            progressCallback(0.1)
            let result = await stateManager.detectCurrentState()
            progressCallback(1.0)
            return result
        }
    }
}
