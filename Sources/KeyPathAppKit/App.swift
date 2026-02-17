import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import ServiceManagement
import Sparkle
import SwiftUI

public struct KeyPathApp: App {
    // Phase 4: MVVM - Use ViewModel instead of Manager directly
    @State private var viewModel: KanataViewModel
    private let kanataManager: RuntimeCoordinator
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let isHeadlessMode: Bool

    public init() {
        // Check if running in headless mode (started by LaunchAgent)
        let args = ProcessInfo.processInfo.arguments
        isHeadlessMode =
            args.contains("--headless") || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

        AppLogger.shared.info(
            "🔍 [App] Initializing KeyPath - headless: \(isHeadlessMode), args: \(args)"
        )
        let info = BuildInfo.current()
        AppLogger.shared.info(
            "🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)"
        )
        AppLogger.shared.debug("📦 [Bundle] Path: \(Bundle.main.bundlePath)")

        // Verify running process signature matches installed bundle (catches failed restarts)
        SignatureHealthCheck.verifySignatureConsistency()

        // Set startup mode to prevent blocking operations during app launch (in-memory flag)
        FeatureFlags.shared.activateStartupMode(timeoutSeconds: 5.0)
        AppLogger.shared.log(
            "🔍 [App] Startup mode set (auto-clear in 5s) - IOHIDCheckAccess calls will be skipped"
        )

        // Phase 4: MVVM - Initialize services and RuntimeCoordinator via composition root
        let configurationService = ConfigurationService(
            configDirectory: "\(NSHomeDirectory())/.config/keypath"
        )
        let manager = RuntimeCoordinator(injectedConfigurationService: configurationService)
        kanataManager = manager
        viewModel = KanataViewModel(manager: manager)
        AppLogger.shared.debug(
            "🎯 [Phase 4] MVVM architecture initialized - ViewModel wrapping RuntimeCoordinator"
        )

        // Configure MainAppStateController early so it's ready when overlay starts observing.
        // Previously this was called in ContentView.onAppear which happens AFTER showForStartup(),
        // causing the health indicator to get stuck in "checking" state.
        MainAppStateController.shared.configure(with: manager)

        // Ensure typing sounds manager is initialized so it can listen for key events
        // even before the overlay/settings UI is opened.
        _ = TypingSoundsManager.shared

        // Set activation policy based on mode
        if isHeadlessMode {
            // Hide from dock in headless mode
            NSApplication.shared.setActivationPolicy(.accessory)
            AppLogger.shared.log("🤖 [App] Running in headless mode (LaunchAgent)")
        } else {
            // Show in dock for normal mode
            NSApplication.shared.setActivationPolicy(.regular)
            AppLogger.shared.log("🪟 [App] Running in normal mode (with UI)")
        }

        appDelegate.kanataManager = manager
        appDelegate.viewModel = viewModel
        appDelegate.isHeadlessMode = isHeadlessMode

        // Request user notification authorization after app has fully launched
        // Delayed to avoid UNUserNotificationCenter initialization issues during bundle setup
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100)) // 0.1s delay
            UserNotificationService.shared.requestAuthorizationIfNeeded()

            // Start Kanata error monitoring
            KanataErrorMonitor.shared.startMonitoring()
            AppLogger.shared.info("🔍 [App] Started Kanata error monitoring")

            // Initialize Sparkle update service
            UpdateService.shared.initialize()
            AppLogger.shared.info("🔄 [App] Sparkle update service initialized")

            // Fetch Kanata version for About panel
            await BuildInfo.fetchKanataVersion()

            // Start global hotkey monitoring (Option+Command+K to show/hide, Option+Command+L to reset/center)
            GlobalHotkeyService.shared.startMonitoring()

            // Initialize WindowManager with retry logic for CGS APIs
            // initializeWithRetry() checks immediately, then uses exponential backoff if needed
            await WindowManager.shared.initializeWithRetry()
            AppLogger.shared.info("🪟 [App] WindowManager initialization complete")
        }
    }

    public var body: some Scene {
        // Note: Main window now managed by AppKit MainWindowController
        // Settings scene for preferences window
        Settings {
            SettingsContainerView()
                .environment(viewModel) // Phase 4: Inject ViewModel
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionSnapshotProvider, PermissionOracle.shared)
        }
        .commands {
            // Replace default "AppName" menu with "KeyPath" menu
            CommandGroup(replacing: .appInfo) {
                Button("About KeyPath") {
                    let info = BuildInfo.current()
                    var detailLines = ["Build \(info.build) • \(info.git) • \(info.date)"]
                    if let kanataVersion = info.kanataVersion {
                        detailLines.append("Kanata \(kanataVersion)")
                    }
                    let details = detailLines.joined(separator: "\n")
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: details,
                                attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                            ),
                            NSApplication.AboutPanelOptionKey.applicationName: "KeyPath",
                            NSApplication.AboutPanelOptionKey.applicationVersion: info.version,
                            NSApplication.AboutPanelOptionKey.version: "Build \(info.build)"
                        ]
                    )
                }

                Divider()

                CheckForUpdatesView(updater: UpdateService.shared.updater)
            }

            // Add File menu with Settings tabs shortcuts
            CommandGroup(replacing: .newItem) {
                Button(
                    action: {
                        openPreferencesTab(.openSettingsAdvanced)
                    },
                    label: {
                        Label("Repair/Remove…", systemImage: "wrench.and.screwdriver")
                    }
                )
                .keyboardShortcut(",", modifiers: .command)

                Button(
                    action: {
                        openPreferencesTab(.openSettingsRules)
                    },
                    label: {
                        Label("Rules…", systemImage: "list.bullet")
                    }
                )
                .keyboardShortcut("r", modifiers: .command)

                Button(
                    action: {
                        openPreferencesTab(.openSettingsAdvanced)
                    },
                    label: {
                        Label("Simulator (Repair/Remove)…", systemImage: "keyboard")
                    }
                )

                Button(
                    action: {
                        openPreferencesTab(.openSettingsSystemStatus)
                    },
                    label: {
                        Label("System Status…", systemImage: "gauge.with.dots.needle.67percent")
                    }
                )
                .keyboardShortcut("s", modifiers: .command)

                Button(
                    action: {
                        openPreferencesTab(.openSettingsLogs)
                    },
                    label: {
                        Label("Logs…", systemImage: "doc.text.magnifyingglass")
                    }
                )
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Install wizard...") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button(
                    action: {
                        openConfigInEditor(viewModel: viewModel)
                    },
                    label: {
                        Label("Edit Config", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                )
                .keyboardShortcut("o", modifiers: .command)

                Button("Simple Key Mappings…") {
                    // Present as a sheet from the (splash) main window.
                    appDelegate.showMainWindow()
                    NotificationCenter.default.post(name: NSNotification.Name("ShowSimpleMods"), object: nil)
                }

                Divider()

                Button(
                    action: {
                        LiveKeyboardOverlayController.shared.toggle()
                    },
                    label: {
                        Label("Live Keyboard Overlay", systemImage: "keyboard.badge.eye")
                    }
                )
                .keyboardShortcut("k", modifiers: .command)

                Button(
                    action: {
                        RecentKeypressesWindowController.shared.toggle()
                    },
                    label: {
                        Label("Recent Keypresses", systemImage: "list.bullet.rectangle")
                    }
                )
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Input Capture Experiment") {
                    InputCaptureExperimentWindowController.shared.showWindow()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Mapper") {
                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Button("How to Emergency Stop") {
                    // Present as a sheet from the (splash) main window.
                    appDelegate.showMainWindow()
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowEmergencyStop"), object: nil
                    )
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button(
                    role: .destructive,
                    action: {
                        // Present as a sheet from the (splash) main window.
                        appDelegate.showMainWindow()
                        NotificationCenter.default.post(name: NSNotification.Name("ShowUninstall"), object: nil)
                    },
                    label: {
                        Label("Uninstall KeyPath…", systemImage: "trash")
                    }
                )

                // Hidden instant uninstall (no confirmation, just admin prompt)
                Button(
                    role: .destructive,
                    action: {
                        Task { @MainActor in
                            AppLogger.shared.log("🗑️ [InstantUninstall] ⌥⌘U triggered - performing immediate uninstall")
                            let coordinator = UninstallCoordinator()
                            let success = await coordinator.uninstall(deleteConfig: false)
                            if success {
                                AppLogger.shared.log("✅ [InstantUninstall] Uninstall completed successfully")
                                NSApplication.shared.terminate(nil)
                            } else {
                                AppLogger.shared.log("❌ [InstantUninstall] Uninstall failed")
                                let alert = NSAlert()
                                alert.messageText = "Uninstall Failed"
                                alert.informativeText = coordinator.lastError ?? "An unknown error occurred during uninstall"
                                alert.alertStyle = .critical
                                alert.runModal()
                            }
                        }
                    },
                    label: {
                        Text("") // Hidden menu item
                    }
                )
                .keyboardShortcut("u", modifiers: [.control, .option, .command])
                .hidden() // Hide from menu but keep keyboard shortcut active
            }

        }
    }
}

// MARK: - Helper Functions

@MainActor
func openConfigInEditor(viewModel: KanataViewModel) {
    let url = URL(fileURLWithPath: viewModel.configPath)
    openFileInPreferredEditor(url)
}

/// Opens a file in Zed if available, otherwise falls back to default application
@MainActor
func openFileInPreferredEditor(_ url: URL) {
    let zedBundleID = "dev.zed.Zed"

    // Try to find Zed
    if let zedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: zedBundleID) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: zedURL, configuration: config) { _, error in
            if let error {
                AppLogger.shared.log("⚠️ Failed to open in Zed: \(error). Falling back to default.")
                NSWorkspace.shared.open(url)
            } else {
                AppLogger.shared.log("📝 Opened config in Zed")
            }
        }
    } else {
        // Zed not installed, use default
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 Opened config with default application (Zed not found)")
    }
}

@MainActor
private func openPreferencesTab(_ notification: Notification.Name) {
    AppLogger.shared.log("🎯 [App] Opening preferences tab: \(notification.rawValue)")

    // Post notification first to ensure tab switches when window opens
    NotificationCenter.default.post(name: notification, object: nil)

    // macOS 14+: The Settings menu item is automatically created by SwiftUI
    // Find it in the app menu and trigger it programmatically
    if let appMenu = NSApp.mainMenu?.items.first?.submenu {
        for item in appMenu.items {
            // Look for the "Settings..." menu item (standard name on macOS)
            if item.title.contains("Settings") || item.title.contains("Preferences"),
               let action = item.action
            {
                AppLogger.shared.log("✅ [App] Found Settings menu item, triggering it")
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(action, to: item.target, from: item)
                return
            }
        }
    }

    AppLogger.shared.log("⚠️ [App] Could not find Settings menu item, trying fallback")

    // Fallback: Use the selector method (works on macOS 13 and earlier)
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 13, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var kanataManager: RuntimeCoordinator?
    var viewModel: KanataViewModel?
    var isHeadlessMode = false
    private var mainWindowController: MainWindowController?
    private var menuBarController: MenuBarController?
    private var initialMainWindowShown = false
    private var pendingReopenShow = false
    private var suppressLaunchSplashAutoHide = false
    private var keyboardCapture: KeyboardCapture?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminate called")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminateAfterLastWindowClosed called")
        // Keep the app resident when the global hotkey is enabled so Option+Command+K
        // can bring the overlay back even with no windows visible.
        return !GlobalHotkeyService.shared.isEnabled
    }

    func applicationWillHide(_: Notification) {
        AppLogger.shared.debug("🔍 [AppDelegate] applicationWillHide called")
    }

    func applicationDidBecomeActive(_: Notification) {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationDidBecomeActive called (initialShown=\(initialMainWindowShown))"
        )

        // One-shot first activation:
        // Show a brief splash window, then bring up the overlay as the primary surface.
        if !initialMainWindowShown {
            let suppressAutoHideBecauseReopen = pendingReopenShow

            // Log diagnostic state at first activation for future debugging
            let appActive = NSApp.isActive
            let appHidden = NSApp.isHidden
            AppLogger.shared.debug(
                "🔍 [AppDelegate] First activation diagnostics: isActive=\(appActive), isHidden=\(appHidden)"
            )

            // Check if app was hidden and unhide if needed
            if NSApp.isHidden {
                NSApp.unhide(nil)
                AppLogger.shared.debug("🪟 [AppDelegate] App was hidden, unhiding")
            }

            initialMainWindowShown = true

            // Show splash quickly (Adobe-style launch splash). It also provides a stable
            // anchor for any sheets triggered from menu actions.
            suppressLaunchSplashAutoHide = false
            mainWindowController?.show(focus: true)

            Task { @MainActor in
                // Let the splash be visible for a brief moment before showing the overlay.
                #if DEBUG
                    // Keep it short by default (real macOS app splash feel), but allow
                    // overriding for debugging via `KEYPATH_SPLASH_DELAY_MS`.
                    let splashDelayMs = Int(ProcessInfo.processInfo.environment["KEYPATH_SPLASH_DELAY_MS"] ?? "")
                        ?? 650
                #else
                    let splashDelayMs = 420
                #endif
                AppLogger.shared.info("[AppDelegate] Launch splash delay: \(splashDelayMs)ms")
                try? await Task.sleep(for: .milliseconds(splashDelayMs))

                LiveKeyboardOverlayController.shared.showForStartup(bypassHiddenCheck: true)
                AppLogger.shared.debug("🪟 [AppDelegate] First activation - overlay shown")

                // Auto-hide splash (do not close) unless the user explicitly requested the window.
                if !self.suppressLaunchSplashAutoHide, !suppressAutoHideBecauseReopen {
                    self.mainWindowController?.window?.orderOut(nil)
                    AppLogger.shared.debug("🪟 [AppDelegate] Auto-hid launch splash window")
                }
            }

            AppLogger.shared.debug("🪟 [AppDelegate] First activation complete (splash shown briefly)")

            if pendingReopenShow {
                AppLogger.shared.debug(
                    "🪟 [AppDelegate] Applying pending reopen show after first activation"
                )
                pendingReopenShow = false
                // Show main window only when explicitly requested via dock click etc.
                mainWindowController?.show(focus: true)
            }
        } else {
            // Subsequent activations: only show overlay if user hasn't explicitly hidden it
            if !LiveKeyboardOverlayController.shared.isVisible,
               LiveKeyboardOverlayController.shared.canAutoShow
            {
                LiveKeyboardOverlayController.shared.showForStartup()
                AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - showing overlay")
            } else if !LiveKeyboardOverlayController.shared.isVisible {
                AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - overlay hidden by user, not auto-showing")
            } else {
                AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - overlay already visible")
            }
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppLogger.shared.info("🔍 [AppDelegate] applicationDidFinishLaunching called")

        #if DEBUG
            AppLogger.shared.info("[AppDelegate] Build configuration: DEBUG")
        #else
            AppLogger.shared.info("[AppDelegate] Build configuration: RELEASE")
        #endif

        // Log build information for traceability
        let info = BuildInfo.current()
        AppLogger.shared.info(
            "🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)"
        )

        // Set smart default keyboard layout on first launch
        setSmartKeyboardLayoutDefault()

        // Phase 2/3: TCP-only mode (no authentication needed)
        AppLogger.shared.debug("📡 [AppDelegate] TCP communication mode - no auth token needed")

        if !isHeadlessMode {
            setupMenuBarController()
        }

        // Warm the splash poster early so it renders during the very brief launch splash.
        // This avoids a "blank poster" flash from lazy NSImage decoding.
        if !isHeadlessMode {
            SplashView.PosterCache.warmIfNeeded()
        }

        // Legacy LaunchAgent support removed

        // Check for pending service bounce first
        // Skip on fresh install to avoid prompting user before wizard runs
        Task { @MainActor in
            // Fresh install check: no prior SMAppService registrations
            let isFreshInstall = Self.checkIsFreshInstall()
            if isFreshInstall {
                AppLogger.shared.info("🆕 [AppDelegate] Fresh install detected - skipping service bounce")
                PermissionGrantCoordinator.shared.clearServiceBounceFlag()
                return
            }

            let (shouldBounce, timeSince) = PermissionGrantCoordinator.shared.checkServiceBounceNeeded()

            if shouldBounce {
                if let timeSince {
                    AppLogger.shared.info(
                        "🔄 [AppDelegate] Service bounce requested \(Int(timeSince))s ago - performing bounce"
                    )
                } else {
                    AppLogger.shared.info("🔄 [AppDelegate] Service bounce requested - performing bounce")
                }

                let bounceSuccess = await PermissionGrantCoordinator.shared.performServiceBounce()
                if bounceSuccess {
                    AppLogger.shared.info("✅ [AppDelegate] Service bounce completed successfully")
                    PermissionGrantCoordinator.shared.clearServiceBounceFlag()
                } else {
                    AppLogger.shared.warn("❌ [AppDelegate] Service bounce failed - flag remains for retry")
                }
            }
        }

        if isHeadlessMode {
            AppLogger.shared.info("🤖 [AppDelegate] Headless mode - starting kanata service automatically")

            // In headless mode, ensure kanata starts
            Task {
                // Small delay to let system settle
                try? await Task.sleep(for: .seconds(2)) // 2 seconds

                // Start kanata if not already running
                if let manager = self.kanataManager {
                    let started = await manager.startKanata(reason: "Headless auto-start")
                    if !started {
                        AppLogger.shared.error("❌ [AppDelegate] Headless auto-start failed via KanataService")
                    }
                } else {
                    AppLogger.shared.error("❌ [AppDelegate] Headless auto-start failed: RuntimeCoordinator unavailable")
                }
            }
        }
        // Note: In normal mode, kanata is already started in RuntimeCoordinator.init() if requirements are met

        // MARK: - Notification Wiring (moved out of legacy ContentView)

        // Show the installation wizard regardless of whether the main window is visible.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowWizardNotification(_:)),
            name: .showWizard,
            object: nil
        )

        // Unified “open wizard” action used by permission notifications.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenInstallationWizardNotification(_:)),
            name: .openInstallationWizard,
            object: nil
        )

        // Startup + post-wizard validation trigger.
        NotificationCenter.default.addObserver(
            forName: .kp_startupRevalidate, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await MainAppStateController.shared.performInitialValidation()
            }
        }

        // Settings/permission flows sometimes post a “toast” message; show as a user notification now that
        // the main window is a splash.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowUserFeedback"), object: nil, queue: .main
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                Task { @MainActor in
                    UserNotificationService.shared.notifyRecoverySucceeded(message)
                }
            }
        }

        // Reset-to-safe config action (used by notification buttons).
        NotificationCenter.default.addObserver(
            forName: .resetToSafeConfig, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = await self?.viewModel?.createDefaultUserConfigIfMissing()
                await MainAppStateController.shared.revalidate()
                UserNotificationService.shared.notifyRecoverySucceeded("Configuration reset to safe defaults.")
            }
        }

        // Start emergency-stop monitoring once permissions are already granted (no prompts at launch).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            await self.startEmergencyMonitoringIfPermitted()
        }

        // Create main window controller (defer fronting until first activation)
        if !isHeadlessMode {
            AppLogger.shared.debug("🪟 [AppDelegate] Setting up main window controller")

            guard let vm = viewModel else {
                AppLogger.shared.error("❌ [AppDelegate] ViewModel is nil, cannot create window")
                return
            }
            mainWindowController = MainWindowController(viewModel: vm)
            AppLogger.shared.debug(
                "🪟 [AppDelegate] Main window controller created (deferring show until activation)"
            )

            // Overlay is shown on the first application activation (after the brief splash),
            // so launch reads as "splash -> overlay" instead of two windows at once.

            // Configure overlay controller with viewModel for Mapper integration and keymap changes
            LiveKeyboardOverlayController.shared.configure(
                kanataViewModel: vm,
                ruleCollectionsManager: kanataManager?.rulesManager
            )

            // Initialize Context HUD controller (sets up notification observers)
            _ = ContextHUDController.shared

            // Defer all window fronting until the first applicationDidBecomeActive event
            // to avoid AppKit display-cycle reentrancy during initial layout.

            // Simple sequential startup (no timers/notifications fan-out)
            Task { @MainActor in
                do {
                    try await AppConfigGenerator.regenerateFromStore()
                    AppLogger.shared.log("✅ [AppDelegate] App-specific config regenerated")
                } catch {
                    AppLogger.shared.error(
                        "❌ [AppDelegate] Failed to regenerate app-specific config: \(error)"
                    )
                }

                // Respect permission-grant return to avoid resetting wizard state
                let result = PermissionGrantCoordinator.shared.checkForPendingPermissionGrant()
                if !result.shouldRestart {
                    AppLogger.shared.log("🚀 [AppDelegate] Starting auto-launch sequence (simple)")
                    if let manager = self.kanataManager {
                        let started = await manager.startKanata(reason: "AppDelegate auto-launch")
                        if started {
                            AppLogger.shared.log("✅ [AppDelegate] Auto-launch sequence completed (simple)")
                        } else {
                            AppLogger.shared.error("❌ [AppDelegate] Auto-launch failed via KanataService")
                        }
                    } else {
                        AppLogger.shared.error(
                            "❌ [AppDelegate] Auto-launch requested but RuntimeCoordinator unavailable"
                        )
                    }
                } else {
                    AppLogger.shared.log(
                        "⏭️ [AppDelegate] Skipping auto-launch (returning from permission grant)"
                    )
                }

                // Trigger validation once after auto-launch attempt
                NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)

                // Auto-launch wizard if helper is not functional (covers fresh install AND reinstall after uninstall)
                // Use XPC functionality test, not just SMAppService status, since status can be stale after uninstall
                let helperFunctional = await HelperManager.shared.testHelperFunctionality()
                AppLogger.shared.info("🆕 [AppDelegate] Helper functional check: \(helperFunctional)")
                if !helperFunctional {
                    AppLogger.shared.info("🆕 [AppDelegate] Helper not functional - auto-launching wizard")
                    // Small delay to ensure overlay is visible first and orphan cleanup dialog can show first
                    try? await Task.sleep(for: .seconds(1)) // 1s
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
                }
            }
        } else {
            AppLogger.shared.debug("🤖 [AppDelegate] Headless mode - skipping window management")
        }

        // Observe notification action events
        NotificationCenter.default.addObserver(forName: .retryStartService, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                AppLogger.shared.log("🔄 [App] Retry start requested via notification")
                guard let manager = self?.kanataManager else {
                    AppLogger.shared.error("❌ [App] Retry start requested but RuntimeCoordinator unavailable")
                    return
                }
                let success = await manager.restartServiceWithFallback(reason: "Notification retryStartService")
                if !success {
                    AppLogger.shared.error("❌ [App] Retry start failed via KanataService fallback")
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openInputMonitoringSettings, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.kanataManager?.openInputMonitoringSettings()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openAccessibilitySettings, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.kanataManager?.openAccessibilitySettings()
            }
        }

        // Wire ActionDispatcher errors to user notifications (for deep link failures)
        ActionDispatcher.shared.onError = { message in
            UserNotificationService.shared.notifyActionError(message)
        }

        // Wire layer action to update the overlay and layer indicator
        // This handles push-msg "layer:X" from momentary layer activations
        ActionDispatcher.shared.onLayerAction = { layerName in
            Task { @MainActor in
                // Update the keyboard overlay
                LiveKeyboardOverlayController.shared.updateLayerName(layerName)

                // Post notification for other listeners (e.g., RuleCollectionsManager)
                NotificationCenter.default.post(
                    name: .kanataLayerChanged,
                    object: nil,
                    userInfo: ["layerName": layerName, "source": "push"]
                )

                AppLogger.shared.log("🔄 [App] Layer action dispatched: '\(layerName)'")
            }
        }
    }

    /// Check if this is a fresh install (no prior SMAppService registrations)
    /// Fresh install = neither helper nor daemon have been registered before
    private static func checkIsFreshInstall() -> Bool {
        let helperStatus = SMAppService.daemon(plistName: "com.keypath.helper.plist").status
        let daemonStatus = SMAppService.daemon(plistName: "com.keypath.kanata.plist").status

        // Fresh if both are not registered (never been installed)
        let isFresh = helperStatus == .notRegistered && daemonStatus == .notRegistered
        AppLogger.shared.log(
            "🔍 [AppDelegate] Fresh install check: helper=\(helperStatus), daemon=\(daemonStatus), isFresh=\(isFresh)"
        )
        return isFresh
    }

    private func setupMenuBarController() {
        guard menuBarController == nil else { return }
        menuBarController = MenuBarController(
            bringToFrontHandler: { [weak self] in
                self?.showKeyPathFromStatusItem()
            },
            showWizardHandler: { targetPage in
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowWizard"),
                    object: nil,
                    userInfo: targetPage.map { ["targetPage": $0] }
                )
            },
            openSettingsHandler: {
                NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
            },
            openSettingsRulesHandler: {
                NotificationCenter.default.post(name: .openSettingsRules, object: nil)
            },
            quitHandler: {
                // Close all windows first to avoid beep from modal blocking
                for window in NSApplication.shared.windows {
                    window.close()
                }
                NSApplication.shared.terminate(nil)
            }
        )

        // Configure with state observation after initialization
        if let rulesManager = kanataManager?.rulesManager {
            menuBarController?.configure(
                appStateController: MainAppStateController.shared,
                ruleCollectionsManager: rulesManager
            )
        }

        AppLogger.shared.debug("☰ [MenuBar] Status item initialized")
    }

    /// Bring the main window (splash) to the front. Used by menu actions that present sheets.
    @MainActor
    func showMainWindow() {
        showKeyPathFromStatusItem()
    }

    private func showKeyPathFromStatusItem() {
        AppLogger.shared.debug("☰ [MenuBar] Show KeyPath requested from status item")

        if mainWindowController == nil {
            if let vm = viewModel {
                mainWindowController = MainWindowController(viewModel: vm)
                AppLogger.shared.debug("🪟 [MenuBar] Created main window controller for status item request")
            } else {
                AppLogger.shared.error("❌ [MenuBar] Cannot show KeyPath: ViewModel unavailable")
                return
            }
        }

        // If the user explicitly shows the main window, don't auto-hide it as part of launch splash.
        suppressLaunchSplashAutoHide = true

        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.show(focus: true)
        initialMainWindowShown = true
        pendingReopenShow = false
    }

    func applicationWillResignActive(_: Notification) {
        AppLogger.shared.log("🔍 [AppDelegate] applicationWillResignActive called")
    }

    func applicationWillTerminate(_: Notification) {
        AppLogger.shared.info(
            "🚪 [AppDelegate] Application will terminate - performing synchronous cleanup"
        )

        // Use synchronous cleanup to ensure kanata is stopped before app exits
        // Note: InstallerEngine manages service lifecycle, but for app termination we rely on
        // RuntimeCoordinator's cleanup logic which now delegates to standard service handling
        kanataManager?.cleanupSync()

        AppLogger.shared.info("✅ [AppDelegate] Cleanup complete, app terminating")
    }

    // MARK: - URL Scheme Handling (keypath://)

    func application(_: NSApplication, open urls: [URL]) {
        AppLogger.shared.log("🔗 [AppDelegate] Received \(urls.count) URL(s) to open")

        for url in urls {
            AppLogger.shared.log("🔗 [AppDelegate] Processing URL: \(url.absoluteString)")

            // Only handle keypath:// URLs
            guard url.scheme == KeyPathActionURI.scheme else {
                AppLogger.shared.log("⚠️ [AppDelegate] Ignoring non-keypath URL: \(url.scheme ?? "nil")")
                continue
            }

            // Parse and dispatch
            if let actionURI = KeyPathActionURI(string: url.absoluteString) {
                AppLogger.shared.log("🎬 [AppDelegate] Dispatching action: \(actionURI.action)")
                ActionDispatcher.shared.dispatch(actionURI)
            } else {
                AppLogger.shared.log("⚠️ [AppDelegate] Failed to parse URL as KeyPathActionURI")
                ActionDispatcher.shared.onError?("Invalid keypath:// URL: \(url.absoluteString)")
            }
        }
    }

    /// Sets a smart default keyboard layout on first launch based on detected keyboard type.
    /// Only runs once - if user has already set a preference, this is a no-op.
    private func setSmartKeyboardLayoutDefault() {
        let key = LayoutPreferences.layoutIdKey

        // Check if user has ever set a layout preference
        if UserDefaults.standard.string(forKey: key) != nil {
            AppLogger.shared.debug("⌨️ [AppDelegate] Keyboard layout already set by user, skipping auto-detect")
            return
        }

        // First launch - detect keyboard type and set smart default
        let recommendedLayout = KeyboardTypeDetector.recommendedLayoutId()
        UserDefaults.standard.set(recommendedLayout, forKey: key)

        let detectedType = KeyboardTypeDetector.detect()
        AppLogger.shared.info("⌨️ [AppDelegate] First launch - detected keyboard type: \(detectedType.rawValue), setting default layout: \(recommendedLayout)")
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationShouldHandleReopen (hasVisibleWindows=\(flag))"
        )

        // If UI hasn’t been set up yet (e.g., app was started in headless mode by LaunchAgent),
        // escalate to a regular app and create the main window on demand.
        if mainWindowController == nil {
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
                AppLogger.shared.debug(
                    "🪟 [AppDelegate] Escalated activation policy to .regular for UI reopen"
                )
            }

            if let vm = viewModel {
                mainWindowController = MainWindowController(viewModel: vm)
                AppLogger.shared.debug("🪟 [AppDelegate] Created main window controller on reopen")
            } else {
                AppLogger.shared.error(
                    "❌ [AppDelegate] Cannot create window on reopen: ViewModel is nil"
                )
            }
        }

        // During early startup, defer showing until first activation completed to avoid layout reentrancy
        if !initialMainWindowShown {
            pendingReopenShow = true
            AppLogger.shared.debug(
                "🪟 [AppDelegate] Reopen received before first activation; deferring show"
            )
        } else {
            mainWindowController?.show(focus: true)
            AppLogger.shared.debug("🪟 [AppDelegate] User-initiated reopen - showing main window")
        }

        return true
    }

    // MARK: - Wizard Presentation

    @MainActor
    private func showWizard(targetPage: WizardPage?) {
        guard let vm = viewModel else {
            AppLogger.shared.error("❌ [AppDelegate] Cannot show wizard: ViewModel unavailable")
            return
        }

        let initialPage = targetPage ?? resolveWizardInitialPage()
        WizardWindowController.shared.showWindow(
            initialPage: initialPage,
            kanataViewModel: vm,
            onDismiss: { [weak self] in
                Task { @MainActor in
                    // Wizard actions can change permissions + service state; refresh both.
                    await self?.viewModel?.updateStatus()
                    await MainAppStateController.shared.revalidate()
                }
            }
        )
    }

    // MARK: - Notification Handlers

    @objc private func handleShowWizardNotification(_ notification: Notification) {
        // Avoid capturing non-Sendable values across actor hops by reducing to raw types first.
        let targetRaw = (notification.userInfo?["targetPage"] as? WizardPage)?.rawValue
        Task { @MainActor in
            let targetPage = targetRaw.flatMap(WizardPage.init(rawValue:))
            self.showWizard(targetPage: targetPage)
        }
    }

    @objc private func handleOpenInstallationWizardNotification(_: Notification) {
        Task { @MainActor in
            self.showWizard(targetPage: nil)
        }
    }

    /// Mirrors the legacy ContentView logic so permission-grant return flows still reopen
    /// the wizard at the most relevant page after an app restart.
    @MainActor
    private func resolveWizardInitialPage() -> WizardPage? {
        // Check for FDA restart restore point (used when app restarts for Full Disk Access)
        if let restorePoint = UserDefaults.standard.string(forKey: "KeyPath.WizardRestorePoint") {
            let restoreTime = UserDefaults.standard.double(forKey: "KeyPath.WizardRestoreTime")
            let timeSinceRestore = Date().timeIntervalSince1970 - restoreTime

            // Clear the restore point immediately
            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestorePoint")
            UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestoreTime")

            // Only restore if within 5 minutes
            if timeSinceRestore < 300 {
                let page = WizardPage.allCases.first { $0.rawValue == restorePoint }
                    ?? WizardPage.allCases.first { String(describing: $0) == restorePoint }
                if let page {
                    AppLogger.shared.log("🔄 [AppDelegate] Restoring wizard to \(page.displayName) after app restart")
                    return page
                }
            } else {
                AppLogger.shared.log("⏱️ [AppDelegate] Wizard restore point expired (\(Int(timeSinceRestore))s old)")
            }
        }

        if UserDefaults.standard.bool(forKey: "wizard_return_to_summary") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_summary")
            AppLogger.shared.log("✅ [AppDelegate] Permissions granted - returning to Summary")
            return .summary
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_input_monitoring") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_input_monitoring")
            return .inputMonitoring
        } else if UserDefaults.standard.bool(forKey: "wizard_return_to_accessibility") {
            UserDefaults.standard.removeObject(forKey: "wizard_return_to_accessibility")
            return .accessibility
        }

        return nil
    }

    // MARK: - Emergency Stop Monitoring

    /// Starts emergency stop monitoring if Accessibility permission is already granted.
    /// This preserves the safety feature without prompting users during app launch.
    @MainActor
    private func startEmergencyMonitoringIfPermitted() async {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        guard snapshot.keyPath.accessibility.isReady else {
            AppLogger.shared.debug("🛑 [EmergencyStop] Skipping monitor start (Accessibility not granted)")
            return
        }

        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
            AppLogger.shared.log("🎹 [AppDelegate] KeyboardCapture initialized for emergency monitoring")
        }

        guard let capture = keyboardCapture else { return }

        capture.startEmergencyMonitoring {
            Task { @MainActor in
                let stopped = await self.viewModel?.stopKanata(reason: "Emergency stop hotkey") ?? false
                if stopped {
                    AppLogger.shared.log("🛑 [EmergencyStop] Kanata service stopped via façade")
                } else {
                    AppLogger.shared.warn("⚠️ [EmergencyStop] Failed to stop Kanata service via façade")
                }

                self.viewModel?.emergencyStopActivated = true

                UserNotificationService.shared.notifyConfigEvent(
                    "Emergency stop activated",
                    body: "Remapping paused. Open Settings → Status to start the service again.",
                    key: "emergency.stop.activated"
                )

                // If the user is already in-app, show the help dialog immediately.
                if NSApp.isActive, !NSApp.isHidden {
                    self.showMainWindow()
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowEmergencyStop"),
                        object: nil
                    )
                }
            }
        }
    }
}

#if DEBUG

    // MARK: - SMAppService Dev Utilities

    @MainActor
    private func showSMAppServiceStatus(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        let status = svc.status
        AppLogger.shared.info(
            "🔧 [SM] \(plistName) status=\(status.rawValue) (0=notRegistered,1=enabled,2=requiresApproval,3=notFound)"
        )
    }

    @MainActor
    private func registerSMAppService(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        do {
            try svc.register()
            AppLogger.shared.info("✅ [SM] register() ok for \(plistName)")
        } catch {
            AppLogger.shared.error("❌ [SM] register() failed for \(plistName): \(error)")
        }
        showSMAppServiceStatus(plistName: plistName)
    }

    private func unregisterSMAppService(plistName: String) {
        let svc = SMAppService.daemon(plistName: plistName)
        if #available(macOS 13, *) {
            Task { @MainActor in
                do {
                    try await svc.unregister()
                    AppLogger.shared.info("✅ [SM] unregister() ok for \(plistName)")
                } catch {
                    AppLogger.shared.error("❌ [SM] unregister() failed for \(plistName): \(error)")
                }
                showSMAppServiceStatus(plistName: plistName)
            }
        } else {
            AppLogger.shared.warn("⚠️ [SM] unregister requires macOS 13+")
        }
    }
#endif

// MARK: - Sparkle Update Menu Item

/// SwiftUI wrapper for Sparkle's "Check for Updates" menu item
struct CheckForUpdatesView: View {
    private var updateService = UpdateService.shared

    /// The updater parameter is kept for API compatibility but we use the shared service
    init(updater _: SPUUpdater?) {}

    var body: some View {
        Button("Check for Updates…") {
            updateService.checkForUpdates()
        }
        .disabled(!updateService.canCheckForUpdates)
    }
}
