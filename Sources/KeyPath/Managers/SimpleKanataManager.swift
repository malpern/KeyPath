import Foundation
import SwiftUI

/// Simple, user-focused Kanata lifecycle manager
/// Replaces the complex 14-state LifecycleStateMachine with 4 clear states
@MainActor
class SimpleKanataManager: ObservableObject {
    // MARK: - Launch Status Model

    // Use decoupled LaunchFailureStatus from WizardTypes to avoid UI-Manager coupling
    typealias KanataLaunchStatus = LaunchFailureStatus

    // MARK: - Simple State Model

    enum State: String, CaseIterable {
        case starting // App launched, attempting auto-start
        case running // Kanata is running successfully
        case needsHelp = "needs_help" // Auto-start failed, user intervention required
        case stopped // User manually stopped

        var displayName: String {
            switch self {
            case .starting: "Starting..."
            case .running: "Running"
            case .needsHelp: "Needs Help"
            case .stopped: "Stopped"
            }
        }

        var isWorking: Bool {
            self == .running
        }

        var needsUserAction: Bool {
            self == .needsHelp
        }
    }

    // MARK: - Published Properties

    @Published private(set) var currentState: State = .starting
    @Published private(set) var errorReason: String?
    @Published private(set) var showWizard: Bool = false
    @Published private(set) var launchFailureStatus: KanataLaunchStatus?
    @Published private(set) var autoStartAttempts: Int = 0
    @Published private(set) var lastHealthCheck: Date?
    @Published private(set) var retryCount: Int = 0
    @Published private(set) var isRetryingAfterFix: Bool = false

    // MARK: - Dependencies

    private let kanataManager: KanataManager
    private let processLifecycleManager: ProcessLifecycleManager
    private var healthTimer: Timer?
    private var statusTimer: Timer?
    private let maxAutoStartAttempts = 2
    private let maxRetryAttempts = 3
    private var lastPermissionState: (input: Bool, accessibility: Bool) = (false, false)

    // MARK: - Initialization

    init(kanataManager: KanataManager) {
        self.kanataManager = kanataManager
        processLifecycleManager = ProcessLifecycleManager(kanataManager: kanataManager)
        AppLogger.shared.log("🏗️ [SimpleKanataManager] Initialized with ProcessLifecycleManager")

        // Initialize permission state
        Task {
            await updatePermissionState()

            // Recover any orphaned processes from previous app runs
            await processLifecycleManager.recoverFromCrash()
        }

        // Start centralized status monitoring
        startStatusMonitoring()

        // Listen for KeyboardCapture permission notifications
        setupNotificationListeners()
    }

    // MARK: - Public Interface

    /// Start the automatic Kanata launch sequence
    func startAutoLaunch() async {
        AppLogger.shared.log("🚀 [SimpleKanataManager] ========== AUTO-LAUNCH START ==========")

        // Check if we've already shown the wizard before
        let hasShownWizardBefore = UserDefaults.standard.bool(forKey: "KeyPath.HasShownWizard")
        AppLogger.shared.log(
            "🔍 [SimpleKanataManager] KeyPath.HasShownWizard flag: \(hasShownWizardBefore)")

        if hasShownWizardBefore {
            AppLogger.shared.log(
                "ℹ️ [SimpleKanataManager] Wizard already shown before - skipping auto-wizard, attempting quiet start"
            )
            AppLogger.shared.log(
                "🤫 [SimpleKanataManager] This means NO wizard will auto-show, only manual access via button"
            )
            // Try to start silently without showing wizard
            await attemptQuietStart()
        } else {
            AppLogger.shared.log(
                "🆕 [SimpleKanataManager] First launch detected - proceeding with normal auto-launch")
            AppLogger.shared.log(
                "🆕 [SimpleKanataManager] This means wizard MAY auto-show if system needs help")
            currentState = .starting
            errorReason = nil
            showWizard = false
            autoStartAttempts = 0
            await attemptAutoStart()
        }

        AppLogger.shared.log("🚀 [SimpleKanataManager] ========== AUTO-LAUNCH COMPLETE ==========")
    }

    /// Attempt to start quietly without showing wizard (for subsequent app launches)
    private func attemptQuietStart() async {
        AppLogger.shared.log("🤫 [SimpleKanataManager] ========== QUIET START ATTEMPT ==========")
        currentState = .starting
        errorReason = nil
        showWizard = false // Never show wizard on quiet starts
        autoStartAttempts = 0

        // Try to start, but if it fails, just show error state without wizard
        await attemptAutoStart()

        // If we ended up in needsHelp state, don't show wizard - just stay in error state
        if currentState == .needsHelp {
            AppLogger.shared.log(
                "🤫 [SimpleKanataManager] Quiet start failed - staying in error state without wizard")
            showWizard = false // Explicitly ensure wizard doesn't show
        }

        AppLogger.shared.log("🤫 [SimpleKanataManager] ========== QUIET START COMPLETE ==========")
    }

    /// Show wizard specifically for Input Monitoring permission flow
    @MainActor
    func showWizardForInputMonitoring() async {
        AppLogger.shared.log("🔐 [SimpleKanataManager] Showing wizard for Input Monitoring restart")

        // Log to file for debugging
        let logPath = "/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/logs/wizard-restart.log"
        let logEntry = """
        [\(Date())] SimpleKanataManager.showWizardForInputMonitoring called
          - Setting showWizard = true

        """
        if let data = logEntry.data(using: .utf8),
           let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }

        showWizard = true
        // Force UI update
        objectWillChange.send()
    }

    /// Manual start requested by user (from wizard)
    func manualStart() async {
        AppLogger.shared.log("👤 [SimpleKanataManager] Manual start requested by user")
        currentState = .starting
        errorReason = nil
        showWizard = false

        await attemptAutoStart()
    }

    /// Manual stop requested by user
    func manualStop() async {
        AppLogger.shared.log("👤 [SimpleKanataManager] Manual stop requested by user")
        stopHealthMonitoring()

        // Use ProcessLifecycleManager for coordinated shutdown
        processLifecycleManager.setIntent(.shouldBeStopped)

        do {
            try await processLifecycleManager.reconcileWithIntent()
            currentState = .stopped
            AppLogger.shared.log(
                "✅ [SimpleKanataManager] Manual stop completed via ProcessLifecycleManager")
        } catch {
            AppLogger.shared.log("⚠️ [SimpleKanataManager] ProcessLifecycleManager stop error: \(error)")
            // Fallback to direct KanataManager
            await kanataManager.stopKanata()
            currentState = .stopped
            AppLogger.shared.log("✅ [SimpleKanataManager] Manual stop completed via fallback")
        }
    }

    /// Refresh current status (called by centralized timer only)
    private func refreshStatus() async {
        await kanataManager.updateStatus()

        if kanataManager.isRunning {
            if currentState != .running {
                AppLogger.shared.log("✅ [SimpleKanataManager] Detected Kanata now running")
                currentState = .running
                errorReason = nil
                launchFailureStatus = nil
                showWizard = false
                isRetryingAfterFix = false
                retryCount = 0
                startHealthMonitoring()
            }
        } else {
            if currentState == .running {
                AppLogger.shared.log("❌ [SimpleKanataManager] Detected Kanata stopped running")
                await handleServiceFailure("Service stopped unexpectedly",
                                           failureType: .serviceFailure("Service stopped unexpectedly"))
            } else if currentState == .needsHelp {
                // CRITICAL FIX: Don't auto-retry if wizard is currently shown to user
                // This prevents timer-based retries from closing the wizard unexpectedly
                if showWizard {
                    AppLogger.shared.log(
                        "🎩 [SimpleKanataManager] Wizard active - deferring auto-retry to prevent interference")
                    return
                }

                // Check if permissions changed or user might have fixed things
                let permissionChanged = await checkForPermissionChanges()

                if permissionChanged || isRetryingAfterFix {
                    AppLogger.shared.log(
                        "🔄 [SimpleKanataManager] Permissions changed or retry requested - attempting auto-start"
                    )
                    await retryAfterFix("Retrying after permission changes...")
                }
                // Remove the else branch that was causing extra attemptAutoStart() calls
            }
        }

        lastHealthCheck = Date()
    }

    /// Force immediate status update (for manual refresh buttons)
    func forceRefreshStatus() async {
        AppLogger.shared.log("🔄 [SimpleKanataManager] Force refresh requested by UI")
        await refreshStatus()
    }

    // MARK: - Auto-Start Logic

    private func attemptAutoStart() async {
        autoStartAttempts += 1
        AppLogger.shared.log(
            "🔄 [SimpleKanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) ==========")

        // Step 1: Check basic requirements
        AppLogger.shared.log("🔄 [SimpleKanataManager] Step 1: Checking requirements...")

        let kanataPath = await findKanataExecutable()
        if kanataPath.isEmpty {
            AppLogger.shared.log("❌ [SimpleKanataManager] Step 1 FAILED: Kanata not found")
            await setNeedsHelp("Kanata not installed. Install with: brew install kanata",
                               failureType: .missingDependency("Kanata not installed"))
            return
        }

        if let permissionError = await checkPermissions() {
            AppLogger.shared.log("❌ [SimpleKanataManager] Step 1 FAILED: \(permissionError)")
            await setNeedsHelp(permissionError,
                               failureType: .permissionDenied(permissionError))
            return
        }

        AppLogger.shared.log("✅ [SimpleKanataManager] Step 1 PASSED: Requirements satisfied")

        // Step 2: Use ProcessLifecycleManager for intelligent process management
        AppLogger.shared.log("🔄 [SimpleKanataManager] Step 2: Setting intent and reconciling...")

        do {
            processLifecycleManager.setIntent(
                .shouldBeRunning(source: "auto_start_attempt_\(autoStartAttempts)"))
            try await processLifecycleManager.reconcileWithIntent()

            // Step 3: Verify the result
            AppLogger.shared.log("🔄 [SimpleKanataManager] Step 3: Verifying process state...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
            await kanataManager.updateStatus()

            if kanataManager.isRunning {
                AppLogger.shared.log("✅ [SimpleKanataManager] Auto-start successful!")
                currentState = .running
                errorReason = nil
                launchFailureStatus = nil
                startHealthMonitoring()
            } else {
                AppLogger.shared.log("❌ [SimpleKanataManager] Auto-start failed - process not running")
                await handleStartFailure()
            }

        } catch {
            AppLogger.shared.log("❌ [SimpleKanataManager] ProcessLifecycleManager error: \(error)")
            await handleProcessLifecycleError(error)
        }

        AppLogger.shared.log(
            "🔄 [SimpleKanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) COMPLETE =========="
        )
    }

    private func handleProcessLifecycleError(_ error: Error) async {
        if let processError = error as? ProcessLifecycleError {
            switch processError {
            case .noKanataManager:
                await setNeedsHelp("Internal error: No Kanata manager available",
                                   failureType: .serviceFailure("Internal error: No Kanata manager available"))
            case .processStartFailed:
                await handleStartFailure()
            case let .processStopFailed(underlyingError):
                await setNeedsHelp(
                    "Failed to stop conflicting processes: \(underlyingError.localizedDescription)",
                    failureType: .serviceFailure("Failed to stop conflicting processes")
                )
            case let .processTerminateFailed(underlyingError):
                await setNeedsHelp("Failed to resolve conflicts: \(underlyingError.localizedDescription)",
                                   failureType: .serviceFailure("Failed to resolve conflicts"))
            }
        } else {
            await setNeedsHelp("Process management error: \(error.localizedDescription)",
                               failureType: .serviceFailure("Process management error"))
        }
    }

    private func handleStartFailure() async {
        AppLogger.shared.log("❌ [SimpleKanataManager] Auto-start failed")

        // Check if we should retry
        if autoStartAttempts < maxAutoStartAttempts {
            AppLogger.shared.log("🔄 [SimpleKanataManager] Retrying auto-start...")
            try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
            await attemptAutoStart()
            return
        }

        // Max attempts reached - check what went wrong
        let (failureReason, failureType) = await diagnoseStartFailure()
        await setNeedsHelp(failureReason, failureType: failureType)
    }

    private func diagnoseStartFailure() async -> (String, KanataLaunchStatus) {
        // Check log file for specific errors
        let logPath = "/var/log/kanata.log"

        if let logData = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = logData.components(separatedBy: .newlines)
            let recentLines = lines.suffix(10)

            for line in recentLines.reversed() {
                if line.contains("Permission denied") {
                    let message = "Permission denied - check Input Monitoring permissions in System Settings"
                    return (message, .permissionDenied(message))
                } else if line.contains("Config"), line.contains("error") {
                    let message = "Configuration file error - check your keypath.kbd file"
                    return (message, .configError(message))
                } else if line.contains("Device"), line.contains("not found") {
                    let message = "Keyboard device not found - ensure keyboard is connected"
                    return (message, .serviceFailure(message))
                } else if line.contains("Address already in use") {
                    let message = "Another keyboard service is running - check for conflicts"
                    return (message, .serviceFailure(message))
                }
            }
        }

        let message = "Kanata failed to start - check system requirements and permissions"
        return (message, .serviceFailure(message))
    }

    private func setNeedsHelp(_ reason: String, failureType: KanataLaunchStatus? = nil) async {
        AppLogger.shared.log("❌ [SimpleKanataManager] ========== SET NEEDS HELP ==========")
        AppLogger.shared.log("❌ [SimpleKanataManager] Reason: \(reason)")
        AppLogger.shared.log(
            "❌ [SimpleKanataManager] Before - showWizard: \(showWizard), currentState: \(currentState)")

        currentState = .needsHelp
        errorReason = reason
        launchFailureStatus = failureType

        // Check if System Preferences is open before showing wizard
        let systemPrefsOpen = await isSystemPreferencesOpen()
        AppLogger.shared.log("🔍 [SimpleKanataManager] System Preferences open: \(systemPrefsOpen)")

        // Check if we've already shown the wizard before
        let hasShownWizardBefore = UserDefaults.standard.bool(forKey: "KeyPath.HasShownWizard")
        AppLogger.shared.log("🔍 [SimpleKanataManager] HasShownWizard flag: \(hasShownWizardBefore)")

        // Decision logic
        let shouldShowWizard = !systemPrefsOpen && !hasShownWizardBefore
        AppLogger.shared.log(
            "🔍 [SimpleKanataManager] Wizard decision: !systemPrefs(\(systemPrefsOpen)) && !hasShownBefore(\(hasShownWizardBefore)) = \(shouldShowWizard)"
        )

        // Only show wizard if: not in System Prefs AND haven't shown wizard before
        showWizard = shouldShowWizard
        isRetryingAfterFix = false

        if systemPrefsOpen {
            AppLogger.shared.log(
                "🔍 [SimpleKanataManager] WIZARD SUPPRESSED: User is working on permissions in System Preferences"
            )
        } else if hasShownWizardBefore {
            AppLogger.shared.log(
                "🔍 [SimpleKanataManager] WIZARD SUPPRESSED: Already shown before (one-time only policy)")
        } else {
            AppLogger.shared.log(
                "🎭 [SimpleKanataManager] WIZARD WILL BE SHOWN: First time and not in System Preferences")
        }

        // Mark that we've shown the wizard (or would have shown it)
        if showWizard {
            UserDefaults.standard.set(true, forKey: "KeyPath.HasShownWizard")
            AppLogger.shared.log(
                "📝 [SimpleKanataManager] MARKED WIZARD AS SHOWN - future launches will suppress wizard")
        }

        AppLogger.shared.log(
            "❌ [SimpleKanataManager] Final state - showWizard: \(showWizard), currentState: \(currentState)"
        )

        // Force UI update on main thread
        await MainActor.run {
            AppLogger.shared.log(
                "🎩 [SimpleKanataManager] MainActor UI update: showWizard = \(showWizard), currentState = \(currentState)"
            )
            AppLogger.shared.log(
                "🎩 [SimpleKanataManager] Published properties should now trigger SwiftUI updates")
        }

        // Update permission state for change detection
        await updatePermissionState()

        AppLogger.shared.log("❌ [SimpleKanataManager] ========== SET NEEDS HELP COMPLETE ==========")
    }

    // MARK: - Requirement Checks

    /// Check if System Preferences or System Settings is currently open
    /// This helps avoid re-triggering the wizard while user is actively fixing permissions
    private func isSystemPreferencesOpen() async -> Bool {
        // Suppress only if System Settings is frontmost (not merely running in background)
        await MainActor.run {
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let isFrontmostSettings = (frontmost == "com.apple.systempreferences")
            if isFrontmostSettings {
                AppLogger.shared.log(
                    "🔍 [SimpleKanataManager] System Settings is frontmost - suppressing wizard")
            } else {
                AppLogger.shared.log(
                    "🔍 [SimpleKanataManager] System Settings not frontmost - wizard may be shown")
            }
            return isFrontmostSettings
        }
    }

    private func findKanataExecutable() async -> String {
        let possiblePaths = [
            "/usr/local/bin/kanata", // canonical path for KeyPath
            "/opt/homebrew/bin/kanata",
            "/usr/bin/kanata"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                AppLogger.shared.log("✅ [SimpleKanataManager] Found Kanata at: \(path)")
                return path
            }
        }

        AppLogger.shared.log("❌ [SimpleKanataManager] Kanata executable not found")
        return ""
    }

    private func checkPermissions() async -> String? {
        // 🔮 THE ORACLE: Single source of truth for ALL permission detection
        // No more complex PermissionService logic, no more binary path confusion
        let snapshot = await PermissionOracle.shared.currentSnapshot()

        AppLogger.shared.log("🔮 [SimpleKanataManager] Oracle permission check complete")

        // Return the first blocking permission issue (clear, actionable message)
        if let issue = snapshot.blockingIssue {
            AppLogger.shared.log("❌ [SimpleKanataManager] Blocking issue: \(issue)")
            return issue
        }

        AppLogger.shared.log("✅ [SimpleKanataManager] All permissions ready via Oracle")
        return nil
    }

    // checkForConflicts method removed - replaced by ProcessLifecycleManager

    // MARK: - Centralized Monitoring

    /// Start centralized status monitoring (replaces individual timers in views)
    private func startStatusMonitoring() {
        // DISABLED: This timer was calling refreshStatus() every 10 seconds, which triggers
        // invasive permission checks that cause KeyPath to auto-add to Input Monitoring
        // User reported: "I STILL can't remove KeyPath from the Input Monitoring list"

        AppLogger.shared.log(
            "🔄 [SimpleKanataManager] Status monitoring timer DISABLED to prevent invasive permission checks"
        )
    }

    private func stopStatusMonitoring() {
        AppLogger.shared.log("🔄 [SimpleKanataManager] Stopping centralized status monitoring")
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // MARK: - Notification Listeners

    private func setupNotificationListeners() {
        AppLogger.shared.log("📻 [SimpleKanataManager] Setting up notification listeners")

        // Listen for KeyboardCapture permission requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("KeyboardCapturePermissionNeeded"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            AppLogger.shared.log(
                "📻 [SimpleKanataManager] Received KeyboardCapturePermissionNeeded notification")

            if let userInfo = notification.userInfo,
               let reason = userInfo["reason"] as? String {
                AppLogger.shared.log("📻 [SimpleKanataManager] Permission needed reason: \(reason)")
            }

            // Trigger the wizard to help with accessibility permissions
            Task {
                await self.setNeedsHelp("Accessibility permission required for keyboard capture",
                                        failureType: .permissionDenied("Accessibility permission required"))
            }
        }
    }

    // MARK: - Health Monitoring

    private func startHealthMonitoring() {
        // DISABLED: This health check timer also calls updateStatus() via performHealthCheck()
        // which triggers invasive permission checks that cause KeyPath to auto-add to Input Monitoring

        AppLogger.shared.log(
            "💓 [SimpleKanataManager] Health monitoring timer DISABLED to prevent invasive permission checks"
        )
    }

    private func stopHealthMonitoring() {
        AppLogger.shared.log("💓 [SimpleKanataManager] Stopping health monitoring")
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func performHealthCheck() async {
        guard currentState == .running else { return }

        await kanataManager.updateStatus()
        lastHealthCheck = Date()

        if !kanataManager.isRunning {
            AppLogger.shared.log("💓 [SimpleKanataManager] Health check failed - service down")
            await handleServiceFailure("Service health check failed",
                                       failureType: .serviceFailure("Service health check failed"))
        }
    }

    private func handleServiceFailure(_ reason: String, failureType _: KanataLaunchStatus? = nil) async {
        AppLogger.shared.log("❌ [SimpleKanataManager] Service failure: \(reason)")
        stopHealthMonitoring()

        // Attempt one auto-restart
        AppLogger.shared.log("🔄 [SimpleKanataManager] Attempting auto-restart...")
        autoStartAttempts = 0 // Reset for auto-restart
        await attemptAutoStart()
    }

    // MARK: - Enhanced Auto-Retry Logic

    /// Retry auto-start after user has potentially fixed issues
    /// CRITICAL FIX: Validate permissions are actually fixed before retrying
    func retryAfterFix(_ feedbackMessage: String) async {
        guard retryCount < maxRetryAttempts else {
            AppLogger.shared.log(
                "⚠️ [SimpleKanataManager] Max retry attempts (\(maxRetryAttempts)) reached - stopping auto-retry"
            )
            await setNeedsHelp("Multiple retry attempts failed - manual intervention required")
            return
        }

        // 🔮 ORACLE VALIDATION: Only retry if permissions are actually fixed
        let snapshot = await PermissionOracle.shared.forceRefresh()

        if !snapshot.isSystemReady {
            AppLogger.shared.log("🔄 [SimpleKanataManager] Permissions still missing - not retrying yet")
            if let issue = snapshot.blockingIssue {
                AppLogger.shared.log("📊 [SimpleKanataManager] Missing: \(issue)")
            }
            return
        }

        retryCount += 1
        isRetryingAfterFix = true

        AppLogger.shared.log("🔄 [SimpleKanataManager] Retry attempt #\(retryCount): \(feedbackMessage)")
        AppLogger.shared.log(
            "✅ [SimpleKanataManager] All permissions validated - proceeding with retry")

        // Set to starting state with user feedback
        currentState = .starting
        errorReason = feedbackMessage
        showWizard = false

        // Reset auto-start attempts for fresh retry
        autoStartAttempts = 0

        // Give user visual feedback for a moment
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        await attemptAutoStart()
    }

    /// Called when wizard closes to trigger immediate retry
    func onWizardClosed() async {
        AppLogger.shared.log("🎩 [SimpleKanataManager] Wizard closed - checking if retry is needed")
        AppLogger.shared.log("🎩 [SimpleKanataManager] Current state: \(currentState)")

        // Don't retry after wizard close - let user handle things manually
        // The wizard was already shown once, let the user fix issues and manually start
        AppLogger.shared.log(
            "🎩 [SimpleKanataManager] Skipping retry - user closed wizard, let them handle manually")
    }

    /// Detect if permissions have changed since last check
    /// 🔮 ORACLE: Clean permission change detection
    private func checkForPermissionChanges() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()

        // Current state from Oracle (authoritative)
        let currentlyReady = snapshot.isSystemReady

        // Previous state (stored simple tuple)
        let previouslyReady = lastPermissionState.input && lastPermissionState.accessibility

        // Update stored state for next comparison
        lastPermissionState = (
            snapshot.keyPath.inputMonitoring.isReady,
            snapshot.keyPath.accessibility.isReady
        )

        // Permission improvement detected
        if !previouslyReady, currentlyReady {
            AppLogger.shared.log("✅ [SimpleKanataManager] 🔮 Oracle detected system is now ready!")
            AppLogger.shared.log("📊 [SimpleKanataManager] \(snapshot.diagnosticSummary)")
            return true
        }

        // Log current state for debugging
        AppLogger.shared.log("📊 [SimpleKanataManager] 🔮 Oracle state - Ready: \(currentlyReady), Previous: \(previouslyReady)")

        return false
    }

    /// Update stored permission state using Oracle
    private func updatePermissionState() async {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        lastPermissionState = (
            snapshot.keyPath.inputMonitoring.isReady,
            snapshot.keyPath.accessibility.isReady
        )
        AppLogger.shared.log(
            "📊 [SimpleKanataManager] 🔮 Oracle updated permission state - Input: \(lastPermissionState.input), Accessibility: \(lastPermissionState.accessibility)"
        )
    }

    // MARK: - State Queries

    var isRunning: Bool {
        currentState == .running
    }

    var needsUserIntervention: Bool {
        currentState == .needsHelp
    }

    var stateDescription: String {
        if isRetryingAfterFix {
            "\(currentState.displayName): \(errorReason ?? "Retrying...") (Attempt \(retryCount)/\(maxRetryAttempts))"
        } else if let errorReason {
            "\(currentState.displayName): \(errorReason)"
        } else {
            currentState.displayName
        }
    }

    // MARK: - Cleanup

    deinit {
        AppLogger.shared.log("🏗️ [SimpleKanataManager] Deinitializing - stopping timers")
        statusTimer?.invalidate()
        healthTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
