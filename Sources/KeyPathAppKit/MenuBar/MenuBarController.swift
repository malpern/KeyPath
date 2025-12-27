import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    typealias Handler = () -> Void

    private let statusItem: NSStatusItem
    private let bringToFrontHandler: Handler
    private let showWizardHandler: Handler
    private let uninstallHandler: Handler
    private let quitHandler: Handler
    private let menu: NSMenu

    init(
        bringToFrontHandler: @escaping Handler,
        showWizardHandler: @escaping Handler,
        uninstallHandler: @escaping Handler,
        quitHandler: @escaping Handler
    ) {
        self.bringToFrontHandler = bringToFrontHandler
        self.showWizardHandler = showWizardHandler
        self.uninstallHandler = uninstallHandler
        self.quitHandler = quitHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(
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
        menu.autoenablesItems = false
        menu.removeAllItems()

        let showItem = NSMenuItem(
            title: NSLocalizedString("Show KeyPath", comment: "Menu item to show main window"),
            action: #selector(handleShowKeyPath),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let wizardItem = NSMenuItem(
            title: NSLocalizedString("Open Install Wizard…", comment: "Menu item to open installation wizard"),
            action: #selector(handleShowWizard),
            keyEquivalent: ""
        )
        wizardItem.target = self
        menu.addItem(wizardItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: NSLocalizedString("Uninstall KeyPath…", comment: "Menu item to uninstall the app"),
            action: #selector(handleUninstall),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(
            title: NSLocalizedString("Quit KeyPath", comment: "Menu item to quit the app"),
            action: #selector(handleQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func handleShowKeyPath() {
        bringToFrontHandler()
    }

    @objc
    private func handleShowWizard() {
        showWizardHandler()
    }

    @objc
    private func handleUninstall() {
        uninstallHandler()
    }

    @objc
    private func handleQuit() {
        quitHandler()
    }
}
