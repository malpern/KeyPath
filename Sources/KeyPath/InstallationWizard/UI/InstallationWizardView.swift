import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager

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
        .onAppear {
            setupWizard()
        }
        // Add keyboard navigation support for left/right arrow keys (macOS 14.0+)
        .modifier(
            KeyboardNavigationModifier(
                onLeftArrow: navigateToPreviousPage,
                onRightArrow: navigateToNextPage
            )
        )
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
                        handleCloseButtonTapped()
                    }
                    .buttonStyle(.plain)
                    .font(.title3) // Smaller close button
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close setup wizard")
                    .disabled(false) // Always allow closing
                }
                .accessibilityHint("Close the KeyPath setup wizard")
            }

            PageDotsIndicator(currentPage: navigationCoordinator.currentPage) { page in
                // Don't allow manual navigation if operations are running
                guard !asyncOperationManager.hasRunningOperations else { return }
                
                navigationCoordinator.navigateToPage(page)
                AppLogger.shared.log(
                    "🔍 [NewWizard] User manually navigated to \(page) - entering user interaction mode")
            }
            .fixedSize(horizontal: false, vertical: true) // Prevent dots from expanding
        }
        .fixedSize(horizontal: false, vertical: true) // Keep header at fixed height
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func pageContent() -> some View {
        ZStack {
            Group {
                switch navigationCoordinator.currentPage {
                case .summary:
                    WizardSummaryPage(
                        systemState: systemState,
                        issues: currentIssues,
                        stateInterpreter: stateInterpreter,
                        kanataManager: kanataManager,
                        onStartService: startKanataService,
                        onDismiss: { dismiss() },
                        onNavigateToPage: { page in
                            navigationCoordinator.navigateToPage(page)
                        }
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
                        onRefresh: { refreshState() },
                        onNavigateToPage: { page in
                            navigationCoordinator.navigateToPage(page)
                        },
                        onDismiss: {
                            dismiss()
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
                            dismiss()
                        },
                        kanataManager: kanataManager
                    )
                case .karabinerComponents:
                    WizardKarabinerComponentsPage(
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
                case .tcpServer:
                    WizardTCPServerPage()
                case .service:
                    WizardKanataServicePage(
                        kanataManager: kanataManager
                    )
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
        }
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
        AppLogger.shared.log("🔍 [NewWizard] Setting up wizard with new architecture")

        // Always reset navigation state for fresh run
        navigationCoordinator.navigationEngine.resetNavigationState()

        // Configure state manager
        stateManager.configure(kanataManager: kanataManager)
        autoFixer.configure(kanataManager: kanataManager, toastManager: toastManager)

        // Make initial check optional and cancellable
        Task {
            // Small delay to let UI render first
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Only run if user hasn't closed wizard
            guard !Task.isCancelled else { return }
            await performInitialStateCheck()
        }
    }

    private func performInitialStateCheck() async {
        // Check if user has already closed wizard
        guard !Task.isCancelled else { 
            AppLogger.shared.log("🔍 [NewWizard] Initial state check cancelled - wizard closing")
            return 
        }
        
        AppLogger.shared.log("🔍 [NewWizard] Performing initial state check")

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
                "🔍 [NewWizard] Initial setup - State: \(result.state), Issues: \(result.issues.count), Target Page: \(navigationCoordinator.currentPage)"
            )
            AppLogger.shared.log(
                "🔍 [NewWizard] Issue details: \(result.issues.map { "\($0.category)-\($0.title)" })")
        }
    }

    private func monitorSystemState() async {
        // Monitor for state changes every 10 seconds (reduced from 3s)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            // Skip state detection if async operations are running to avoid conflicts
            guard !asyncOperationManager.hasRunningOperations else {
                continue
            }

            // Note: Removed auto-fix check that was preventing navigation to permission pages

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
                        "🔍 [NewWizard] State changed: \(oldState) -> \(systemState), page: \(oldPage) -> \(navigationCoordinator.currentPage)"
                    )
                }
            }
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
                    "🔍 [NewWizard] *** FIX BUTTON CLICKED *** Auto-fix started - BUILD VERSION CHECK")
                Swift.print("*** CRASH-PROOF *** AppLogger.log called successfully")
                AppLogger.shared.log("🔍 [NewWizard] TIMESTAMP: \(Date())")
                AppLogger.shared.log("🔍 [NewWizard] Current issues: \(currentIssues.count) total")

                // Log each current issue for debugging
                for (index, issue) in currentIssues.enumerated() {
                    if let autoFixAction = issue.autoFixAction {
                        AppLogger.shared.log(
                            "🔍 [NewWizard] Issue \(index): \(issue.identifier) -> AutoFix: \(autoFixAction)")
                    } else {
                        AppLogger.shared.log(
                            "🔍 [NewWizard] Issue \(index): \(issue.identifier) -> AutoFix: nil")
                    }
                }

                // Find issues that can be auto-fixed
                let autoFixableIssues = currentIssues.compactMap(\.autoFixAction)
                AppLogger.shared.log("🔍 [NewWizard] Auto-fixable actions found: \(autoFixableIssues)")

                for action in autoFixableIssues {
                    let operation = WizardOperations.autoFix(action: action, autoFixer: autoFixer)
                    let actionDescription = getAutoFixActionDescription(action)

                    asyncOperationManager.execute(operation: operation) { (success: Bool) in
                        AppLogger.shared.log(
                            "🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")

                        // Show toast notification
                        if success {
                            Task { @MainActor in
                                toastManager.showSuccess("\(actionDescription) completed successfully")
                            }
                        } else {
                            Task { @MainActor in
                                AppLogger.shared.log("❌ [NewWizard] Auto-fix FAILED for action: \(action)")
                                AppLogger.shared.log("❌ [NewWizard] Action description: \(actionDescription)")
                                let errorMessage = getDetailedErrorMessage(
                                    for: action, actionDescription: actionDescription
                                )
                                AppLogger.shared.log("❌ [NewWizard] Generated error message: \(errorMessage)")
                                toastManager.showError(errorMessage)
                            }
                        }
                    }
                }

                // Clear cache and refresh state after auto-fix attempts
                PermissionService.shared.clearCache()
                if let statusChecker = stateManager.statusChecker {
                    statusChecker.clearCache()
                }
                await refreshState()

                AppLogger.shared.log("🔍 [NewWizard] *** PERFORMAUTOFIX COMPLETED SUCCESSFULLY ***")
                Swift.print("*** CRASH-PROOF *** performAutoFix completed successfully")

            } catch {
                AppLogger.shared.log("❌ [NewWizard] *** EXCEPTION IN PERFORMAUTOFIX *** \(error)")
                Swift.print("*** CRASH-PROOF *** Exception in performAutoFix: \(error)")
                try? "*** EXCEPTION *** performAutoFix failed: \(error)\n".write(
                    to: URL(fileURLWithPath: NSHomeDirectory() + "/fix-button-debug.txt"), atomically: false,
                    encoding: .utf8
                )
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

        AppLogger.shared.log("🔧 [NewWizard] Auto-fix for specific action: \(action)")

        // Immediately mark auto-fix as running to prevent monitoring loop interference
        let operationId = "auto_fix_\(String(describing: action))"
        await MainActor.run {
            asyncOperationManager.runningOperations.insert(operationId)
        }

        let operation = WizardOperations.autoFix(action: action, autoFixer: autoFixer)
        let actionDescription = getAutoFixActionDescription(action)

        return await withCheckedContinuation { continuation in
            Task {
                // Remove our manual operation ID since execute() will handle it properly
                await MainActor.run {
                    asyncOperationManager.runningOperations.remove(operationId)
                }

                asyncOperationManager.execute(
                    operation: operation,
                    onSuccess: { success in
                        AppLogger.shared.log(
                            "🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")

                        // Show toast notification
                        if success {
                            Task { @MainActor in
                                toastManager.showSuccess("\(actionDescription) completed successfully")
                            }
                            // Refresh system state after successful auto-fix, then return success
                            Task {
                                // Shorter delay - we have warm-up window to handle startup
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                                await refreshState()
                                continuation.resume(returning: success)
                            }
                        } else {
                            // Clear permission cache on failure - might be stale permission status
                            PermissionService.shared.clearCache()
                            Task { @MainActor in
                                let errorMessage = getDetailedErrorMessage(
                                    for: action, actionDescription: actionDescription
                                )
                                toastManager.showError(errorMessage)
                            }
                            continuation.resume(returning: success)
                        }
                    },
                    onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [NewWizard] Auto-fix \(action) error: \(error.localizedDescription)")

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
        case .installViaBrew:
            "Install packages via Homebrew"
        case .repairVHIDDaemonServices:
            "Repair VHID LaunchDaemon services"
        case .synchronizeConfigPaths:
            "Fix config path mismatch between KeyPath and Kanata"
        case .restartUnhealthyServices:
            "Restart failing system services"
        }

        AppLogger.shared.log("🔍 [ActionDescription] Returning description: \(description)")
        return description
    }

    private func refreshState() {
        AppLogger.shared.log("🔍 [NewWizard] Refreshing system state (using cache if available)")

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
                "🔍 [NewWizard] Refresh complete - Issues: \(result.issues.map { "\($0.category)-\($0.title)" })"
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
                            AppLogger.shared.log("✅ [NewWizard] Kanata service started successfully")
                            dismiss()
                        } else {
                            AppLogger.shared.log("❌ [NewWizard] Failed to start Kanata service")
                        }
                    } onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [NewWizard] Error starting Kanata service: \(error.localizedDescription)")
                    }
                } else {
                    // Service already running, dismiss wizard
                    dismiss()
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
        // Use DispatchQueue to ensure immediate execution
        DispatchQueue.main.async {
            dismiss()
        }
    }
    
    /// Performs cancellation and cleanup in the background after UI dismissal
    private func performBackgroundCleanup() {
        // Use Task.detached to avoid any main thread scheduling overhead
        Task.detached { [weak asyncOperationManager] in
            // This runs completely in background, no main thread blocking
            asyncOperationManager?.cancelAllOperationsAsync()
        }
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
        } else if operationId.contains("auto_fix_installViaBrew") {
            return "Installing via Homebrew"
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

        let message = switch action {
        case .installLaunchDaemonServices:
            "Failed to install system services. Check that you provided admin password and try again."
        case .activateVHIDDeviceManager:
            "Failed to activate driver extensions. Please manually approve in System Settings > General > Login Items & Extensions."
        case .installViaBrew:
            "Failed to install packages via Homebrew. Check your internet connection or install manually."
        case .startKarabinerDaemon:
            "Failed to start system daemon. Check System Settings > Privacy & Security > System Extensions."
        case .createConfigDirectories:
            "Failed to create configuration directories. Check file system permissions."
        case .restartVirtualHIDDaemon:
            "Failed to restart Virtual HID daemon. Try manually in System Settings > Privacy & Security."
        case .restartUnhealthyServices:
            "Failed to restart system services. This usually means:\n\n• Admin password was not provided when prompted\n" +
            "• Missing services could not be installed\n• System permission denied for service restart\n\n" +
            "Try the Fix button again and provide admin password when prompted."
        default:
            "Failed to \(actionDescription.lowercased()). Check logs for details and try again."
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

// MARK: - State Manager

@MainActor
class WizardStateManager: ObservableObject {
    var statusChecker: SystemStatusChecker?

    func configure(kanataManager: KanataManager) {
        statusChecker = SystemStatusChecker(kanataManager: kanataManager)
    }

    func detectCurrentState() async -> SystemStateResult {
        guard let statusChecker else {
            return SystemStateResult(
                state: .initializing,
                issues: [],
                autoFixActions: [],
                detectionTimestamp: Date()
            )
        }
        return await statusChecker.detectCurrentState()
    }
}

// MARK: - Auto-Fixer Manager

@MainActor
class WizardAutoFixerManager: ObservableObject {
    private var autoFixer: WizardAutoFixer?

    func configure(kanataManager: KanataManager, toastManager: WizardToastManager) {
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with KanataManager")
        autoFixer = WizardAutoFixer(kanataManager: kanataManager, toastManager: toastManager)
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
                .focusable(true)
        } else {
            // For macOS 13.0, keyboard navigation isn't available
            content
        }
    }
}
