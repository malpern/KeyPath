import AppKit
import Combine
import Foundation
import KeyPathCore
import KeyPathWizardCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    typealias Handler = () -> Void

    // MARK: - Handlers

    private let bringToFrontHandler: Handler
    private let showWizardHandler: (WizardPage?) -> Void
    private let openSettingsHandler: Handler
    private let openSettingsRulesHandler: Handler
    private let quitHandler: Handler

    // MARK: - UI Components

    private let statusItem: NSStatusItem
    private let menu: NSMenu

    // MARK: - State Observation

    private var cancellables = Set<AnyCancellable>()
    private weak var appStateController: MainAppStateController?
    private weak var ruleCollectionsManager: RuleCollectionsManager?

    // MARK: - Feature IDs (in display order: approachable → nerdy)

    private static let featureCollections: [(id: UUID, name: String)] = [
        (RuleCollectionIdentifier.launcher, "Quick Launcher"),
        (RuleCollectionIdentifier.windowSnapping, "Window Management"),
        (RuleCollectionIdentifier.vimNavigation, "Vim Motions"),
        (RuleCollectionIdentifier.homeRowMods, "Home Row Mods")
    ]

    // MARK: - Initialization

    init(
        bringToFrontHandler: @escaping Handler,
        showWizardHandler: @escaping (WizardPage?) -> Void,
        openSettingsHandler: @escaping Handler,
        openSettingsRulesHandler: @escaping Handler,
        quitHandler: @escaping Handler
    ) {
        self.bringToFrontHandler = bringToFrontHandler
        self.showWizardHandler = showWizardHandler
        self.openSettingsHandler = openSettingsHandler
        self.openSettingsRulesHandler = openSettingsRulesHandler
        self.quitHandler = quitHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

        configureButton()
        configureMenu()
    }

    /// Configure with dependencies for state observation
    func configure(
        appStateController: MainAppStateController,
        ruleCollectionsManager: RuleCollectionsManager
    ) {
        self.appStateController = appStateController
        self.ruleCollectionsManager = ruleCollectionsManager

        // Observe validation state and issues changes to update icon
        Publishers.CombineLatest(
            appStateController.$validationState,
            appStateController.$issues
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.updateStatusIcon()
        }
        .store(in: &cancellables)

        // Initial icon update
        updateStatusIcon()

        AppLogger.shared.log("📊 [MenuBar] Configured with state observation")
    }

    // MARK: - Button Configuration

    private func configureButton() {
        guard let button = statusItem.button else { return }

        // Try to load custom template icon from bundle, fall back to SF Symbol
        if let image = Bundle.main.image(forResource: "menubar-icon") {
            image.isTemplate = true
            button.image = image
        } else if let image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "KeyPath"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "⌨︎"
        }

        button.imagePosition = .imageOnly
        button.toolTip = "KeyPath"
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - Dynamic Icon Updates

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let isHealthy = appStateController?.validationState?.isSuccess ?? true
        let hasIssues = !(appStateController?.issues.isEmpty ?? true)

        // Update tooltip based on state
        if !isHealthy || hasIssues {
            button.toolTip = "KeyPath - Needs Setup"
            button.alphaValue = 0.5 // Dim when unhealthy
        } else {
            button.toolTip = "KeyPath - Running"
            button.alphaValue = 1.0
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        menu.removeAllItems()

        let isHealthy = appStateController?.validationState?.isSuccess ?? true
        let issues = appStateController?.issues ?? []

        if isHealthy, issues.isEmpty {
            buildHealthyMenu()
        } else {
            buildUnhealthyMenu(issues: issues)
        }
    }

    private func buildHealthyMenu() {
        // Status header
        let statusMenuItem = NSMenuItem(
            title: "KeyPath Running",
            action: #selector(handleStatusClick),
            keyEquivalent: ""
        )
        statusMenuItem.target = self
        statusMenuItem.image = createStatusDot(color: .systemGreen)
        menu.addItem(statusMenuItem)

        // Show Keyboard Overlay (with keyboard icon and shortcut)
        let overlayItem = NSMenuItem(
            title: "Show Keyboard Overlay",
            action: #selector(handleShowOverlay),
            keyEquivalent: "k"
        )
        overlayItem.keyEquivalentModifierMask = [.command]
        overlayItem.target = self
        overlayItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(overlayItem)

        menu.addItem(.separator())

        // Feature items (with checkmarks for enabled state)
        for (id, name) in Self.featureCollections {
            let isEnabled = ruleCollectionsManager?.ruleCollections.first { $0.id == id }?.isEnabled ?? false

            let featureItem = NSMenuItem(
                title: name,
                action: #selector(handleFeatureClick),
                keyEquivalent: ""
            )
            featureItem.target = self
            featureItem.state = isEnabled ? .on : .off
            featureItem.representedObject = id
            menu.addItem(featureItem)
        }

        // App-specific mappings for frontmost app
        addAppSpecificSection()

        addFooterItems()
    }

    private func buildUnhealthyMenu(issues: [WizardIssue]) {
        // Status header (warning state)
        let statusMenuItem = NSMenuItem(
            title: "KeyPath Needs Setup",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        statusMenuItem.image = createStatusDot(color: .systemOrange)
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Fix it CTA
        let fixItem = NSMenuItem(
            title: "Fix it",
            action: #selector(handleFixIt),
            keyEquivalent: ""
        )
        fixItem.target = self
        fixItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        // Map issue to appropriate wizard page for navigation
        if let firstIssue = issues.first {
            fixItem.representedObject = wizardPage(for: firstIssue)
        }
        menu.addItem(fixItem)

        // Problem message (dimmed, indented under Fix it)
        if let firstIssue = issues.first {
            let messageItem = NSMenuItem(
                title: firstIssue.title,
                action: nil,
                keyEquivalent: ""
            )
            messageItem.isEnabled = false
            messageItem.indentationLevel = 1
            menu.addItem(messageItem)
        }

        addFooterItems()
    }

    // MARK: - Helper Methods

    /// Adds Settings and Quit items to the menu (shared by healthy and unhealthy menus)
    private func addFooterItems() {
        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit KeyPath",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func createStatusDot(color: NSColor) -> NSImage {
        let size = NSSize(width: 8, height: 8)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    /// Adds app-specific mappings section for the frontmost app
    private func addAppSpecificSection() {
        // Get frontmost app (excluding KeyPath itself)
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier,
              let appName = frontApp.localizedName
        else {
            return
        }

        // Get app icon (scaled to menu size)
        let appIcon: NSImage
        if let icon = frontApp.icon {
            appIcon = icon
            appIcon.size = NSSize(width: 16, height: 16)
        } else {
            appIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: appName)
                ?? NSImage()
        }

        menu.addItem(.separator())

        // Use synchronous approach to get cached keymap data for menu building
        let keymap = getAppKeymapSync(bundleIdentifier: bundleId)

        if let keymap, !keymap.overrides.isEmpty {
            // Header for app-specific mappings
            let headerItem = NSMenuItem(
                title: "\(appName) Mappings",
                action: nil,
                keyEquivalent: ""
            )
            headerItem.isEnabled = false
            headerItem.image = appIcon
            menu.addItem(headerItem)

            // Show up to 5 mappings
            for override in keymap.overrides.prefix(5) {
                let mappingItem = NSMenuItem(
                    title: "  \(override.inputKey) → \(KeyDisplayFormatter.format(override.outputAction))",
                    action: #selector(handleAppMappingClick),
                    keyEquivalent: ""
                )
                mappingItem.target = self
                mappingItem.indentationLevel = 1
                mappingItem.representedObject = bundleId
                menu.addItem(mappingItem)
            }

            // Show "and X more..." if there are more
            if keymap.overrides.count > 5 {
                let moreItem = NSMenuItem(
                    title: "  and \(keymap.overrides.count - 5) more...",
                    action: #selector(handleAppMappingClick),
                    keyEquivalent: ""
                )
                moreItem.target = self
                moreItem.indentationLevel = 1
                moreItem.representedObject = bundleId
                menu.addItem(moreItem)
            }
        }

        // "Add [App] rule..." action
        let createItem = NSMenuItem(
            title: "Add \(appName) rule...",
            action: #selector(handleCreateAppMapping),
            keyEquivalent: ""
        )
        createItem.target = self
        createItem.image = appIcon
        createItem.representedObject = (bundleId, appName, frontApp.icon)
        menu.addItem(createItem)
    }

    /// Synchronously get app keymap (for menu building)
    private func getAppKeymapSync(bundleIdentifier: String) -> AppKeymap? {
        // Use a semaphore to wait for the async result
        var result: AppKeymap?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            result = await AppKeymapStore.shared.getKeymap(bundleIdentifier: bundleIdentifier)
            semaphore.signal()
        }

        // Wait with a short timeout to avoid blocking UI
        _ = semaphore.wait(timeout: .now() + 0.1)
        return result
    }

    // MARK: - Actions

    @objc
    private func handleStatusClick() {
        bringToFrontHandler()
    }

    @objc
    private func handleShowOverlay() {
        LiveKeyboardOverlayController.shared.toggle()
    }

    @objc
    private func handleFeatureClick(_: NSMenuItem) {
        // Open Settings > Rules tab
        openSettingsRulesHandler()
    }

    @objc
    private func handleFixIt(_ sender: NSMenuItem) {
        let targetPage = sender.representedObject as? WizardPage
        showWizardHandler(targetPage)
    }

    @objc
    private func handleSettings() {
        openSettingsHandler()
    }

    @objc
    private func handleQuit() {
        quitHandler()
    }

    @objc
    private func handleAppMappingClick(_ sender: NSMenuItem) {
        // Open the overlay with the mapper drawer to show/edit app mappings
        guard let bundleId = sender.representedObject as? String else { return }

        // Get app name for the notification
        let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleName"] as? String }
            ?? bundleId

        // Open overlay and set the app condition
        LiveKeyboardOverlayController.shared.showForQuickLaunch()

        // Post notification to set app condition in mapper (use existing notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": bundleId,
                    "displayName": appName
                ]
            )
        }
    }

    @objc
    private func handleCreateAppMapping(_ sender: NSMenuItem) {
        // Open the overlay with mapper drawer pre-configured for the app
        guard let info = sender.representedObject as? (String, String, NSImage?) else { return }
        let (bundleId, appName, _) = info

        // Open overlay
        LiveKeyboardOverlayController.shared.showForQuickLaunch()

        // Post notification to open mapper with app condition pre-set (use existing notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": bundleId,
                    "displayName": appName
                ]
            )
        }
    }

    // MARK: - Issue Category Mapping

    /// Maps an issue to the appropriate wizard page for navigation
    private func wizardPage(for issue: WizardIssue) -> WizardPage {
        switch issue.category {
        case .conflicts:
            return .conflicts
        case .permissions:
            // Use identifier to determine if it's accessibility or input monitoring
            if case let .permission(requirement) = issue.identifier {
                switch requirement {
                case .kanataAccessibility, .keyPathAccessibility:
                    return .accessibility
                case .kanataInputMonitoring, .keyPathInputMonitoring:
                    return .inputMonitoring
                case .driverExtensionEnabled:
                    return .karabinerComponents
                case .backgroundServicesEnabled:
                    return .service
                }
            }
            return .inputMonitoring // Default for permissions
        case .backgroundServices, .daemon:
            return .service
        case .installation:
            return .helper
        case .systemRequirements:
            return .summary
        }
    }
}
