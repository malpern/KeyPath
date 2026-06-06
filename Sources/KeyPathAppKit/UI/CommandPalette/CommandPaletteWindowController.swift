import AppKit
import SwiftUI

@MainActor
final class CommandPaletteWindowController {
    static let shared = CommandPaletteWindowController()

    private var panel: NSPanel?
    private let recencyKey = "CommandPalette.Recency"
    private let panelDelegate = PanelDelegate()

    private init() {}

    // MARK: - Recency Tracking

    func recordUsage(_ itemID: String) {
        var recency = UserDefaults.standard.dictionary(forKey: recencyKey) as? [String: Double] ?? [:]
        recency[itemID] = Date().timeIntervalSinceReferenceDate
        UserDefaults.standard.set(recency, forKey: recencyKey)
    }

    private func recencyScore(_ itemID: String) -> Double {
        let recency = UserDefaults.standard.dictionary(forKey: recencyKey) as? [String: Double] ?? [:]
        return recency[itemID] ?? 0
    }

    private func sortByRecency(_ items: [CommandPaletteItem]) -> [CommandPaletteItem] {
        let pinned = items.filter { $0.id == "toggle-app" }
        let recentIDs = (UserDefaults.standard.dictionary(forKey: recencyKey) as? [String: Double] ?? [:])
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
        let recentSet = Set(recentIDs)

        let recentItems = recentIDs.compactMap { id in
            items.first(where: { $0.id == id && $0.id != "toggle-app" })
        }.map { item in
            CommandPaletteItem(
                id: item.id, title: item.title, subtitle: item.subtitle,
                icon: item.icon, shortcut: item.shortcut, group: "Recent",
                action: item.action
            )
        }

        let rest = items.filter { $0.id != "toggle-app" && !recentSet.contains($0.id) }

        return pinned + recentItems + rest
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        dismiss()

        let items = buildItems()
        let view = CommandPaletteView(items: items) { [weak self] in
            self?.dismiss()
        }

        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.delegate = panelDelegate
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        panel.setContentSize(NSSize(width: 440, height: 420))
        positionPanel(panel)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    func allItemIDs() -> Set<String> {
        var items: [CommandPaletteItem] = []
        items.append(contentsOf: navigationItems())
        items.append(contentsOf: collectionItems())
        items.append(contentsOf: packItems())
        items.append(contentsOf: overlayTabItems())
        items.append(contentsOf: settingsItems())
        return Set(items.map(\.id))
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        if let overlayFrame = LiveKeyboardOverlayController.shared.window?.frame,
           LiveKeyboardOverlayController.shared.window?.isVisible == true
        {
            let x = overlayFrame.midX - panelSize.width / 2
            let y = overlayFrame.maxY - panelSize.height - 24
            let clamped = NSPoint(
                x: min(max(x, screenFrame.minX), screenFrame.maxX - panelSize.width),
                y: max(y, screenFrame.minY)
            )
            panel.setFrameOrigin(clamped)
        } else {
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY + screenFrame.height * 0.15
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Command Items

    private func buildItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        items.append(contentsOf: navigationItems())
        items.append(contentsOf: collectionItems())
        items.append(contentsOf: packItems())
        items.append(contentsOf: overlayTabItems())
        items.append(contentsOf: settingsItems())

        return sortByRecency(items.map { item in
            let originalAction = item.action
            return CommandPaletteItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                icon: item.icon,
                shortcut: item.shortcut,
                group: item.group
            ) { [weak self] in
                self?.recordUsage(item.id)
                originalAction()
            }
        })
    }

    // MARK: - Navigation

    private func navigationItems() -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "toggle-app",
                title: "Hide / Show KeyPath",
                subtitle: "Toggle the main KeyPath window",
                icon: "eye",
                shortcut: nil,
                group: "Navigation"
            ) {
                DispatchQueue.main.async {
                    if NSApp.isHidden {
                        NSApp.unhide(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        NSApp.hide(nil)
                    }
                }
            },
            CommandPaletteItem(
                id: "overlay",
                title: "Live Keyboard Overlay",
                subtitle: "Show the floating keyboard visualization",
                icon: "keyboard.badge.eye",
                shortcut: "\u{2325}\u{2318}K",
                group: "Navigation"
            ) {
                DispatchQueue.main.async {
                    LiveKeyboardOverlayController.shared.toggle()
                }
            },
            CommandPaletteItem(
                id: "mappings",
                title: "Mappings",
                subtitle: "Open the key mapper overlay",
                icon: "keyboard",
                shortcut: "\u{21e7}\u{2318}M",
                group: "Navigation"
            ) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                }
            },
            CommandPaletteItem(
                id: "edit-config",
                title: "Edit Config",
                subtitle: "Open keypath.kbd in your editor",
                icon: "chevron.left.forwardslash.chevron.right",
                shortcut: "\u{2318}O",
                group: "Navigation"
            ) {
                DispatchQueue.main.async {
                    if let vm = (NSApp.delegate as? AppDelegate)?.viewModel {
                        openConfigInEditor(viewModel: vm)
                    }
                }
            },
            CommandPaletteItem(
                id: "help",
                title: "Help",
                subtitle: "Open the KeyPath help browser",
                icon: "questionmark.circle",
                shortcut: "\u{2318}?",
                group: "Navigation"
            ) {
                DispatchQueue.main.async {
                    HelpWindowController.shared.showBrowser()
                }
            },
        ]
    }

    // MARK: - Rule Collections

    private func collectionItems() -> [CommandPaletteItem] {
        let catalog = RuleCollectionCatalog()
        return catalog.defaultCollections().map { collection in
            CommandPaletteItem(
                id: "collection-\(collection.id.uuidString)",
                title: collection.name,
                subtitle: collection.summary,
                icon: collection.icon ?? "list.bullet",
                shortcut: nil,
                group: "Collections"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsRules)
                }
            }
        }
    }

    // MARK: - Packs

    private func packItems() -> [CommandPaletteItem] {
        PackRegistry.starterKit.map { pack in
            CommandPaletteItem(
                id: "pack-\(pack.id)",
                title: pack.name,
                subtitle: pack.tagline,
                icon: pack.iconSymbol,
                shortcut: nil,
                group: "Packs"
            ) {
                DispatchQueue.main.async {
                    if let vm = (NSApp.delegate as? AppDelegate)?.viewModel {
                        PackDetailWindowController.shared.showWindow(pack: pack, kanataManager: vm)
                    }
                }
            }
        }
    }

    // MARK: - Overlay Inspector Tabs

    private func overlayTabItems() -> [CommandPaletteItem] {
        let tabs: [(section: InspectorSection, title: String, subtitle: String, icon: String)] = [
            (.mapper, "Mapper", "Key mapper and conflict detection", "arrow.left.arrow.right"),
            (.customRules, "Custom Rules", "Global and app-specific rules", "text.badge.star"),
            (.keyboard, "Keymap", "Logical key labels", "character.textbox"),
            (.layout, "Layout", "Physical keyboard layout", "rectangle.split.3x3"),
            (.keycaps, "Keycaps", "Keycap appearance and colors", "paintpalette"),
            (.sounds, "Sounds", "Typing sounds", "speaker.wave.2"),
            (.launchers, "Launchers", "App and website launchers", "arrow.up.forward.app"),
            (.devices, "Devices", "Keyboard device selection", "desktopcomputer"),
            (.history, "Keystroke History", "Timeline of key events and tap-hold decisions", "clock.arrow.trianglehead.counterclockwise.rotate.90"),
        ]

        return tabs.map { tab in
            CommandPaletteItem(
                id: "inspector-\(tab.section.rawValue)",
                title: tab.title,
                subtitle: tab.subtitle,
                icon: tab.icon,
                shortcut: nil,
                group: "Overlay"
            ) {
                DispatchQueue.main.async {
                    let controller = LiveKeyboardOverlayController.shared
                    if controller.window == nil || controller.window?.isVisible != true {
                        controller.showResetCentered()
                    }
                    controller.openInspector(animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: .commandPaletteSelectInspectorSection,
                            object: nil,
                            userInfo: ["section": tab.section.rawValue]
                        )
                    }
                }
            }
        }
    }

    // MARK: - Settings Tabs

    private func settingsItems() -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "settings-status",
                title: "System Status",
                subtitle: "Check service health and permissions",
                icon: "gauge.with.dots.needle.67percent",
                shortcut: "\u{2318}S",
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsSystemStatus)
                }
            },
            CommandPaletteItem(
                id: "settings-rules",
                title: "Rules Tab",
                subtitle: "Manage rule collections",
                icon: "list.bullet",
                shortcut: "\u{2318}R",
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsRules)
                }
            },
            CommandPaletteItem(
                id: "settings-general",
                title: "General",
                subtitle: "App preferences and startup options",
                icon: "gearshape",
                shortcut: nil,
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsGeneral)
                }
            },
            CommandPaletteItem(
                id: "settings-advanced",
                title: "Repair / Remove",
                subtitle: "Reinstall components or uninstall",
                icon: "wrench.and.screwdriver",
                shortcut: nil,
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsAdvanced)
                }
            },
            CommandPaletteItem(
                id: "settings-logs",
                title: "Logs",
                subtitle: "View debug and runtime logs",
                icon: "doc.text.magnifyingglass",
                shortcut: "\u{2318}L",
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsLogs)
                }
            },
            CommandPaletteItem(
                id: "settings-wizard",
                title: "Installation Wizard",
                subtitle: "Run the setup wizard",
                icon: "wand.and.stars",
                shortcut: "\u{21e7}\u{2318}N",
                group: "Settings"
            ) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showWizard, object: nil)
                }
            },
        ]
    }
}

private class PanelDelegate: NSObject, NSWindowDelegate {
    func windowDidResignKey(_: Notification) {
        Task { @MainActor in
            CommandPaletteWindowController.shared.dismiss()
        }
    }
}
