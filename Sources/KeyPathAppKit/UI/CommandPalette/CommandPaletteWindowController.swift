import AppKit
import SwiftUI

@MainActor
final class CommandPaletteWindowController {
    static let shared = CommandPaletteWindowController()

    private var panel: NSPanel?

    private init() {}

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
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        panel.setContentSize(NSSize(width: 440, height: 340))
        positionPanel(panel)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.midY + screenFrame.height * 0.15
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Command Items

    private func buildItems() -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "toggle-app",
                title: "Hide / Show KeyPath",
                subtitle: "Toggle the main KeyPath window",
                icon: "eye",
                shortcut: nil
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
                id: "mappings",
                title: "Mappings",
                subtitle: "Open the key mapper overlay",
                icon: "keyboard",
                shortcut: "\u{21e7}\u{2318}M"
            ) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openOverlayWithMapper, object: nil)
                }
            },

            CommandPaletteItem(
                id: "rules",
                title: "Rules",
                subtitle: "Manage rule collections",
                icon: "list.bullet",
                shortcut: "\u{2318}R"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsRules)
                }
            },

            CommandPaletteItem(
                id: "packs",
                title: "Packs",
                subtitle: "Browse and install keyboard packs",
                icon: "shippingbox",
                shortcut: nil
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsRules)
                }
            },

            CommandPaletteItem(
                id: "overlay",
                title: "Live Keyboard Overlay",
                subtitle: "Show the floating keyboard visualization",
                icon: "keyboard.badge.eye",
                shortcut: "\u{2325}\u{2318}K"
            ) {
                DispatchQueue.main.async {
                    LiveKeyboardOverlayController.shared.toggle()
                }
            },

            CommandPaletteItem(
                id: "status",
                title: "System Status",
                subtitle: "Check service health and permissions",
                icon: "gauge.with.dots.needle.67percent",
                shortcut: "\u{2318}S"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsSystemStatus)
                }
            },

            CommandPaletteItem(
                id: "edit-config",
                title: "Edit Config",
                subtitle: "Open keypath.kbd in your editor",
                icon: "chevron.left.forwardslash.chevron.right",
                shortcut: "\u{2318}O"
            ) {
                DispatchQueue.main.async {
                    if let vm = (NSApp.delegate as? AppDelegate)?.viewModel {
                        openConfigInEditor(viewModel: vm)
                    }
                }
            },

            CommandPaletteItem(
                id: "logs",
                title: "Logs",
                subtitle: "View debug and runtime logs",
                icon: "doc.text.magnifyingglass",
                shortcut: "\u{2318}L"
            ) {
                DispatchQueue.main.async {
                    openPreferencesTab(.openSettingsLogs)
                }
            },

            CommandPaletteItem(
                id: "wizard",
                title: "Installation Wizard",
                subtitle: "Run the setup wizard",
                icon: "wand.and.stars",
                shortcut: "\u{21e7}\u{2318}N"
            ) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
                }
            },

            CommandPaletteItem(
                id: "help",
                title: "Help",
                subtitle: "Open the KeyPath help browser",
                icon: "questionmark.circle",
                shortcut: "\u{2318}?"
            ) {
                DispatchQueue.main.async {
                    HelpWindowController.shared.showBrowser()
                }
            },
        ]
    }
}
