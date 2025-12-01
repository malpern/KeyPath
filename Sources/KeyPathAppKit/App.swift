import AppKit
import KeyPathCore
import KeyPathPermissions
import ServiceManagement
import SwiftUI

public struct KeyPathApp: App {
    // Phase 4: MVVM - Use ViewModel instead of Manager directly
    @StateObject private var viewModel: KanataViewModel
    private let kanataManager: RuntimeCoordinator
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let isHeadlessMode: Bool

    public init() {
        // Check if running in headless mode (started by LaunchAgent)
        let args = ProcessInfo.processInfo.arguments
        isHeadlessMode =
            args.contains("--headless") || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

        AppLogger.shared.info(
            "🔍 [App] Initializing KeyPath - headless: \(isHeadlessMode), args: \(args)")
        let info = BuildInfo.current()
        AppLogger.shared.info(
            "🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)"
        )
        AppLogger.shared.debug("📦 [Bundle] Path: \(Bundle.main.bundlePath)")

        // Verify running process signature matches installed bundle (catches failed restarts)
        SignatureHealthCheck.verifySignatureConsistency()

        // Enable auto-trigger recording when launched with --autotrigger (in-memory flag)
        if args.contains("--autotrigger") {
            FeatureFlags.shared.setAutoTriggerEnabled(true)
            AppLogger.shared.log("🧪 [App] Auto-trigger flag detected (--autotrigger)")
        }

        // Set startup mode to prevent blocking operations during app launch (in-memory flag)
        FeatureFlags.shared.activateStartupMode(timeoutSeconds: 5.0)
        AppLogger.shared.log(
            "🔍 [App] Startup mode set (auto-clear in 5s) - IOHIDCheckAccess calls will be skipped")

        // Phase 4: MVVM - Initialize services and RuntimeCoordinator via composition root
        let configurationService = ConfigurationService(
            configDirectory: "\(NSHomeDirectory())/.config/keypath")
        let manager = RuntimeCoordinator(injectedConfigurationService: configurationService)
        kanataManager = manager
        _viewModel = StateObject(wrappedValue: KanataViewModel(manager: manager))
        AppLogger.shared.debug(
            "🎯 [Phase 4] MVVM architecture initialized - ViewModel wrapping RuntimeCoordinator")

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
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
            UserNotificationService.shared.requestAuthorizationIfNeeded()

            // Start Kanata error monitoring
            KanataErrorMonitor.shared.startMonitoring()
            AppLogger.shared.info("🔍 [App] Started Kanata error monitoring")
        }
    }

    public var body: some Scene {
        // Note: Main window now managed by AppKit MainWindowController
        // Settings scene for preferences window
        Settings {
            SettingsContainerView()
                .environmentObject(viewModel) // Phase 4: Inject ViewModel
                .environment(\.preferencesService, PreferencesService.shared)
                .environment(\.permissionSnapshotProvider, PermissionOracle.shared)
        }
        .commands {
            // Replace default "AppName" menu with "KeyPath" menu
            CommandGroup(replacing: .appInfo) {
                Button("About KeyPath") {
                    let info = BuildInfo.current()
                    let details = "Build \(info.build) • \(info.git) • \(info.date)"
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
                        openPreferencesTab(.openSettingsSimulator)
                    },
                    label: {
                        Label("Simulator…", systemImage: "keyboard")
                    }
                )
                .keyboardShortcut("k", modifiers: .command)

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

                Divider()

                Button(
                    action: {
                        LiveKeyboardOverlayController.shared.toggle()
                    },
                    label: {
                        Label("Live Keyboard Overlay", systemImage: "keyboard.badge.eye")
                    }
                )
                .keyboardShortcut("y", modifiers: .command)

                Button("Input Capture Experiment") {
                    InputCaptureExperimentWindowController.shared.showWindow()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("How to Emergency Stop") {
                    // Emergency stop dialog will be handled by main window controller
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowEmergencyStop"), object: nil
                    )
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button(
                    role: .destructive,
                    action: {
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

            #if DEBUG
                CommandMenu("Developer • SMAppService") {
                    Button("Helper: Show SMAppService Status") {
                        showSMAppServiceStatus(plistName: "com.keypath.helper.plist")
                    }

                    Button("Helper: Register via SMAppService") {
                        registerSMAppService(plistName: "com.keypath.helper.plist")
                    }

                    Button("Helper: Unregister via SMAppService") {
                        unregisterSMAppService(plistName: "com.keypath.helper.plist")
                    }
                }

            #endif
        }
    }
}

// MARK: - Helper Functions

@MainActor
func openConfigInEditor(viewModel: KanataViewModel) {
    let url = URL(fileURLWithPath: viewModel.configPath)
    NSWorkspace.shared.open(url)
    AppLogger.shared.log("📝 Opened config with default application")
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
               let action = item.action {
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

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminate called")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        AppLogger.shared.log("🔍 [AppDelegate] applicationShouldTerminateAfterLastWindowClosed called")
        return true
    }

    func applicationWillHide(_: Notification) {
        AppLogger.shared.debug("🔍 [AppDelegate] applicationWillHide called")
    }

    func applicationDidBecomeActive(_: Notification) {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationDidBecomeActive called (initialShown=\(initialMainWindowShown))")

        // One-shot first activation: unconditionally show window on first activation
        if !initialMainWindowShown {
            // Log diagnostic state at first activation for future debugging
            let appActive = NSApp.isActive
            let appHidden = NSApp.isHidden
            let windowOcclusion = mainWindowController?.window?.occlusionState ?? []
            AppLogger.shared.debug(
                "🔍 [AppDelegate] First activation diagnostics: isActive=\(appActive), isHidden=\(appHidden), windowOcclusion=\(windowOcclusion.rawValue)"
            )

            // Check if app was hidden and unhide if needed
            if NSApp.isHidden {
                NSApp.unhide(nil)
                AppLogger.shared.debug("🪟 [AppDelegate] App was hidden, unhiding")
            }

            // Unconditionally show and focus the main window on first activation
            mainWindowController?.show(focus: true)
            initialMainWindowShown = true
            AppLogger.shared.debug("🪟 [AppDelegate] First activation - main window shown and focused")
            if pendingReopenShow {
                AppLogger.shared.debug(
                    "🪟 [AppDelegate] Applying pending reopen show after first activation")
                pendingReopenShow = false
                mainWindowController?.show(focus: true)
            }
        } else {
            // Subsequent activations: only show if window not visible
            if mainWindowController?.isWindowVisible != true {
                mainWindowController?.show(focus: true)
                AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - showing hidden window")
            } else {
                AppLogger.shared.debug("🪟 [AppDelegate] Subsequent activation - window already visible")
            }
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppLogger.shared.info("🔍 [AppDelegate] applicationDidFinishLaunching called")

        // Log build information for traceability
        let info = BuildInfo.current()
        AppLogger.shared.info(
            "🏷️ [Build] Version: \(info.version) | Build: \(info.build) | Git: \(info.git) | Date: \(info.date)"
        )

        // Phase 2/3: TCP-only mode (no authentication needed)
        AppLogger.shared.debug("📡 [AppDelegate] TCP communication mode - no auth token needed")

        if !isHeadlessMode {
            setupMenuBarController()
        }

        // Legacy LaunchAgent support removed

        // Check for pending service bounce first
        Task { @MainActor in
            let (shouldBounce, timeSince) = PermissionGrantCoordinator.shared.checkServiceBounceNeeded()

            if shouldBounce {
                if let timeSince {
                    AppLogger.shared.info(
                        "🔄 [AppDelegate] Service bounce requested \(Int(timeSince))s ago - performing bounce")
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
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

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

        // Create main window controller (defer fronting until first activation)
        if !isHeadlessMode {
            AppLogger.shared.debug("🪟 [AppDelegate] Setting up main window controller")

            guard let vm = viewModel else {
                AppLogger.shared.error("❌ [AppDelegate] ViewModel is nil, cannot create window")
                return
            }
            mainWindowController = MainWindowController(viewModel: vm)
            AppLogger.shared.debug(
                "🪟 [AppDelegate] Main window controller created (deferring show until activation)")

            // Restore live keyboard overlay state from previous session
            LiveKeyboardOverlayController.shared.restoreState()

            // Defer all window fronting until the first applicationDidBecomeActive event
            // to avoid AppKit display-cycle reentrancy during initial layout.

            // Simple sequential startup (no timers/notifications fan-out)
            Task { @MainActor in
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
                        "⏭️ [AppDelegate] Skipping auto-launch (returning from permission grant)")
                }

                // Trigger validation once after auto-launch attempt
                NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
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
    }

    private func setupMenuBarController() {
        guard menuBarController == nil else { return }
        menuBarController = MenuBarController(
            bringToFrontHandler: { [weak self] in
                self?.showKeyPathFromStatusItem()
            },
            showWizardHandler: {
                NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
            },
            uninstallHandler: {
                NotificationCenter.default.post(name: NSNotification.Name("ShowUninstall"), object: nil)
            },
            quitHandler: {
                // Close all windows first to avoid beep from modal blocking
                for window in NSApplication.shared.windows {
                    window.close()
                }
                NSApplication.shared.terminate(nil)
            }
        )
        AppLogger.shared.debug("☰ [MenuBar] Status item initialized")
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
            "🚪 [AppDelegate] Application will terminate - performing synchronous cleanup")

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

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.shared.debug(
            "🔍 [AppDelegate] applicationShouldHandleReopen (hasVisibleWindows=\(flag))")

        // If UI hasn’t been set up yet (e.g., app was started in headless mode by LaunchAgent),
        // escalate to a regular app and create the main window on demand.
        if mainWindowController == nil {
            if NSApplication.shared.activationPolicy() != .regular {
                NSApplication.shared.setActivationPolicy(.regular)
                AppLogger.shared.debug(
                    "🪟 [AppDelegate] Escalated activation policy to .regular for UI reopen")
            }

            if let vm = viewModel {
                mainWindowController = MainWindowController(viewModel: vm)
                AppLogger.shared.debug("🪟 [AppDelegate] Created main window controller on reopen")
            } else {
                AppLogger.shared.error(
                    "❌ [AppDelegate] Cannot create window on reopen: ViewModel is nil")
            }
        }

        // During early startup, defer showing until first activation completed to avoid layout reentrancy
        if !initialMainWindowShown {
            pendingReopenShow = true
            AppLogger.shared.debug(
                "🪟 [AppDelegate] Reopen received before first activation; deferring show")
        } else {
            mainWindowController?.show(focus: true)
            AppLogger.shared.debug("🪟 [AppDelegate] User-initiated reopen - showing main window")
        }

        return true
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
