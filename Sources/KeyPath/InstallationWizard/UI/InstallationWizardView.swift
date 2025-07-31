import SwiftUI

/// Main installation wizard view using clean architecture
struct InstallationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    
    // New architecture components
    @StateObject private var stateManager = WizardStateManager()
    @StateObject private var autoFixer = WizardAutoFixerManager()
    private let navigationEngine = WizardNavigationEngine()
    
    // UI state
    @State private var currentPage: WizardPage = .summary
    @State private var isInitializing = true
    @State private var systemState: WizardSystemState = .initializing
    @State private var currentIssues: [WizardIssue] = []
    @State private var isPerformingAutoFix = false
    
    // Auto-navigation control
    @State private var lastPageChangeTime = Date()
    @State private var userInteractionMode = false
    private let autoNavigationGracePeriod: TimeInterval = 10.0 // 10 seconds
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with page dots
            wizardHeader()
            
            // Page Content
            pageContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 600)
        .background(VisualEffectBackground())
        .onAppear {
            setupWizard()
        }
        .overlay {
            if isInitializing {
                initializingOverlay()
            }
        }
        .task {
            // Monitor state changes
            await monitorSystemState()
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
            }
            
            PageDotsIndicator(currentPage: currentPage) { page in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage = page
                    lastPageChangeTime = Date()
                    userInteractionMode = true
                    AppLogger.shared.log("🔍 [NewWizard] User manually navigated to \(page) - entering user interaction mode")
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func pageContent() -> some View {
        ZStack {
            Group {
                switch currentPage {
                case .summary:
                    WizardSummaryPage(
                        systemState: systemState,
                        issues: currentIssues,
                        onStartService: startKanataService,
                        onDismiss: { dismiss() }
                    )
                case .conflicts:
                    WizardConflictsPage(
                        issues: currentIssues.filter { $0.category == .conflicts },
                        isFixing: isPerformingAutoFix,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState
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
                        isFixing: isPerformingAutoFix,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState
                    )
                case .installation:
                    WizardInstallationPage(
                        issues: currentIssues.filter { $0.category == .installation },
                        isFixing: isPerformingAutoFix,
                        onAutoFix: performAutoFix,
                        onRefresh: refreshState
                    )
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
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
        
        let result = await stateManager.detectCurrentState()
        
        await MainActor.run {
            systemState = result.state
            currentIssues = result.issues
            currentPage = navigationEngine.determineCurrentPage(for: result.state)
            lastPageChangeTime = Date()
            
            withAnimation {
                isInitializing = false
            }
            
            AppLogger.shared.log("🔍 [NewWizard] Initial state: \(result.state), \(result.issues.count) issues, page: \(currentPage)")
        }
    }
    
    private func monitorSystemState() async {
        // Monitor for state changes every 3 seconds
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            let result = await stateManager.detectCurrentState()
            
            await MainActor.run {
                let oldState = systemState
                let oldPage = currentPage
                
                systemState = result.state
                currentIssues = result.issues
                
                // Check if we're in user interaction grace period
                let timeSinceLastPageChange = Date().timeIntervalSince(lastPageChangeTime)
                let inGracePeriod = userInteractionMode && timeSinceLastPageChange < autoNavigationGracePeriod
                
                // Auto-navigate if needed, but with grace period and conflicts handling
                let targetPage = navigationEngine.determineCurrentPage(for: result.state)
                let shouldAutoNavigate = navigationEngine.createNavigationState(currentPage: currentPage, systemState: systemState).shouldAutoNavigate
                
                if targetPage != currentPage && shouldAutoNavigate {
                    // Never auto-navigate during grace period
                    if inGracePeriod {
                        AppLogger.shared.log("🔍 [NewWizard] Preventing auto-nav during grace period (\(String(format: "%.1f", timeSinceLastPageChange))s of \(autoNavigationGracePeriod)s)")
                    }
                    // Don't auto-navigate away from conflicts page if there are unresolved conflicts  
                    else if currentPage == .conflicts && currentIssues.contains(where: { $0.category == .conflicts }) {
                        AppLogger.shared.log("🔍 [NewWizard] Preventing auto-nav away from conflicts page - unresolved conflicts exist")
                    }
                    // Don't auto-navigate away from any action page where user might be interacting
                    else if [.conflicts, .daemon, .installation].contains(currentPage) && timeSinceLastPageChange < 5.0 {
                        AppLogger.shared.log("🔍 [NewWizard] Preventing auto-nav away from action page - recent page change")
                    }
                    else {
                        withAnimation {
                            currentPage = targetPage
                            lastPageChangeTime = Date()
                            userInteractionMode = false // Reset user interaction mode on auto-nav
                        }
                    }
                } else if inGracePeriod && timeSinceLastPageChange >= autoNavigationGracePeriod {
                    // Grace period expired, reset user interaction mode
                    userInteractionMode = false
                    AppLogger.shared.log("🔍 [NewWizard] Grace period expired - auto-navigation re-enabled")
                }
                
                if oldState != systemState || oldPage != currentPage {
                    AppLogger.shared.log("🔍 [NewWizard] State changed: \(oldState) -> \(systemState), page: \(oldPage) -> \(currentPage)")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func performAutoFix() {
        Task {
            await MainActor.run {
                isPerformingAutoFix = true
                userInteractionMode = true
                lastPageChangeTime = Date()
                AppLogger.shared.log("🔍 [NewWizard] Auto-fix started - entering user interaction mode")
            }
            
            // Find issues that can be auto-fixed
            let autoFixableIssues = currentIssues.compactMap { $0.autoFixAction }
            
            for action in autoFixableIssues {
                let success = await autoFixer.performAutoFix(action)
                AppLogger.shared.log("🔧 [NewWizard] Auto-fix \(action): \(success ? "success" : "failed")")
            }
            
            // Refresh state after auto-fix attempts
            await refreshState()
            
            await MainActor.run {
                isPerformingAutoFix = false
            }
        }
    }
    
    private func refreshState() async {
        AppLogger.shared.log("🔍 [NewWizard] Refreshing system state")
        
        let result = await stateManager.detectCurrentState()
        
        await MainActor.run {
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
                    await kanataManager.startKanataWithSafetyTimeout()
                    
                    // Wait a moment to ensure it starts properly
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
                
                // Dismiss the wizard
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
    
    private func showStartConfirmation() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Ready to Start KeyPath"
                alert.informativeText = """
                KeyPath will now start the keyboard remapping service.
                
                🔐 Emergency Stop: If keyboard becomes unresponsive, press:
                Left Control + Space + Escape (at the same time)
                
                This will immediately stop the remapping service and restore normal keyboard function.
                """
                alert.addButton(withTitle: "Start KeyPath")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .informational
                
                let response = alert.runModal()
                continuation.resume(returning: response == .alertFirstButtonReturn)
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