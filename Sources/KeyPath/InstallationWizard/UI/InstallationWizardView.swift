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

    // UI state
    @State private var isInitializing = true
    @State private var systemState: WizardSystemState = .initializing
    @State private var currentIssues: [WizardIssue] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header with page dots - always visible with fixed height
            wizardHeader()
                .frame(height: 120) // Fixed height for header

            // Page Content takes remaining space
            pageContent()
                .frame(maxWidth: .infinity)
                .overlay {
                    if isInitializing {
                        initializingOverlay()
                    }
                }
        }
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
        .background(VisualEffectBackground())
        .onAppear {
            setupWizard()
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
    }

    // MARK: - UI Components

    @ViewBuilder
    private func wizardHeader() -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)

                Text("KeyPath Setup")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundColor(shouldBlockClose ? .gray : .secondary)
                .keyboardShortcut(.cancelAction)
                .disabled(shouldBlockClose)
                .accessibilityLabel("Close setup wizard")
                .accessibilityHint(shouldBlockClose ? "Setup must be completed before closing" : "Close the KeyPath setup wizard")
            }

            PageDotsIndicator(currentPage: navigationCoordinator.currentPage) { page in
                navigationCoordinator.navigateToPage(page)
                AppLogger.shared.log("🔍 [NewWizard] User manually navigated to \(page) - entering user interaction mode")
            }
        }
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
                        onStartService: startKanataService,
                        onDismiss: { dismiss() },
                        onNavigateToPage: { page in
                            navigationCoordinator.navigateToPage(page)
                        }
                    )
                case .conflicts:
                    WizardConflictsPage(
                        issues: currentIssues.filter { $0.category == .conflicts },
                        isFixing: asyncOperationManager.hasRunningOperations,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
                case .inputMonitoring:
                    WizardPermissionsPage(
                        permissionType: .inputMonitoring,
                        issues: currentIssues.filter { $0.category == .permissions },
                        kanataManager: kanataManager
                    )
                case .accessibility:
                    WizardPermissionsPage(
                        permissionType: .accessibility,
                        issues: currentIssues.filter { $0.category == .permissions },
                        kanataManager: kanataManager
                    )
                case .daemon:
                    WizardDaemonPage(
                        issues: currentIssues.filter { $0.category == .daemon },
                        isFixing: asyncOperationManager.hasRunningOperations,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
                case .backgroundServices:
                    WizardBackgroundServicesPage(
                        issues: currentIssues.filter { $0.category == .backgroundServices },
                        isFixing: asyncOperationManager.hasRunningOperations,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState,
                        kanataManager: kanataManager
                    )
                case .installation:
                    WizardInstallationPage(
                        issues: currentIssues.filter { $0.category == .installation },
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
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .opacity(0.9)

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Checking system status...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .transition(.opacity)
    }

    // MARK: - State Management

    private func setupWizard() {
        AppLogger.shared.log("🔍 [NewWizard] Setting up wizard with new architecture")

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
            navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

            withAnimation {
                isInitializing = false
            }

            AppLogger.shared.log("🔍 [NewWizard] Initial setup - State: \(result.state), Issues: \(result.issues.count), Target Page: \(navigationCoordinator.currentPage)")
            AppLogger.shared.log("🔍 [NewWizard] Issue details: \(result.issues.map { "\($0.category)-\($0.title)" })")
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

            let operation = WizardOperations.stateDetection(stateManager: stateManager)

            await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
                let oldState = systemState
                let oldPage = navigationCoordinator.currentPage

                systemState = result.state
                currentIssues = result.issues

                AppLogger.shared.log("🔍 [Navigation] Current: \(navigationCoordinator.currentPage), Issues: \(result.issues.map { "\($0.category)-\($0.title)" })")

                // Use navigation coordinator for auto-navigation logic
                navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

                if oldState != systemState || oldPage != navigationCoordinator.currentPage {
                    AppLogger.shared.log("🔍 [NewWizard] State changed: \(oldState) -> \(systemState), page: \(oldPage) -> \(navigationCoordinator.currentPage)")
                }
            }
        }
    }

    // MARK: - Actions

    private func performAutoFix() {
        Task {
            AppLogger.shared.log("🔍 [NewWizard] Auto-fix started")

            // Find issues that can be auto-fixed
            let autoFixableIssues = currentIssues.compactMap { $0.autoFixAction }

            for action in autoFixableIssues {
                let operation = WizardOperations.autoFix(action: action, autoFixer: autoFixer)

                await asyncOperationManager.execute(operation: operation) { (success: Bool) in
                    AppLogger.shared.log("🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")
                }
            }

            // Refresh state after auto-fix attempts
            await refreshState()
        }
    }

    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [NewWizard] Auto-fix for specific action: \(action)")

        let operation = WizardOperations.autoFix(action: action, autoFixer: autoFixer)

        return await withCheckedContinuation { continuation in
            Task {
                await asyncOperationManager.execute(
                    operation: operation,
                    onSuccess: { success in
                        AppLogger.shared.log("🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")
                        continuation.resume(returning: success)
                    },
                    onFailure: { error in
                        AppLogger.shared.log("❌ [NewWizard] Auto-fix \(action) error: \(error.localizedDescription)")
                        continuation.resume(returning: false)
                    }
                )
            }
        }
    }

    private func refreshState() async {
        AppLogger.shared.log("🔍 [NewWizard] Refreshing system state")

        let operation = WizardOperations.stateDetection(stateManager: stateManager)

        await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            systemState = result.state
            currentIssues = result.issues
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
                        AppLogger.shared.log("❌ [NewWizard] Error starting Kanata service: \(error.localizedDescription)")
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
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                startConfirmationResult = continuation
                showingStartConfirmation = true
            }
        }
    }

    // MARK: - Computed Properties

    private var shouldBlockClose: Bool {
        // Block close if there are critical conflicts
        currentIssues.contains { $0.severity == .critical }
    }
}

// MARK: - State Manager

@MainActor
class WizardStateManager: ObservableObject {
    private var detector: SystemStateDetector?

    func configure(kanataManager: KanataManager) {
        detector = SystemStateDetector(kanataManager: kanataManager)
    }

    func detectCurrentState() async -> SystemStateResult {
        guard let detector = detector else {
            return SystemStateResult(
                state: .initializing,
                issues: [],
                autoFixActions: [],
                detectionTimestamp: Date()
            )
        }
        return await detector.detectCurrentState()
    }
}

// MARK: - Auto-Fixer Manager

@MainActor
class WizardAutoFixerManager: ObservableObject {
    private var autoFixer: WizardAutoFixer?

    func configure(kanataManager: KanataManager) {
        autoFixer = WizardAutoFixer(kanataManager: kanataManager)
    }

    func canAutoFix(_ action: AutoFixAction) -> Bool {
        autoFixer?.canAutoFix(action) ?? false
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        guard let autoFixer = autoFixer else { return false }
        return await autoFixer.performAutoFix(action)
    }
}

// MARK: - Start Confirmation Dialog

struct StartConfirmationDialog: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on background tap - this is an important confirmation
                }

            // Dialog content
            VStack(spacing: 0) {
                // Header with icon
                VStack(spacing: 16) {
                    // App icon
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.gradient)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "keyboard")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.white)
                        }

                    Text("Ready to Start KeyPath")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("KeyPath will now start the keyboard remapping service.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)

                // Emergency stop section
                VStack(spacing: 20) {
                    Divider()
                        .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.title3)
                                .foregroundColor(.orange)

                            Text("Emergency Stop")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }

                        Text("If the keyboard becomes unresponsive, press:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Visual keyboard keys
                        HStack(spacing: 12) {
                            KeyCapView(text: "⌃", label: "Ctrl")

                            Text("+")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            KeyCapView(text: "␣", label: "Space")

                            Text("+")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            KeyCapView(text: "⎋", label: "Esc")
                        }

                        Text("(Press all three keys at the same time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()

                        Text("This will immediately stop the remapping service and restore normal keyboard function.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 24)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onConfirm()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Start KeyPath")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.blue.gradient)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onCancel()
                        }
                    }) {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .frame(width: 420)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
}

// MARK: - Key Cap View

struct KeyCapView: View {
    let text: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .foregroundColor(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .frame(width: 50, height: 44)
                .overlay(
                    Text(text)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}
