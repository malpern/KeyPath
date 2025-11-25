import AppKit

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
            title: "Show KeyPath",
            action: #selector(handleShowKeyPath),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let wizardItem = NSMenuItem(
            title: "Open Install Wizard…",
            action: #selector(handleShowWizard),
            keyEquivalent: ""
        )
        wizardItem.target = self
        menu.addItem(wizardItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(
            title: "Uninstall KeyPath…",
            action: #selector(handleUninstall),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(
            title: "Quit KeyPath",
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
