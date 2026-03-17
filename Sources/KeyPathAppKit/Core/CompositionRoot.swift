import AppKit
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathPluginKit
import KeyPathWizardCore
import SwiftUI

/// Holds the result of application-level service initialization.
/// Created once during `KeyPathApp.init()` and passed to the App struct's stored properties.
struct CompositionRootResult {
    let kanataManager: RuntimeCoordinator
    let viewModel: KanataViewModel
    let serviceContainer: ServiceContainer
    let isHeadlessMode: Bool
    let isOneShotProbeMode: Bool
}

/// Centralizes service initialization and wiring that previously lived inside `KeyPathApp.init()`.
///
/// This is a pure function (no stored state) that returns everything the App struct needs.
@MainActor
enum CompositionRoot {
    /// Perform all service initialization and return the wired-up result.
    static func bootstrap() -> CompositionRootResult {
        let environment = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        let isHeadlessMode =
            args.contains("--headless") || environment["KEYPATH_HEADLESS"] == "1"
        let isOneShotProbeMode = AppDelegate.isOneShotProbeEnvironment(environment)

        AppLogger.shared.info(
            "🔍 [App] Initializing KeyPath - headless: \(isHeadlessMode), oneShotProbe: \(isOneShotProbeMode), args: \(args)"
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
        let viewModel = KanataViewModel(manager: manager)
        let serviceContainer = ServiceContainer()
        AppLogger.shared.debug(
            "🎯 [Phase 4] MVVM architecture initialized - ViewModel wrapping RuntimeCoordinator"
        )

        // Configure MainAppStateController early so it's ready when overlay starts observing.
        if !isOneShotProbeMode {
            MainAppStateController.shared.configure(with: manager)
        }

        // Wire wizard dependencies so wizard views can access the runtime coordinator.
        configureWizardDependencies(runtimeCoordinator: manager)

        // Ensure typing sounds manager is initialized so it can listen for key events
        _ = TypingSoundsManager.shared

        // Set activation policy based on mode
        if isHeadlessMode {
            NSApplication.shared.setActivationPolicy(.accessory)
            AppLogger.shared.log("🤖 [App] Running in headless mode (LaunchAgent)")
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
            AppLogger.shared.log("🪟 [App] Running in normal mode (with UI)")
        }

        // Prime the synchronous cache before any startup config regeneration can run.
        DeviceSelectionStore.primeSharedCacheFromDisk()

        // Schedule deferred startup services
        if !isOneShotProbeMode {
            scheduleDeferredStartupServices()
        } else {
            AppLogger.shared.info("🧪 [App] One-shot probe mode active - skipping nonessential startup services")
        }

        return CompositionRootResult(
            kanataManager: manager,
            viewModel: viewModel,
            serviceContainer: serviceContainer,
            isHeadlessMode: isHeadlessMode,
            isOneShotProbeMode: isOneShotProbeMode
        )
    }

    /// Deferred startup services that don't need to block init.
    private static func scheduleDeferredStartupServices() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100)) // 0.1s delay

            UserNotificationService.shared.requestAuthorizationIfNeeded()

            // Start Kanata error monitoring
            KanataErrorMonitor.shared.startMonitoring()
            AppLogger.shared.info("🔍 [App] Started Kanata error monitoring")

            // Initialize Sparkle update service
            UpdateService.shared.initialize()
            AppLogger.shared.info("🔄 [App] Sparkle update service initialized")

            // Discover and load plugin bundles
            PluginManager.shared.discoverAndLoadPlugins()

            // Fetch Kanata version for About panel
            await BuildInfo.fetchKanataVersion()

            // Start global hotkey monitoring (Option+Command+K to show/hide, Option+Command+L to reset/center)
            GlobalHotkeyService.shared.startMonitoring()

            // Initialize WindowManager with retry logic for CGS APIs
            await WindowManager.shared.initializeWithRetry()
            AppLogger.shared.info("🪟 [App] WindowManager initialization complete")

            // Guard HID access: IOHIDManagerOpen triggers the Input Monitoring
            // permission prompt, so only use it if permission is already granted.
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            if snapshot.keyPath.inputMonitoring.isReady {
                // Start HID device monitoring for auto-detect keyboard on plug-in
                HIDDeviceMonitor.shared.startMonitoring()
                AppLogger.shared.info("🔌 [App] HID device monitor started")

                // Refine keyboard layout default if still set to ANSI from synchronous first-launch default
                let layoutKey = LayoutPreferences.layoutIdKey
                if UserDefaults.standard.string(forKey: layoutKey) == LayoutPreferences.defaultLayoutId {
                    let recommended = KeyboardTypeDetector.recommendedLayoutId()
                    if recommended != LayoutPreferences.defaultLayoutId {
                        UserDefaults.standard.set(recommended, forKey: layoutKey)
                        AppLogger.shared.info("⌨️ [App] Refined keyboard layout to \(recommended) via HID detection")
                    }
                }
            } else {
                AppLogger.shared.info("🔌 [App] HID device monitor skipped (Input Monitoring not yet granted)")
            }
        }
    }
}
