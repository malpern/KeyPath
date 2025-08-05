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
        .frame(height: 120)  // Fixed height for header

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
        .accessibilityHint(
          shouldBlockClose
            ? "Setup must be completed before closing" : "Close the KeyPath setup wizard")
      }

      PageDotsIndicator(currentPage: navigationCoordinator.currentPage) { page in
        navigationCoordinator.navigateToPage(page)
        AppLogger.shared.log(
          "🔍 [NewWizard] User manually navigated to \(page) - entering user interaction mode")
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

  @ViewBuilder
  private func operationProgressOverlay() -> some View {
    ZStack {
      Color.black.opacity(0.4)

      WizardOperationProgress(
        operationName: getCurrentOperationName(),
        progress: getCurrentOperationProgress(),
        isIndeterminate: isCurrentOperationIndeterminate()
      )
    }
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
    .animation(.easeInOut(duration: 0.3), value: asyncOperationManager.hasRunningOperations)
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

      // Skip state detection if there are pending auto-fixes to let user resolve them
      let hasAutoFixes = currentIssues.contains { $0.autoFixAction != nil }
      if hasAutoFixes {
        AppLogger.shared.log(
          "🔧 [Navigation] Skipping monitoring - auto-fixes available, letting user resolve issues")
        continue
      }

      let operation = WizardOperations.stateDetection(stateManager: stateManager)

      await asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
        let oldState = systemState
        let oldPage = navigationCoordinator.currentPage

        systemState = result.state
        currentIssues = result.issues

        AppLogger.shared.log(
          "🔍 [Navigation] Current: \(navigationCoordinator.currentPage), Issues: \(result.issues.map { "\($0.category)-\($0.title)" })"
        )

        // Use navigation coordinator for auto-navigation logic
        navigationCoordinator.autoNavigateIfNeeded(for: result.state, issues: result.issues)

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
      let autoFixableIssues = currentIssues.compactMap { $0.autoFixAction }

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
              toastManager.showError("Failed to \(actionDescription.lowercased())")
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

            // Show toast notification and refresh state if successful
            if success {
              Task { @MainActor in
                toastManager.showSuccess("\(actionDescription) completed successfully")
              }
              // Refresh system state after successful auto-fix
              Task {
                await refreshState()
              }
            } else {
              Task { @MainActor in
                toastManager.showError("Failed to \(actionDescription.lowercased())")
              }
            }

            continuation.resume(returning: success)
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
      return "Terminate conflicting processes"
    case .startKarabinerDaemon:
      return "Start Karabiner daemon"
    case .restartVirtualHIDDaemon:
      return "Fix VirtualHID connection issues"
    case .installMissingComponents:
      return "Install missing components"
    case .createConfigDirectories:
      return "Create configuration directories"
    case .activateVHIDDeviceManager:
      return "Activate VirtualHID Device Manager"
    case .installLaunchDaemonServices:
      return "Install LaunchDaemon services"
    case .installViaBrew:
      return "Install packages via Homebrew"
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
    return await withCheckedContinuation { continuation in
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
    AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with KanataManager")
    autoFixer = WizardAutoFixer(kanataManager: kanataManager)
    AppLogger.shared.log("🔧 [AutoFixerManager] Configuration complete")
  }

  func canAutoFix(_ action: AutoFixAction) -> Bool {
    autoFixer?.canAutoFix(action) ?? false
  }

  func performAutoFix(_ action: AutoFixAction) async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixerManager] performAutoFix called for action: \(action)")
    guard let autoFixer = autoFixer else {
      AppLogger.shared.log("❌ [AutoFixerManager] Internal autoFixer is nil - returning false")
      return false
    }
    AppLogger.shared.log("🔧 [AutoFixerManager] Delegating to internal autoFixer")
    return await autoFixer.performAutoFix(action)
  }
}
