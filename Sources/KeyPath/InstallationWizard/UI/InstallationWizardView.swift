import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager

    // New architecture components
    @StateObject private var stateManager = WizardStateManager()
    @StateObject private var autoFixer = WizardAutoFixerManager()
    @StateObject private var stateInterpreter = WizardStateInterpreter()
    @StateObject private var navigationCoordinator = WizardNavigationCoordinator()
    @StateObject private var asyncOperationManager = WizardAsyncOperationManager()
    @StateObject private var toastManager = WizardToastManager()

    // UI state
    @State private var isInitializing = true
    @State private var systemState: WizardSystemState = .initializing
    @State private var currentIssues: [WizardIssue] = []

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
                    }
                }
                .overlay {
                    if asyncOperationManager.hasRunningOperations {
                        operationProgressOverlay()
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
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.title3) // Smaller close button
                    .foregroundColor(shouldBlockClose ? .gray : .secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(shouldBlockClose)
                    .accessibilityLabel("Close setup wizard")
                }
                .accessibilityHint(
                    shouldBlockClose
                        ? "Setup must be completed before closing" : "Close the KeyPath setup wizard")
            }

            PageDotsIndicator(currentPage: navigationCoordinator.currentPage) { page in
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
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
                case .inputMonitoring:
                    WizardInputMonitoringPage(
                        systemState: systemState,
                        issues: currentIssues.filter { $0.category == .permissions },
                        onRefresh: refreshState,
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
                        onRefresh: refreshState,
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
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
                case .kanataComponents:
                    WizardKanataComponentsPage(
                        issues: currentIssues,
                        isFixing: asyncOperationManager.hasRunningOperations,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
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
            // Minimal overlay for all operations - just the gear icon
            WizardOperationProgress(
                operationName: operationName,
                progress: getCurrentOperationProgress(),
                isIndeterminate: isCurrentOperationIndeterminate()
            )
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
        autoFixer.configure(kanataManager: kanataManager)

        Task {
            await performInitialStateCheck()
        }
    }

    private func performInitialStateCheck() async {
        AppLogger.shared.log("🔍 [NewWizard] Performing initial state check")

        let operation = WizardOperations.stateDetection(stateManager: stateManager)

        await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
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
        // Monitor for state changes every 3 seconds
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // Skip state detection if async operations are running to avoid conflicts
            guard !asyncOperationManager.hasRunningOperations else {
                continue
            }

            // Note: Removed auto-fix check that was preventing navigation to permission pages

            let operation = WizardOperations.stateDetection(stateManager: stateManager)

            await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
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
        Task {
            AppLogger.shared.log("🔍 [NewWizard] Auto-fix started")

            // Find issues that can be auto-fixed
            let autoFixableIssues = currentIssues.compactMap(\.autoFixAction)

            for action in autoFixableIssues {
                let operation = WizardOperations.autoFix(action: action, autoFixer: autoFixer)
                let actionDescription = getAutoFixActionDescription(action)

                await asyncOperationManager.execute(operation: operation) { (success: Bool) in
                    AppLogger.shared.log(
                        "🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")

                    // Show toast notification
                    if success {
                        Task { @MainActor in
                            toastManager.showSuccess("\(actionDescription) completed successfully")
                        }
                    } else {
                        Task { @MainActor in
                            let errorMessage = getDetailedErrorMessage(for: action, actionDescription: actionDescription)
                            toastManager.showError(errorMessage)
                        }
                    }
                }
            }

            // Refresh state after auto-fix attempts
            await refreshState()
        }
    }

    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
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

                await asyncOperationManager.execute(
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
                                // Small delay to let filesystem operations settle (especially after admin operations)
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                await refreshState()
                                continuation.resume(returning: success)
                            }
                        } else {
                            Task { @MainActor in
                                toastManager.showError("Failed to \(actionDescription.lowercased())")
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
        switch action {
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
        case .installViaBrew:
            "Install packages via Homebrew"
        case .repairVHIDDaemonServices:
            "Repair VHID LaunchDaemon services"
        case .synchronizeConfigPaths:
            "Fix config path mismatch between KeyPath and Kanata"
        case .restartUnhealthyServices:
            "Restart failing system services"
        }
    }

    private func refreshState() async {
        AppLogger.shared.log("🔍 [NewWizard] Refreshing system state with cache clear")

        // Clear any cached state that might be stale
        PermissionService.shared.clearCache()

        let operation = WizardOperations.stateDetection(stateManager: stateManager)

        await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
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

                    await asyncOperationManager.execute(operation: operation) { (success: Bool) in
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
    private func getDetailedErrorMessage(for action: AutoFixAction, actionDescription: String) -> String {
        switch action {
        case .installLaunchDaemonServices:
            return "Failed to install system services. Check that you provided admin password and try again."
        case .activateVHIDDeviceManager:
            return "Failed to activate driver extensions. Please manually approve in System Settings > General > Login Items & Extensions."
        case .installViaBrew:
            return "Failed to install packages via Homebrew. Check your internet connection or install manually."
        case .startKarabinerDaemon:
            return "Failed to start system daemon. Check System Settings > Privacy & Security > System Extensions."
        case .createConfigDirectories:
            return "Failed to create configuration directories. Check file system permissions."
        case .restartVirtualHIDDaemon:
            return "Failed to restart Virtual HID daemon. Try manually in System Settings > Privacy & Security."
        case .restartUnhealthyServices:
            return "Failed to fix system services. Check that you provided admin password and all required permissions are granted."
        default:
            return "Failed to \(actionDescription.lowercased()). Check logs for details and try again."
        }
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

    private var shouldBlockClose: Bool {
        // Block close if there are critical conflicts
        currentIssues.contains { $0.severity == .critical }
    }

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
    private var statusChecker: SystemStatusChecker?

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

    func configure(kanataManager: KanataManager) {
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with KanataManager")
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
