import AppKit
import Combine
import Foundation
import KeyPathCore

/// Service that monitors frontmost application changes and signals Kanata
/// to activate/deactivate app-specific virtual keys.
///
/// See ADR-027 for the full architecture.
///
/// ## Usage
/// ```swift
/// let service = AppContextService.shared
/// await service.start(tcpClient: kanataTCPClient)
/// ```
///
/// ## Flow
/// 1. NSWorkspace notifies of app activation
/// 2. Service looks up bundle ID in AppKeymapStore
/// 3. If mapping exists, sends ActOnFakeKey to Kanata:
///    - Release previous VK (if any)
///    - Press new VK
@MainActor
public final class AppContextService: ObservableObject {
    // MARK: - Singleton

    public static let shared = AppContextService()

    // MARK: - Published State

    /// The currently active app's bundle identifier (nil if no app has focus)
    @Published public private(set) var currentBundleIdentifier: String?

    /// The currently active virtual key (nil if current app has no keymap)
    @Published public private(set) var currentVirtualKey: String?

    /// Whether the service is actively monitoring
    @Published public private(set) var isMonitoring: Bool = false

    // MARK: - Private State

    private var tcpClient: KanataTCPClient?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObserver: NSObjectProtocol?

    /// Cache of bundle ID → virtual key name mappings
    private var bundleToVKMapping: [String: String] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Lifecycle

    /// Start monitoring app changes and signaling Kanata.
    ///
    /// - Parameter tcpPort: The TCP port to use for connecting to Kanata.
    ///                      Pass nil to use the default port from preferences.
    public func start(tcpPort: Int? = nil) async {
        guard !isMonitoring else {
            AppLogger.shared.log("⚠️ [AppContextService] Already monitoring, ignoring start()")
            return
        }

        AppLogger.shared.log("🚀 [AppContextService] Starting app context monitoring")

        // Initialize TCP client
        let port = tcpPort ?? PreferencesService.shared.tcpServerPort
        self.tcpClient = KanataTCPClient(port: port)

        // Load mappings from store
        await reloadMappings()

        // Set up workspace notification observer
        setupWorkspaceObserver()

        // Process current frontmost app immediately
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            await handleAppActivation(bundleIdentifier: frontApp.bundleIdentifier)
        }

        isMonitoring = true
        AppLogger.shared.log("✅ [AppContextService] Now monitoring \(bundleToVKMapping.count) app mappings")
    }

    /// Stop monitoring app changes.
    ///
    /// This method is async to ensure the current virtual key is properly released
    /// before returning.
    public func stop() async {
        guard isMonitoring else { return }

        AppLogger.shared.log("🛑 [AppContextService] Stopping app context monitoring")

        // Remove workspace observer
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        // Release current virtual key if any (await to ensure it completes)
        await releaseCurrentVirtualKey()

        cancellables.removeAll()
        isMonitoring = false
        currentBundleIdentifier = nil
        currentVirtualKey = nil
        tcpClient = nil

        AppLogger.shared.log("✅ [AppContextService] Stopped")
    }

    /// Reload mappings from the store.
    /// Call this after modifying app keymaps to pick up changes.
    public func reloadMappings() async {
        bundleToVKMapping = await AppKeymapStore.shared.getBundleToVKMapping()
        AppLogger.shared.log("🔄 [AppContextService] Reloaded \(bundleToVKMapping.count) app mappings")

        // Re-evaluate current app
        if let bundleId = currentBundleIdentifier {
            await handleAppActivation(bundleIdentifier: bundleId)
        }
    }

    // MARK: - Private Methods

    private func setupWorkspaceObserver() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                await self.handleAppActivation(bundleIdentifier: app.bundleIdentifier)
            }
        }

        AppLogger.shared.log("👁️ [AppContextService] Workspace observer installed")
    }

    private func handleAppActivation(bundleIdentifier: String?) async {
        let previousBundle = currentBundleIdentifier
        let previousVK = currentVirtualKey

        currentBundleIdentifier = bundleIdentifier

        // Look up virtual key for this app
        let newVK: String?
        if let bundleId = bundleIdentifier {
            newVK = bundleToVKMapping[bundleId]
        } else {
            newVK = nil
        }

        // Skip if no change
        if newVK == previousVK {
            AppLogger.shared.debug(
                "🔄 [AppContextService] App changed to \(bundleIdentifier ?? "nil") but VK unchanged (\(newVK ?? "none"))"
            )
            return
        }

        AppLogger.shared.log(
            "🔀 [AppContextService] App switch: \(previousBundle ?? "nil") → \(bundleIdentifier ?? "nil")"
        )
        AppLogger.shared.log(
            "🔀 [AppContextService] VK switch: \(previousVK ?? "none") → \(newVK ?? "none")"
        )

        // Release previous VK if any
        if let prevVK = previousVK {
            await sendFakeKeyAction(name: prevVK, action: .release)
        }

        // Press new VK if any
        if let vk = newVK {
            await sendFakeKeyAction(name: vk, action: .press)
        }

        currentVirtualKey = newVK
    }

    private func releaseCurrentVirtualKey() async {
        guard let vk = currentVirtualKey else { return }
        await sendFakeKeyAction(name: vk, action: .release)
        currentVirtualKey = nil
    }

    private func sendFakeKeyAction(name: String, action: KanataTCPClient.FakeKeyAction) async {
        guard let client = tcpClient else {
            AppLogger.shared.warn("⚠️ [AppContextService] No TCP client, skipping \(action.rawValue) for \(name)")
            return
        }

        let result = await client.actOnFakeKey(name: name, action: action)

        switch result {
        case .success:
            AppLogger.shared.log("✅ [AppContextService] \(action.rawValue) \(name)")
        case let .error(msg):
            AppLogger.shared.warn("⚠️ [AppContextService] \(action.rawValue) \(name) failed: \(msg)")
        case let .networkError(msg):
            AppLogger.shared.warn("⚠️ [AppContextService] \(action.rawValue) \(name) network error: \(msg)")
        }
    }
}

// MARK: - Test Support

#if DEBUG
    extension AppContextService {
        /// For testing: directly set the bundle to VK mapping
        public func setMappings(_ mappings: [String: String]) {
            self.bundleToVKMapping = mappings
        }

        /// For testing: simulate an app activation
        public func simulateAppActivation(bundleIdentifier: String?) async {
            await handleAppActivation(bundleIdentifier: bundleIdentifier)
        }

        /// For testing: set TCP port after initialization
        public func setTCPPort(_ port: Int) {
            self.tcpClient = KanataTCPClient(port: port)
        }
    }
#endif
